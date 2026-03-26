import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../services/windows_google_auth_service.dart';
import '../generated/app_localizations.dart';
import 'registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

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
    super.dispose();
  }

  // Email/Password Login
  Future<void> _loginWithEmail() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        // AuthWrapper will automatically navigate
      }
    } on FirebaseAuthException catch (e) {
      String message = l.authErrorDefault;
      if (e.code == 'user-not-found') {
        message = l.authErrorUserNotFound;
      } else if (e.code == 'wrong-password') {
        message = l.authErrorWrongPassword;
      } else if (e.code == 'invalid-email') {
        message = l.authErrorInvalidEmail;
      } else if (e.code == 'user-disabled') {
        message = l.authErrorDefault;
      } else if (e.code == 'too-many-requests') {
        message = l.authErrorTooManyRequests;
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
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
    final isLinuxDesktop = !kIsWeb && Platform.isLinux;
    final usesProviderFlow = !kIsWeb && Platform.isMacOS;

    if (isLinuxDesktop) {
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

    setState(() => _isLoading = true);

    try {
      if (isWindowsDesktop) {
        await WindowsGoogleAuthService().signInWithGoogle();
      } else if (usesProviderFlow) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        await _auth.signInWithProvider(googleProvider);
      } else {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

        if (googleUser == null) {
          return;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await _auth.signInWithCredential(credential);
      }

      if (mounted) {
        // AuthWrapper will automatically navigate
      }
    } on WindowsGoogleAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message = l.authErrorDefault;
        if (e.code == 'account-exists-with-different-credential') {
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
      if (mounted) {
        print('Google Sign-In Error: $e');
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
                        l.welcomeBack,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.signInToContinue,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 32),

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
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Remember Me & Forgot Password
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (value) {
                                  setState(() => _rememberMe = value ?? false);
                                },
                              ),
                              Text(l.rememberMe),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l.comingSoon),
                                ),
                              );
                            },
                            child: Text(l.forgotPassword),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Login Button
                      ElevatedButton(
                        onPressed: _isLoading ? null : _loginWithEmail,
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
                                ),
                              )
                            : Text(
                                l.signIn,
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
                              l.googleSignInUnsupportedPlatform,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Register Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l.dontHaveAnAccount,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegistrationScreen(),
                                ),
                              );
                            },
                            child: Text(
                              l.signUp,
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
