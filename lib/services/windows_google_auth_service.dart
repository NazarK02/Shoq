import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_auth_config.dart';

class WindowsGoogleAuthException implements Exception {
  final String message;
  const WindowsGoogleAuthException(this.message);

  @override
  String toString() => message;
}

class WindowsGoogleAuthService {
  // Set these via flutter run/build:
  // --dart-define=GOOGLE_WINDOWS_CLIENT_ID=...
  // --dart-define=GOOGLE_WINDOWS_CLIENT_SECRET=... (optional, usually empty for Desktop OAuth clients)
  static const String _clientIdFromDefine = String.fromEnvironment(
    'GOOGLE_WINDOWS_CLIENT_ID',
  );
  static const String _clientSecretFromDefine = String.fromEnvironment(
    'GOOGLE_WINDOWS_CLIENT_SECRET',
  );
  static const String _clientIdFromConfig = AppAuthConfig.windowsGoogleClientId;
  static const String _clientSecretFromConfig =
      AppAuthConfig.windowsGoogleClientSecret;
  static const String _redirectHost = AppAuthConfig.windowsGoogleRedirectHost;
  static const int _redirectPort = AppAuthConfig.windowsGoogleRedirectPort;
  static const String _redirectPath = AppAuthConfig.windowsGoogleRedirectPath;

  static String get _clientId => _clientIdFromDefine.isNotEmpty
      ? _clientIdFromDefine
      : _clientIdFromConfig;

  static String get _clientSecret => _clientSecretFromDefine.isNotEmpty
      ? _clientSecretFromDefine
      : _clientSecretFromConfig;

  static Uri get _redirectUri => Uri(
    scheme: 'http',
    host: _redirectHost,
    port: _redirectPort,
    path: _redirectPath,
  );

  static bool get isConfigured =>
      _clientId.isNotEmpty && !_clientId.contains('YOUR_DESKTOP_CLIENT_ID');

  static String get setupHint =>
      'Google Windows OAuth is not configured. Set windowsGoogleClientId in lib/services/app_auth_config.dart. If you use a Web OAuth client, add this redirect URI too: $_redirectUri';

  static const _googleAuthHost = 'accounts.google.com';
  static const _googleAuthPath = '/o/oauth2/v2/auth';
  static const _googleTokenUrl = 'https://oauth2.googleapis.com/token';
  static const _pkceCharset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  Future<UserCredential> signInWithGoogle() async {
    if (!Platform.isWindows) {
      throw const WindowsGoogleAuthException(
        'Windows Google auth flow can only be used on Windows.',
      );
    }
    if (!isConfigured) {
      throw WindowsGoogleAuthException(setupHint);
    }

    final verifier = _randomString(64);
    final challenge = _pkceCodeChallenge(verifier);
    final state = _randomString(32);

    final HttpServer server;
    try {
      server = await HttpServer.bind(
        InternetAddress(_redirectHost),
        _redirectPort,
      );
    } on SocketException {
      throw WindowsGoogleAuthException(
        'Cannot start Google callback listener on $_redirectUri. '
        'Close other apps that use this port and try again.',
      );
    }

    StreamSubscription<HttpRequest>? sub;
    final callbackCompleter = Completer<_OAuthCallback>();

    sub = server.listen((request) async {
      final query = request.uri.queryParameters;
      final hasAuthResult =
          request.uri.path == _redirectPath &&
          (query.containsKey('code') || query.containsKey('error'));

      if (!hasAuthResult) {
        await _respondHtml(
          request.response,
          title: 'Shoq Login',
          message: 'You can close this tab and return to Shoq.',
        );
        return;
      }

      await _respondHtml(
        request.response,
        title: 'Shoq Login',
        message: 'Sign-in complete. You can close this tab.',
      );

      if (!callbackCompleter.isCompleted) {
        callbackCompleter.complete(
          _OAuthCallback(
            code: query['code'],
            state: query['state'],
            error: query['error'],
            errorDescription: query['error_description'],
          ),
        );
      }
    });

    final authUri = Uri.https(_googleAuthHost, _googleAuthPath, {
      'client_id': _clientId,
      'redirect_uri': _redirectUri.toString(),
      'response_type': 'code',
      'scope': 'openid email profile',
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'prompt': 'select_account',
    });

    try {
      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const WindowsGoogleAuthException(
          'Could not open browser for Google Sign-In.',
        );
      }

      _OAuthCallback callback;
      try {
        callback = await callbackCompleter.future.timeout(
          const Duration(minutes: 3),
        );
      } on TimeoutException {
        throw const WindowsGoogleAuthException(
          'Google Sign-In timed out. Please try again.',
        );
      }

      if (callback.state != state) {
        throw const WindowsGoogleAuthException(
          'Google Sign-In failed: invalid state.',
        );
      }

      if (callback.error != null) {
        throw WindowsGoogleAuthException(
          callback.errorDescription ?? callback.error!,
        );
      }

      final code = callback.code;
      if (code == null || code.isEmpty) {
        throw const WindowsGoogleAuthException(
          'Google Sign-In failed: no authorization code.',
        );
      }

      final tokenResponse = await _exchangeCodeForTokens(
        code: code,
        codeVerifier: verifier,
        redirectUri: _redirectUri.toString(),
      );

      final credential = GoogleAuthProvider.credential(
        accessToken: tokenResponse.accessToken,
        idToken: tokenResponse.idToken,
      );

      return FirebaseAuth.instance.signInWithCredential(credential);
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
  }

  Future<_TokenResponse> _exchangeCodeForTokens({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(_googleTokenUrl));
      req.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );

      final payload = <String, String>{
        'client_id': _clientId,
        if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
        'code': code,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      };

      req.write(_formUrlEncode(payload));

      final res = await req.close();
      final body = await utf8.decodeStream(res);

      Map<String, dynamic> json;
      try {
        json = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw const WindowsGoogleAuthException(
          'Google token response could not be parsed.',
        );
      }

      if (res.statusCode != HttpStatus.ok) {
        final error = json['error']?.toString();
        String reason =
            json['error_description']?.toString() ??
            error ??
            'OAuth token exchange failed.';
        if (error == 'invalid_client') {
          reason =
              'OAuth client is invalid. Update windowsGoogleClientId in lib/services/app_auth_config.dart with your real Desktop OAuth client ID.';
        } else if (error == 'redirect_uri_mismatch') {
          reason =
              'Redirect URI mismatch. In Google Cloud Console, add this exact Authorized redirect URI: $_redirectUri';
        }
        throw WindowsGoogleAuthException(reason);
      }

      final accessToken = json['access_token']?.toString();
      final idToken = json['id_token']?.toString();

      if (accessToken == null || accessToken.isEmpty) {
        throw const WindowsGoogleAuthException(
          'Google Sign-In failed: missing access token.',
        );
      }

      if (idToken == null || idToken.isEmpty) {
        throw const WindowsGoogleAuthException(
          'Google Sign-In failed: missing ID token.',
        );
      }

      return _TokenResponse(accessToken: accessToken, idToken: idToken);
    } finally {
      client.close(force: true);
    }
  }

  static String _formUrlEncode(Map<String, String> values) {
    return values.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  static String _randomString(int length) {
    final random = Random.secure();
    final chars = List.generate(
      length,
      (_) => _pkceCharset[random.nextInt(_pkceCharset.length)],
    );
    return chars.join();
  }

  static String _pkceCodeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static Future<void> _respondHtml(
    HttpResponse response, {
    required String title,
    required String message,
  }) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    response.write('''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>$title</title>
  </head>
  <body style="font-family:Segoe UI,Arial,sans-serif;padding:24px;">
    <h2>$title</h2>
    <p>$message</p>
  </body>
</html>
''');
    await response.close();
  }
}

class _OAuthCallback {
  final String? code;
  final String? state;
  final String? error;
  final String? errorDescription;

  const _OAuthCallback({
    required this.code,
    required this.state,
    required this.error,
    required this.errorDescription,
  });
}

class _TokenResponse {
  final String accessToken;
  final String idToken;

  const _TokenResponse({required this.accessToken, required this.idToken});
}
