import 'dart:convert';
import 'dart:io' show HttpClient, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../services/windows_google_auth_service.dart';
import '../services/firebase_options.dart';
import '../generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  bool get _googleSignInSupportedDesktop {
    if (kIsWeb) return true;
    if (Platform.isLinux) return false;
    if (Platform.isWindows) return WindowsGoogleAuthService.isConfigured;
    return true;
  }

  String? get _googleSignInDesktopHint {
    if (kIsWeb) return null;
    if (Platform.isLinux) {
      return 'Google Sign-In is not supported on Linux desktop.';
    }
    if (Platform.isWindows && !WindowsGoogleAuthService.isConfigured) {
      return WindowsGoogleAuthService.setupHint;
    }
    return null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<UserCredential> _createUserWithEmail(
    String email,
    String password,
  ) async {
    if (Platform.isWindows) {
      return _createUserWithEmailWindowsRest(email, password);
    }
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> _createUserWithEmailWindowsRest(
    String email,
    String password,
  ) async {
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
    );

    final client = HttpClient();
    final request = await client.postUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    request.add(
      utf8.encode(
        jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      ),
    );
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode >= 400) {
      final error = _parseRestAuthError(responseBody);
      throw FirebaseAuthException(
        code: error.$1,
        message: error.$2,
      );
    }

    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  (String, String?) _parseRestAuthError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['error'] is Map) {
        final message = data['error']['message']?.toString() ?? 'UNKNOWN';
        switch (message) {
          case 'EMAIL_EXISTS':
            return ('email-already-in-use', 'Email already in use.');
          case 'INVALID_EMAIL':
            return ('invalid-email', 'Invalid email address.');
          case 'WEAK_PASSWORD':
            return ('weak-password', 'Weak password.');
          case 'OPERATION_NOT_ALLOWED':
            return ('operation-not-allowed', 'Operation not allowed.');
          default:
            return ('unknown', message);
        }
      }
    } catch (_) {}
    return ('unknown', 'Registration failed.');
  }

  // Email/Password Registration
  Future<void> _registerWithEmail() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.pleaseAcceptTerms)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final name = _nameController.text.trim();

      print('🔵 Creating user account...');

      if (Platform.isWindows) {
        // Give the UI thread a tiny breather before hitting platform channels.
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Create user
      UserCredential userCredential = await _createUserWithEmail(
        email,
        password,
      );

      print('✅ User account created: ${userCredential.user?.uid}');

      // Update display name (safe to skip if it fails)
      if (!Platform.isWindows) {
        try {
          await userCredential.user?.updateDisplayName(name);
        } catch (e) {
          print('⚠️ Display name update failed: $e');
        }
      } else {
        print('Windows: skipping display name update until later.');
      }

      if (!Platform.isWindows) {
        // IMPORTANT: Reload the user to get the updated displayName
        await userCredential.user?.reload();

        // Get the refreshed user object
        User? refreshedUser = _auth.currentUser;

        // Send verification email
        print('📧 Sending verification email...');
        // Workaround for Firebase Windows threading bug: defer off the widget tree's hot path
        await Future.delayed(Duration.zero);
        await refreshedUser?.sendEmailVerification();
        print('✅ Verification email sent');
      } else {
        print('Windows: skipping auto verification email; user can resend manually.');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Platform.isWindows
                  ? 'Account created. Please verify your email from the verification screen.'
                  : l.verificationEmailSent,
            ),
          ),
        );

        // Return to the app root and let AuthWrapper display the proper screen.
        Navigator.of(
          context,
          rootNavigator: true,
        ).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');

      final l = AppLocalizations.of(context);
      String message = l.authErrorDefault;
      if (e.code == 'weak-password') {
        message = l.authErrorWeakPassword;
      } else if (e.code == 'email-already-in-use') {
        message = l.authErrorEmailInUse;
      } else if (e.code == 'invalid-email') {
        message = l.authErrorInvalidEmail;
      } else if (e.code == 'operation-not-allowed') {
        message = l.authErrorNotAllowed;
      } else if (e.code == 'network-request-failed') {
        message = l.authErrorNetwork;
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      print('❌ Unknown Error: $e');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${l.authErrorDefault}: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Google Sign-In
  Future<void> _signInWithGoogle() async {
    final l = AppLocalizations.of(context);
    final isWindowsDesktop = !kIsWeb && Platform.isWindows;
    final usesProviderFlow = !kIsWeb && Platform.isMacOS;

    if (!kIsWeb && Platform.isLinux) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.googleSignInUnsupportedLinux),
          ),
        );
      }
      return;
    }

    if (isWindowsDesktop && !WindowsGoogleAuthService.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(WindowsGoogleAuthService.setupHint)),
        );
      }
      return;
    }

    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.pleaseAcceptTerms)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential;

      if (isWindowsDesktop) {
        userCredential = await WindowsGoogleAuthService().signInWithGoogle();
      } else if (usesProviderFlow) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        userCredential = await _auth.signInWithProvider(googleProvider);
      } else {
        print('Starting Google Sign-In...');

        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

        if (googleUser == null) {
          print('Google Sign-In cancelled');
          return;
        }

        print('Selected Google account: ${googleUser.email}');

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        print('Signing in with Google credentials...');
        userCredential = await _auth.signInWithCredential(credential);
      }

      print('Signed in: ${userCredential.user?.uid}');

      // AuthWrapper will automatically navigate to HomeScreen
      // No need to manually navigate here
    } on WindowsGoogleAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Error: ${e.code} - ${e.message}');

      if (mounted) {
        final l = AppLocalizations.of(context);
        String message = l.authErrorDefault;
        if (e.code == 'account-exists-with-different-credential') {
          message = l.authErrorDefault;
        } else if (e.code == 'invalid-credential') {
          message = l.authErrorDefault;
        } else if (e.code == 'operation-not-allowed') {
          message = l.authErrorDefault;
        } else if (e.code == 'user-disabled') {
          message = l.authErrorDefault;
        } else if (e.code == 'unknown-error' &&
            (e.message ?? '').contains('non-mobile systems')) {
          message = l.googleSignInUnsupportedPlatform;
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      print('Unknown Error: $e');

      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.authErrorDefault}: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo
                      Image.asset(
                        'assets/images/logo.png',
                        width: 120,
                        height: 120,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.shopping_bag,
                            size: 80,
                            color: Theme.of(context).primaryColor,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l.createAccount,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.signUpToGetStarted,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Name Field
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l.fullName,
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l.pleaseEnterName;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: l.email,
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l.pleaseEnterEmail;
                          }
                          if (!value.contains('@')) {
                            return l.authErrorInvalidEmail;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: l.password,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l.pleaseEnterPassword;
                          }
                          if (value.length < 6) {
                            return l.passwordTooShort;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Confirm Password Field
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: l.confirmPassword,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              );
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l.pleaseConfirmPassword;
                          }
                          if (value != _passwordController.text) {
                            return l.passwordsDoNotMatch;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Terms and Conditions Checkbox
                      Row(
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            onChanged: (value) {
                              setState(() => _acceptedTerms = value ?? false);
                            },
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(
                                  () => _acceptedTerms = !_acceptedTerms,
                                );
                              },
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                  children: [
                                    TextSpan(text: 'I accept the '),
                                    WidgetSpan(
                                      child: GestureDetector(
                                        onTap: () async {
                                          final url = Uri.parse(
                                            'https://aeamadoraoeste.edu.pt/',
                                          );
                                          final success = await launchUrl(
                                            url,
                                            mode:
                                                LaunchMode.externalApplication,
                                          );
                                          if (!success && mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Could not open link',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: Text(
                                          l.termsOfService,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Register Button
                      ElevatedButton(
                        onPressed: _isLoading ? null : _registerWithEmail,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                l.signUp,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      const SizedBox(height: 24),

                      // Divider
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey[400])),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              l.orSeparator,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey[400])),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Google Sign-In Button
                      OutlinedButton.icon(
                        onPressed:
                            (_isLoading || !_googleSignInSupportedDesktop)
                            ? null
                            : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata, size: 32),
                        label: Text(
                          _googleSignInSupportedDesktop
                              ? l.continueWithGoogle
                              : l.googleSignInUnsupportedPlatform,
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                      if (!_googleSignInSupportedDesktop) ...[
                        const SizedBox(height: 8),
                        Text(
                          _googleSignInDesktopHint ??
                              l.googleSignInUnsupportedLinux,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Login Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                            },
                            child: Text(
                              l.signIn,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Theme toggle button in top-right corner
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: Icon(
                  themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  size: 28,
                ),
                onPressed: () {
                  themeService.toggleTheme();
                },
                tooltip: themeService.isDarkMode ? l.lightMode : l.darkMode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
