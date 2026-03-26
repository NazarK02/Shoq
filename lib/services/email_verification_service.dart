import 'dart:convert';
import 'dart:io' show HttpClient, Platform;

import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';

class EmailVerificationService {
  static final Set<String> _locallyVerifiedUserIds = <String>{};
  final FirebaseAuth _auth = FirebaseAuth.instance;

  void markLocallyVerified(String userId) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return;
    _locallyVerifiedUserIds.add(trimmed);
  }

  bool isLocallyVerified(String userId) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return false;
    return _locallyVerifiedUserIds.contains(trimmed);
  }

  void clearLocallyVerified(String userId) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return;
    _locallyVerifiedUserIds.remove(trimmed);
  }

  Future<bool> refreshEmailVerified(User user) async {
    if (Platform.isWindows) {
      return _refreshWindowsVerification(user);
    }

    try {
      await user.reload();
    } catch (_) {}
    return _auth.currentUser?.emailVerified == true ||
        user.emailVerified == true;
  }

  Future<void> sendVerificationEmail(User user) async {
    if (Platform.isWindows) {
      await _sendVerificationEmailViaRest(user);
      return;
    }

    await user.sendEmailVerification();
  }

  Future<bool> _refreshWindowsVerification(User user) async {
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    if (apiKey.trim().isEmpty) {
      return false;
    }

    String? token;
    try {
      token = await user.getIdToken();
    } catch (_) {}

    token ??= user.refreshToken;
    if (token == null || token.trim().isEmpty) {
      try {
        token = await user.getIdToken(true);
      } catch (_) {
        return false;
      }
    }

    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$apiKey',
    );

    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.add(
        utf8.encode(
          jsonEncode({
            'idToken': token,
          }),
        ),
      );

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        return false;
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final users = decoded['users'];
        if (users is List && users.isNotEmpty) {
          final userInfo = users.first;
          if (userInfo is Map) {
            return userInfo['emailVerified'] == true ||
                userInfo['emailVerified'] == 'true';
          }
        }
      } else if (decoded is Map) {
        final users = decoded['users'];
        if (users is List && users.isNotEmpty) {
          final userInfo = users.first;
          if (userInfo is Map) {
            return userInfo['emailVerified'] == true ||
                userInfo['emailVerified'] == 'true';
          }
        }
      }
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }

    return false;
  }

  Future<void> _sendVerificationEmailViaRest(User user) async {
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    if (apiKey.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-api-key',
        message: 'Firebase API key is missing.',
      );
    }

    final idToken = await user.getIdToken(true);
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$apiKey',
    );

    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.add(
        utf8.encode(
          jsonEncode({
            'requestType': 'VERIFY_EMAIL',
            'idToken': idToken,
          }),
        ),
      );

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        final error = _parseRestAuthError(responseBody);
        throw FirebaseAuthException(
          code: error.$1,
          message: error.$2,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  (String, String?) _parseRestAuthError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = decoded['error']['message']?.toString() ?? 'UNKNOWN';
        switch (message) {
          case 'INVALID_ID_TOKEN':
            return ('invalid-id-token', 'Your sign-in session expired.');
          case 'EXPIRED_OOB_CODE':
            return ('expired-action-code', 'The verification link expired.');
          case 'INVALID_OOB_CODE':
            return ('invalid-action-code', 'The verification link is invalid.');
          case 'TOO_MANY_ATTEMPTS_TRY_LATER':
            return (
              'too-many-requests',
              'Too many requests. Try again later.',
            );
          case 'USER_DISABLED':
            return ('user-disabled', 'This user account is disabled.');
          case 'EMAIL_EXISTS':
            return ('email-already-in-use', 'Email already in use.');
          case 'INVALID_EMAIL':
            return ('invalid-email', 'Invalid email address.');
          default:
            return ('unknown', message);
        }
      }
    } catch (_) {}
    return ('unknown', 'Failed to send verification email.');
  }
}
