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
import 'services/video_cache_service.dart';
import 'services/app_route_service.dart';
import 'screens/call_screen.dart';
import 'services/signaling_service.dart';
import 'widgets/active_session_banner.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

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

  /// FCM background messages (mobile only)
  if (!Platform.isWindows) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  /// Initialize theme before UI to avoid flicker
  final themeService = ThemeService();
  await themeService.initialize();

  runApp(
    ChangeNotifierProvider.value(value: themeService, child: const MyApp()),
  );

  // Defer non-critical init to keep startup fast
  if (!Platform.isWindows) {
    Future.microtask(() async {
      try {
        await NotificationService().initialize();
      } catch (e) {
        debugPrint('Notification init failed: $e');
      }
    });
  }

  // Evict old cached videos in background to avoid unbounded disk growth
  Future.microtask(() async {
    try {
      unawaited(VideoCacheService().evictOlderThan(const Duration(days: 30)));
    } catch (e) {
      debugPrint('Video cache eviction failed: $e');
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      navigatorObservers: [AppRouteService()],
      title: 'Shoq App',
      debugShowCheckedModeBanner: false,
      theme: ThemeService.lightTheme,
      darkTheme: ThemeService.darkTheme,
      themeMode: themeService.themeMode,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final systemScale = mediaQuery.textScaler.scale(1.0);
        final effectiveScale = (systemScale * themeService.uiScale).clamp(
          0.65,
          2.0,
        );
        final scaledChild = MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(effectiveScale),
            disableAnimations:
                mediaQuery.disableAnimations || themeService.reduceMotion,
          ),
          child: child ?? const SizedBox.shrink(),
        );
        return Stack(
          children: [
            scaledChild,
            ActiveSessionBanner(navigatorKey: appNavigatorKey),
          ],
        );
      },
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
  Timer? _verificationPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) async {
      if (user != null) {
        _verificationCheckUid = user.uid;

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
        _stopVerificationPolling();
        _e2eeInitialized = false;
        _verificationCheckUid = null;
      }
    });
  }

  void _startVerificationPolling(User user) {
    final uid = user.uid;
    if (_verificationCheckUid == uid && _verificationPollTimer != null) {
      return;
    }

    _stopVerificationPolling();
    _verificationCheckUid = uid;
    _verificationPollTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) async {
      final current = FirebaseAuth.instance.currentUser;
      if (!mounted || current == null || current.uid != uid) {
        _stopVerificationPolling();
        return;
      }

      if (current.emailVerified) {
        _stopVerificationPolling();
        if (mounted) setState(() {});
        return;
      }

      try {
        await current.reload().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Keep polling; transient network errors should not break flow.
      }

      if (!mounted) return;
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed == null || refreshed.uid != uid) {
        _stopVerificationPolling();
        return;
      }
      if (refreshed.emailVerified) {
        _stopVerificationPolling();
      }
      setState(() {});
    });
  }

  void _stopVerificationPolling() {
    _verificationPollTimer?.cancel();
    _verificationPollTimer = null;
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
      final isVideoRequested = message['isVideo'] == true;
      final isVideo = isVideoRequested && !Platform.isWindows;

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
      debugPrint('🔐 Initializing E2EE for logged-in user...');
      await UserService().initializeE2EE();
      debugPrint('✅ E2EE initialization complete');
    } catch (e) {
      debugPrint('⚠️  E2EE initialization failed (user may be new): $e');
      // Don't throw - app should still work for new users
      // E2EE will be initialized when they first try to send a message
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _stopIncomingCallListener();
    _stopVerificationPolling();
    _presenceService.stopPresenceTracking();
    _presenceService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    debugPrint('📱 Lifecycle changed to: $state');

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

          if (isGoogleUser) {
            _stopVerificationPolling();
            return const HomeScreen();
          }

          if (activeUser.emailVerified) {
            _stopVerificationPolling();
            return const HomeScreen();
          }

          _startVerificationPolling(activeUser);

          final refreshedUser = FirebaseAuth.instance.currentUser;
          if (refreshedUser != null && refreshedUser.emailVerified) {
            _stopVerificationPolling();
            return const HomeScreen();
          }

          return const EmailVerificationScreen();
        }

        _stopVerificationPolling();
        return const LoginScreen();
      },
    );
  }
}
