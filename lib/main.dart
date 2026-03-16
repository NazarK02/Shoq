import 'dart:async';
import 'dart:io' show Directory, File, FileMode, Platform;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shoq/generated/app_localizations.dart';
import 'services/locale_service.dart';
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
String _crashLogPath = '';

Future<void> _initCrashLogPath() async {
  final candidates = <String?>[
    Platform.environment['LOCALAPPDATA'],
    Platform.environment['APPDATA'],
    Directory.systemTemp.path,
    Directory.current.path,
  ];

  for (final base in candidates) {
    if (base == null || base.trim().isEmpty) continue;

    final dirPath = Platform.isWindows
        ? '$base${Platform.pathSeparator}Shoq'
        : '$base${Platform.pathSeparator}shoq';

    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final candidate = '$dirPath${Platform.pathSeparator}shoq_crash.log';
      await File(candidate).writeAsString(
        '[BOOT] ${DateTime.now().toIso8601String()}\n',
        mode: FileMode.append,
        flush: true,
      );
      _crashLogPath = candidate;
      return;
    } catch (_) {
      continue;
    }
  }

  _crashLogPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}shoq_crash.log';
}

Future<void> _logCrash(
  String label,
  Object? error,
  StackTrace? stackTrace,
) async {
  final path = _crashLogPath.isNotEmpty
      ? _crashLogPath
      : '${Directory.systemTemp.path}${Platform.pathSeparator}shoq_crash.log';
  final buffer = StringBuffer()
    ..writeln('[$label] ${DateTime.now().toIso8601String()}')
    ..writeln('Error: $error');
  if (stackTrace != null) {
    buffer.writeln(stackTrace);
  }
  buffer.writeln('---');
  try {
    await File(path).writeAsString(
      buffer.toString(),
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

/// Background notification handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('BG message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initCrashLogPath();

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    unawaited(_logCrash('FlutterError', details.exception, details.stack));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_logCrash('PlatformDispatcher', error, stack));
    return true;
  };
  ErrorWidget.builder = (details) {
    unawaited(_logCrash('ErrorWidget', details.exception, details.stack));
    return Material(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'App error.\nSee log: $_crashLogPath',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };

  runZonedGuarded(() async {
    /// Firebase init
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

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

    final localeService = LocaleService();
    await localeService.initialize();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeService),
          ChangeNotifierProvider.value(value: localeService),
        ],
        child: const MyApp(),
      ),
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
  }, (error, stack) {
    unawaited(_logCrash('Zone', error, stack));
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final localeService = context.watch<LocaleService>();

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      navigatorObservers: [AppRouteService()],
      title: 'Shoq App',
      debugShowCheckedModeBanner: false,
      theme: ThemeService.lightTheme,
      darkTheme: ThemeService.darkTheme,
      themeMode: themeService.themeMode,
      locale: localeService.locale,
      supportedLocales: LocaleService.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final layoutScale = themeService.uiScale;
        final systemTextScale = mq.textScaler.scale(1.0);
        final effectiveTextScaler = TextScaler.linear(
          ((systemTextScale * themeService.textScale) / layoutScale)
              .clamp(0.5, 3.0),
        );
        final scaledSize = mq.size / layoutScale;

        return MediaQuery(
          data: mq.copyWith(
            size: scaledSize,
            padding: mq.padding * (1.0 / layoutScale),
            viewPadding: mq.viewPadding * (1.0 / layoutScale),
            viewInsets: mq.viewInsets * (1.0 / layoutScale),
            systemGestureInsets:
                mq.systemGestureInsets * (1.0 / layoutScale),
            textScaler: effectiveTextScaler,
            disableAnimations: mq.disableAnimations || themeService.reduceMotion,
          ),
          child: Transform.scale(
            scale: layoutScale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: scaledSize.width,
              height: scaledSize.height,
              child: Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  ActiveSessionBanner(navigatorKey: appNavigatorKey),
                ],
              ),
            ),
          ),
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
  bool _bootstrapInProgress = false;
  String? _bootstrappedUid;
  Timer? _windowsTokenPollTimer;
  bool _windowsTokenCheckInProgress = false;
  bool _windowsTokenVerified = false;
  String? _windowsTokenVerifiedUid;
  String? _verificationCheckUid;
  Timer? _verificationPollTimer;
  bool _forceSignOutInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authSubscription = FirebaseAuth.instance.userChanges().listen((
      user,
    ) async {
      if (user != null) {
        _verificationCheckUid = user.uid;
        final isGoogleUser = user.providerData.any(
          (p) => p.providerId == 'google.com',
        );
        final requiresVerification = !isGoogleUser && !user.emailVerified;
        if (Platform.isWindows && requiresVerification) {
          _startWindowsTokenPolling(user);
        }
        final shouldSaveUser =
            !Platform.isWindows || !requiresVerification;
        if (shouldSaveUser) {
          try {
            await UserService().saveUserToFirestore(user: user);
          } catch (e) {
            debugPrint('User document save failed: $e');
          }
        } else {
          debugPrint(
              'Skipping user document save until verification on Windows.');
        }
        final tokenVerifiedForUser =
            _windowsTokenVerified && _windowsTokenVerifiedUid == user.uid;
        if (requiresVerification &&
            !(Platform.isWindows && tokenVerifiedForUser)) {
          _presenceService.stopPresenceTracking();
          _stopIncomingCallListener();
          if (!Platform.isWindows) {
            _stopVerificationPolling();
          }
          return;
        }
        await _bootstrapForUser(user);
      } else {
        _presenceService.stopPresenceTracking();
        UserService().stopUserDocListener();
        UserCacheService().clear();
        ConversationCacheService().clearAll();
        _stopIncomingCallListener();
        _stopVerificationPolling();
        _e2eeInitialized = false;
        _verificationCheckUid = null;
        _bootstrappedUid = null;
        _bootstrapInProgress = false;
        _windowsTokenVerified = false;
        _windowsTokenVerifiedUid = null;
      }
    });
  }

  Future<void> _forceSignOut() async {
    if (_forceSignOutInProgress) return;
    _forceSignOutInProgress = true;
    try {
      _presenceService.stopPresenceTracking();
      UserService().stopUserDocListener();
      UserCacheService().clear();
      ConversationCacheService().clearAll();
      _stopIncomingCallListener();
      _stopVerificationPolling();
      _e2eeInitialized = false;
      _verificationCheckUid = null;
      _windowsTokenVerified = false;
      _windowsTokenVerifiedUid = null;
      await UserService().signOut();
    } catch (e) {
      debugPrint('Force sign-out failed: $e');
    } finally {
      _forceSignOutInProgress = false;
    }
  }

  Future<void> _bootstrapForUser(User user) async {
    if (_bootstrapInProgress) return;
    if (_bootstrappedUid == user.uid) return;
    _bootstrapInProgress = true;
    try {
      try {
        await UserService().saveUserToFirestore(user: user);
      } catch (e) {
        debugPrint('User document save failed during bootstrap: $e');
      }
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
      _bootstrappedUid = user.uid;
    } catch (e) {
      debugPrint('Auth bootstrap failed, forcing sign-out: $e');
      await _forceSignOut();
    } finally {
      _bootstrapInProgress = false;
    }
  }

  void _startVerificationPolling(User user) {
    if (Platform.isWindows) {
      return;
    }
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
    _windowsTokenPollTimer?.cancel();
    _windowsTokenPollTimer = null;
    _windowsTokenCheckInProgress = false;
  }

  void _startWindowsTokenPolling(User user) {
    if (!Platform.isWindows) return;
    if (_windowsTokenPollTimer != null &&
        _verificationCheckUid == user.uid) {
      return;
    }

    _windowsTokenPollTimer?.cancel();
    _windowsTokenPollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) async {
        if (_windowsTokenCheckInProgress) return;
        _windowsTokenCheckInProgress = true;
        try {
          final current = FirebaseAuth.instance.currentUser;
          if (!mounted || current == null || current.uid != user.uid) {
            _windowsTokenPollTimer?.cancel();
            _windowsTokenPollTimer = null;
            return;
          }

          final token = await current.getIdTokenResult(true);
          final claims = token.claims ?? const <String, dynamic>{};
          final verified =
              claims['email_verified'] == true || claims['emailVerified'] == true;
          if (verified) {
            _windowsTokenVerified = true;
            _windowsTokenVerifiedUid = user.uid;
            _windowsTokenPollTimer?.cancel();
            _windowsTokenPollTimer = null;
            if (mounted) setState(() {});
            await _bootstrapForUser(current);
          }
        } catch (e) {
          debugPrint('Windows token verify poll failed: $e');
        } finally {
          _windowsTokenCheckInProgress = false;
        }
      },
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
      final isVideoRequested = message['isVideo'] == true;
      final isVideo = isVideoRequested;

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
        if (snapshot.hasError) {
          unawaited(_logCrash(
            'AuthStream',
            snapshot.error,
            snapshot.stackTrace,
          ));
          _stopVerificationPolling();
          return const LoginScreen();
        }
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

          final tokenVerified =
              _windowsTokenVerified && _windowsTokenVerifiedUid == activeUser.uid;
          if (Platform.isWindows && tokenVerified) {
            _stopVerificationPolling();
            return const HomeScreen();
          }

          if (!Platform.isWindows) {
            _startVerificationPolling(activeUser);
          } else {
            _startWindowsTokenPolling(activeUser);
          }

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
