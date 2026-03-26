import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/email_verification_service.dart';
import '../services/user_service_e2ee.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EmailVerificationService _verificationService =
      EmailVerificationService();
  Timer? _timer;
  Timer? _resendTimer;
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
    _startVerificationCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        // Defer the send so navigation/state changes do not race the auth call.
        await Future.delayed(Duration.zero);
        await EmailVerificationService().sendVerificationEmail(user);

        if (!mounted) return;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verification email sent!')),
          );
        }

        setState(() {
          _resendCountdown = 60;
        });

        _resendTimer?.cancel();
        _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_resendCountdown > 0) {
            setState(() {
              _resendCountdown--;
            });
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

  Future<bool> _refreshVerificationStatus(User user) async {
    final attempts = Platform.isWindows ? 3 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final verified = await _verificationService.refreshEmailVerified(user);
      if (verified) {
        _verificationService.markLocallyVerified(user.uid);
        return true;
      }

      if (attempt < attempts - 1) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    return false;
  }

  void _startVerificationCheck() {
    if (_timer != null) return;
    final interval = const Duration(seconds: 3);
    _timer = Timer.periodic(interval, (timer) async {
      if (_verificationCheckInProgress) return;
      _verificationCheckInProgress = true;
      try {
        final user = _auth.currentUser;
        if (user != null) {
          final verified = await _refreshVerificationStatus(user);
          if (verified) {
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
    if (!mounted) return;
    setState(() => _isResending = true);
    try {
      await _sendVerificationEmail();
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
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
                      try {
                        final verified = await _refreshVerificationStatus(user);
                        if (verified) {
                          _handleVerifiedState();
                          return;
                        }
                      } catch (e) {
                        debugPrint('Verification check failed: $e');
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
