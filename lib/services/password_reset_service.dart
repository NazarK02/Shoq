import 'dart:convert';
import 'dart:io' show HttpClient, Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart';

class PasswordResetService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> sendPasswordResetEmail(String email) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Invalid email address.',
      );
    }

    if (!kIsWeb && Platform.isWindows) {
      await _sendPasswordResetEmailViaRest(trimmedEmail);
      return;
    }

    await _auth.sendPasswordResetEmail(email: trimmedEmail);
  }

  Future<void> _sendPasswordResetEmailViaRest(String email) async {
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    if (apiKey.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-api-key',
        message: 'Firebase API key is missing.',
      );
    }

    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$apiKey',
    );

    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.add(
        utf8.encode(
          jsonEncode({'requestType': 'PASSWORD_RESET', 'email': email}),
        ),
      );

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        final error = _parseRestAuthError(responseBody);

        // Avoid exposing whether an email exists when password reset is requested.
        if (error.$1 == 'user-not-found') {
          return;
        }

        throw FirebaseAuthException(code: error.$1, message: error.$2);
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
          case 'INVALID_EMAIL':
            return ('invalid-email', 'Invalid email address.');
          case 'EMAIL_NOT_FOUND':
            return ('user-not-found', 'No account found for this email.');
          case 'TOO_MANY_ATTEMPTS_TRY_LATER':
            return ('too-many-requests', 'Too many requests. Try again later.');
          case 'USER_DISABLED':
            return ('user-disabled', 'This user account is disabled.');
          default:
            return ('unknown', message);
        }
      }
    } catch (_) {}

    return ('unknown', 'Failed to send password reset email.');
  }
}
