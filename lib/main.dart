import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/email_verification_screen.dart';
import 'services/firebase_options.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'services/presence_service.dart';
import 'services/user_service_e2ee.dart';
import 'services/app_prefetch_service.dart';
import 'services/user_cache_service.dart';
import 'services/conversation_cache_service.dart';
import 'screens/call_screen.dart';
import 'services/signaling_service.dart';

/// Background notification handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('BG message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// Firebase init
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable local persistence for faster startup and offline cache.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  /// FCM background messages
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  /// Initialize theme before UI to avoid flicker
  final themeService = ThemeService();
  await themeService.initialize();

  runApp(
    ChangeNotifierProvider.value(value: themeService, child: const MyApp()),
  );

  // Defer non-critical init to keep startup fast
  Future.microtask(() async {
    try {
      await NotificationService().initialize();
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return MaterialApp(
      title: 'Shoq App',
      debugShowCheckedModeBanner: false,
      theme: ThemeService.lightTheme,
      darkTheme: ThemeService.darkTheme,
      themeMode: themeService.themeMode,
      home: const AuthWrapper(),
    );
  }
}

/// Reacts to auth + email verification changes automatically
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  final PresenceService _presenceService = PresenceService();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<Map<String, dynamic>>? _incomingCallSub;
  String? _activeIncomingCallId;
  bool _callRouteOpen = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _e2eeInitialized = false;
  String? _verificationCheckUid;
  bool _verificationCheckInProgress = false;
  bool _verificationCheckCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) async {
      if (user != null) {
        if (_verificationCheckUid != user.uid) {
          _verificationCheckUid = user.uid;
          _verificationCheckInProgress = false;
          _verificationCheckCompleted = false;
        }

        await UserService().saveUserToFirestore(user: user);
        UserService().loadCachedProfile();
        UserService().startUserDocListener();
        AppPrefetchService().warmUpForUser(user.uid);
        _startIncomingCallListener(user.uid);
        // Initialize E2EE for logged-in users (only once per session)
        if (!_e2eeInitialized) {
          await _initializeE2EEForUser();
          _e2eeInitialized = true;
        }

        _presenceService.startPresenceTracking();
      } else {
        _presenceService.stopPresenceTracking();
        UserService().stopUserDocListener();
        UserCacheService().clear();
        ConversationCacheService().clearAll();
        _stopIncomingCallListener();
        _e2eeInitialized = false;
        _verificationCheckUid = null;
        _verificationCheckInProgress = false;
        _verificationCheckCompleted = false;
      }
    });
  }

  void _scheduleVerificationRefresh(User user) {
    if (_verificationCheckInProgress && _verificationCheckUid == user.uid) {
      return;
    }

    _verificationCheckUid = user.uid;
    _verificationCheckInProgress = true;
    _verificationCheckCompleted = false;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await user.reload().timeout(const Duration(seconds: 4));
      } catch (_) {
        // Ignore timeout/errors and gracefully continue.
      }

      if (!mounted) return;
      setState(() {
        _verificationCheckInProgress = false;
        _verificationCheckCompleted = true;
      });
    });
  }

  Widget _buildStartupLoader() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading your account...'),
          ],
        ),
      ),
    );
  }

  void _startIncomingCallListener(String uid) {
    _incomingCallSub?.cancel();
    unawaited(
      SignalingService().ensureConnected(userId: uid).catchError((error) {
        debugPrint('Incoming call signaling connection failed: $error');
      }),
    );

    _incomingCallSub = SignalingService().messages.listen((message) {
      if (!mounted) return;
      if (message['type'] != 'call_offer') return;
      if (message['to'] != uid) return;

      final callId = message['callId']?.toString() ?? '';
      if (callId.isEmpty) return;
      if (_callRouteOpen || _activeIncomingCallId == callId) return;

      _activeIncomingCallId = callId;
      _callRouteOpen = true;

      final callerName = message['callerName']?.toString() ?? 'User';
      final isVideo = message['isVideo'] == true;

      if (_appLifecycleState != AppLifecycleState.resumed ||
          Platform.isWindows) {
        NotificationService().showIncomingCallNotification(
          callId: callId,
          callerName: callerName,
          isVideo: isVideo,
        );
      }

      final invite = CallInvite(
        callId: callId,
        fromId: message['from']?.toString() ?? '',
        fromClientId: message['fromClientId']?.toString(),
        callerName: callerName,
        callerPhotoUrl: message['callerPhotoUrl']?.toString(),
        isVideo: isVideo,
        offer: {'sdp': message['sdp'], 'type': message['sdpType']},
      );

      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => CallScreen.incoming(incomingInvite: invite),
            ),
          )
          .whenComplete(() {
            _callRouteOpen = false;
            _activeIncomingCallId = null;
          });
    });
  }

  void _stopIncomingCallListener() {
    _incomingCallSub?.cancel();
    _incomingCallSub = null;
    SignalingService().disconnect();
    _activeIncomingCallId = null;
    _callRouteOpen = false;
  }

  Future<void> _initializeE2EEForUser() async {
    try {
      print('🔐 Initializing E2EE for logged-in user...');
      await UserService().initializeE2EE();
      print('✅ E2EE initialization complete');
    } catch (e) {
      print('⚠️  E2EE initialization failed (user may be new): $e');
      // Don't throw - app should still work for new users
      // E2EE will be initialized when they first try to send a message
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _stopIncomingCallListener();
    _presenceService.stopPresenceTracking();
    _presenceService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    print('📱 Lifecycle changed to: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        SignalingService().ensureConnected(userId: user.uid);
        _presenceService.setOnline();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _presenceService.setOffline();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user != null) {
          final activeUser = FirebaseAuth.instance.currentUser ?? user;
          final isGoogleUser = activeUser.providerData.any(
            (p) => p.providerId == 'google.com',
          );

          if (isGoogleUser) return const HomeScreen();

          if (activeUser.emailVerified) return const HomeScreen();

          final shouldRefreshVerification =
              _verificationCheckUid != activeUser.uid ||
              (!_verificationCheckCompleted && !_verificationCheckInProgress);
          if (shouldRefreshVerification) {
            _scheduleVerificationRefresh(activeUser);
          }

          if (_verificationCheckInProgress &&
              _verificationCheckUid == activeUser.uid) {
            return _buildStartupLoader();
          }

          final refreshedUser = FirebaseAuth.instance.currentUser;
          if (refreshedUser != null && refreshedUser.emailVerified) {
            return const HomeScreen();
          }

          return const EmailVerificationScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
