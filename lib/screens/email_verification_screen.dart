import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service_e2ee.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Timer? _timer;
  bool _isResending = false;
  int _resendCountdown = 0;
  bool _verificationCheckInProgress = false;

  void _handleVerifiedState() {
    _timer?.cancel();
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows) {
      _startVerificationCheck();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        // Workaround for Firebase Windows threading bug: defer off the widget tree's hot path
        await Future.delayed(Duration.zero);
        await user.sendEmailVerification();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verification email sent!')),
          );
        }

        setState(() {
          _resendCountdown = 60;
        });

        Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_resendCountdown > 0) {
            if (mounted) {
              setState(() {
                _resendCountdown--;
              });
            }
          } else {
            timer.cancel();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  void _startVerificationCheck() {
    if (Platform.isWindows) return;
    if (_timer != null) return;
    final interval = const Duration(seconds: 3);
    _timer = Timer.periodic(interval, (timer) async {
      if (_verificationCheckInProgress) return;
      _verificationCheckInProgress = true;
      try {
        final user = _auth.currentUser;
        if (user != null) {
          await user.reload().timeout(const Duration(seconds: 5));
          if (_auth.currentUser?.emailVerified == true) {
            _handleVerifiedState();
          }
        }
      } catch (e) {
        debugPrint('Verification check failed: $e');
      } finally {
        _verificationCheckInProgress = false;
      }
    });
  }

  Future<void> _resendEmail() async {
    if (_resendCountdown > 0 || _isResending) return;
    setState(() => _isResending = true);
    await _sendVerificationEmail();
    setState(() => _isResending = false);
  }

  Future<void> _signOut() async {
    try {
      await UserService().signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mark_email_unread_outlined,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'Verify Your Email',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'We sent a verification email to:',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user?.email ?? '',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (Platform.isWindows) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Auto-check runs in the background on Windows. If it doesn\'t update, tap "I\'ve Verified My Email".',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
                const SizedBox(height: 32),

                // Resend button
                ElevatedButton.icon(
                  onPressed: _resendCountdown > 0 || _isResending
                      ? null
                      : _resendEmail,
                  icon: _isResending
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _resendCountdown > 0
                        ? 'Resend in $_resendCountdown seconds'
                        : 'Resend Verification Email',
                  ),
                ),
                const SizedBox(height: 16),

                // "I Verified My Email" button
                OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final user = _auth.currentUser;
                    if (user != null) {
                      if (Platform.isWindows) {
                        try {
                          final token = await user.getIdTokenResult(true);
                          final claims = token.claims ?? const <String, dynamic>{};
                          final verified =
                              claims['email_verified'] == true ||
                              claims['emailVerified'] == true;
                          if (verified) {
                            _handleVerifiedState();
                            return;
                          }
                        } catch (e) {
                          debugPrint('Windows verification check failed: $e');
                        }
                      } else {
                        await user.reload();
                        if (_auth.currentUser?.emailVerified == true) {
                          _handleVerifiedState();
                          return;
                        }
                      }
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Email not verified yet. Please check your inbox.',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('I\'ve Verified My Email'),
                ),
                const SizedBox(height: 16),

                // Sign out button
                OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
