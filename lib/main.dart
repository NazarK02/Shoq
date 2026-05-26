import 'dart:async';
import 'dart:io' show Directory, File, FileMode, Platform;
import 'dart:ui' show PlatformDispatcher, DartPluginRegistrant;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoq/generated/app_localizations.dart';
import 'services/locale_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/email_verification_screen.dart';
import 'services/firebase_options.dart';
import 'services/notification_service.dart';
import 'services/email_verification_service.dart';
import 'services/theme_service.dart';
import 'services/presence_service.dart';
import 'services/user_service_e2ee.dart';
import 'services/app_prefetch_service.dart';
import 'services/chat_service_e2ee.dart';
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
    await File(
      path,
    ).writeAsString(buffer.toString(), mode: FileMode.append, flush: true);
  } catch (_) {}
}

/// Background notification handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('BG message: ${message.messageId}');

  final data = message.data;
  if (data['type']?.toString() == 'call_offer') {
    final callId = data['callId']?.toString() ?? '';
    if (callId.isEmpty) return;

    final callerName = data['callerName']?.toString() ?? 'Incoming call';
    final isVideo = data['isVideo'] == true || data['isVideo'] == 'true';

    await NotificationService().ensureLocalNotificationsReady();
    await NotificationService().showIncomingCallNotification(
      callId: callId,
      callerName: callerName,
      isVideo: isVideo,
      fromId: data['fromId']?.toString(),
      conversationId: data['conversationId']?.toString(),
      fromClientId: data['fromClientId']?.toString(),
      callerPhotoUrl: data['callerPhotoUrl']?.toString(),
      sdp: data['sdp']?.toString(),
      sdpType: data['sdpType']?.toString(),
    );
  }
}

Future<void> main() async {
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

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await _initCrashLogPath();

      /// Firebase init
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Keep offline cache enabled, but cap it to avoid long GC / disk stalls on
      // desktop and lower-memory phones.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100 * 1024 * 1024,
      );

      /// FCM background messages (mobile only)
      if (!Platform.isWindows) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
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
          unawaited(
            VideoCacheService().evictOlderThan(const Duration(days: 30)),
          );
        } catch (e) {
          debugPrint('Video cache eviction failed: $e');
        }
      });
    },
    (error, stack) {
      unawaited(_logCrash('Zone', error, stack));
    },
  );
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
      theme: ThemeService.lightThemeFor(uiScale: themeService.uiScale),
      darkTheme: ThemeService.darkThemeFor(uiScale: themeService.uiScale),
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
        final systemTextScale = mq.textScaler.scale(1.0);
        final effectiveTextScaler = TextScaler.linear(
          (systemTextScale * themeService.textScale).clamp(0.5, 3.0),
        );

        return MediaQuery(
          data: mq.copyWith(
            textScaler: effectiveTextScaler,
            disableAnimations:
                mq.disableAnimations || themeService.reduceMotion,
          ),
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              ActiveSessionBanner(navigatorKey: appNavigatorKey),
            ],
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
  final EmailVerificationService _verificationService =
      EmailVerificationService();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<Map<String, dynamic>>? _incomingCallSub;
  StreamSubscription<Map<String, dynamic>>? _callNotificationSub;
  String? _activeIncomingCallId;
  bool _callRouteOpen = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  Map<String, dynamic>? _pendingCallPayload;
  bool _restorePendingCallInProgress = false;
  bool _e2eeInitialized = false;
  bool _bootstrapInProgress = false;
  String? _bootstrappedUid;
  Timer? _windowsTokenPollTimer;
  bool _windowsTokenCheckInProgress = false;
  String? _verificationCheckUid;
  Timer? _verificationPollTimer;
  bool _forceSignOutInProgress = false;
  User? _authUser;
  bool _authEventReceived = false;
  bool _showBootstrapLoading = true;
  bool _showEmailVerification = false;
  double _bootstrapProgress = 0.08;
  String _bootstrapMessage = 'Starting Shoq...';
  int _authGeneration = 0;
  bool _authHintLoaded = false;
  String? _authRestoreHintUid;
  Timer? _authRestoreGraceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _callNotificationSub = NotificationService().callIntents.listen(
      _handleCallNotification,
    );

    unawaited(_loadAuthRestoreHint());

    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      unawaited(_handleAuthUserChanged(user));
    });
  }

  Future<void> _loadAuthRestoreHint() async {
    final uid = await _readAuthRestoreHint();
    if (!mounted) return;
    setState(() {
      _authHintLoaded = true;
      _authRestoreHintUid = uid;
    });

    if (_authEventReceived && _authUser == null) {
      unawaited(_handleAuthUserChanged(null));
    }
  }

  Future<String?> _readAuthRestoreHint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(UserService.authRestoreHintKey)?.trim() ?? '';
      return uid.isEmpty ? null : uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberAuthRestoreHint(String uid) async {
    final normalized = uid.trim();
    if (normalized.isEmpty) return;
    _authRestoreHintUid = normalized;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(UserService.authRestoreHintKey, normalized);
    } catch (_) {}
  }

  void _cancelAuthRestoreGrace() {
    _authRestoreGraceTimer?.cancel();
    _authRestoreGraceTimer = null;
  }

  void _setBootstrapState({
    required String message,
    required double progress,
    bool loading = true,
    bool showEmailVerification = false,
  }) {
    if (!mounted) return;
    setState(() {
      _showBootstrapLoading = loading;
      _showEmailVerification = showEmailVerification;
      _bootstrapMessage = message;
      _bootstrapProgress = progress.clamp(0.0, 1.0);
    });
  }

  Future<bool> _isVerifiedForEntry(User user) async {
    final isGoogleUser = user.providerData.any(
      (p) => p.providerId == 'google.com',
    );
    if (isGoogleUser ||
        user.emailVerified ||
        _verificationService.isLocallyVerified(user.uid)) {
      return true;
    }

    if (!Platform.isWindows) return false;

    _setBootstrapState(
      message: 'Checking email verification...',
      progress: 0.24,
    );
    try {
      final verified = await _verificationService
          .refreshEmailVerified(user)
          .timeout(const Duration(seconds: 6), onTimeout: () => false);
      if (verified) {
        _verificationService.markLocallyVerified(user.uid);
      }
      return verified;
    } catch (e) {
      debugPrint('Immediate Windows verification check failed: $e');
      return false;
    }
  }

  Future<bool> _waitForWindowsVerificationSettle(
    User user,
    int generation,
  ) async {
    if (!Platform.isWindows) return false;

    const attempts = 6;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (!mounted || generation != _authGeneration) return false;

      _setBootstrapState(
        message: 'Checking email verification...',
        progress: (0.3 + (attempt * 0.09)).clamp(0.3, 0.84),
      );

      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || generation != _authGeneration) return false;

      final current = FirebaseAuth.instance.currentUser;
      if (current == null || current.uid != user.uid) return false;

      try {
        final verified = await _verificationService
            .refreshEmailVerified(current)
            .timeout(const Duration(seconds: 4), onTimeout: () => false);
        if (verified) {
          _verificationService.markLocallyVerified(user.uid);
          return true;
        }
      } catch (e) {
        debugPrint('Windows verification settle check failed: $e');
      }
    }

    return false;
  }

  Future<void> _handleAuthUserChanged(User? user) async {
    final generation = ++_authGeneration;
    if (mounted) {
      setState(() {
        _authEventReceived = true;
        _authUser = user;
        _showBootstrapLoading = user != null;
        _showEmailVerification = false;
        _bootstrapMessage = user == null
            ? 'Opening sign in...'
            : 'Checking your session...';
        _bootstrapProgress = user == null ? 0 : 0.12;
      });
    }

    if (user == null) {
      _cancelAuthRestoreGrace();
      final previousBootstrappedUid = _bootstrappedUid;
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
      _pendingCallPayload = null;
      if (!_authHintLoaded) {
        _setBootstrapState(
          message: 'Checking saved sign-in...',
          progress: 0.12,
        );
        return;
      }

      final authHintUid = await _readAuthRestoreHint();
      if (!mounted || generation != _authGeneration) return;
      _authRestoreHintUid = authHintUid;

      if (Platform.isWindows &&
          authHintUid != null &&
          authHintUid.isNotEmpty &&
          !_forceSignOutInProgress) {
        _setBootstrapState(
          message: 'Restoring your session...',
          progress: 0.18,
        );
        _authRestoreGraceTimer = Timer(const Duration(seconds: 16), () {
          if (!mounted || generation != _authGeneration) return;
          final current = FirebaseAuth.instance.currentUser;
          if (current != null) {
            unawaited(_handleAuthUserChanged(current));
            return;
          }
          _verificationService.clearLocallyVerified(
            previousBootstrappedUid ?? '',
          );
          _setBootstrapState(
            message: 'Opening sign in...',
            progress: 0,
            loading: false,
          );
        });
        return;
      }

      _verificationService.clearLocallyVerified(previousBootstrappedUid ?? '');
      unawaited(NotificationService().clearPendingCallIntent());
      _setBootstrapState(
        message: 'Opening sign in...',
        progress: 0,
        loading: false,
      );
      return;
    }

    _cancelAuthRestoreGrace();
    final activeUser = FirebaseAuth.instance.currentUser ?? user;
    _verificationCheckUid = activeUser.uid;

    final isGoogleUser = activeUser.providerData.any(
      (p) => p.providerId == 'google.com',
    );
    final requiresVerification = !isGoogleUser;
    var verified = await _isVerifiedForEntry(activeUser);
    if (!mounted || generation != _authGeneration) return;

    if (requiresVerification && !verified && Platform.isWindows) {
      verified = await _waitForWindowsVerificationSettle(
        activeUser,
        generation,
      );
      if (!mounted || generation != _authGeneration) return;
    }

    if (requiresVerification && !verified) {
      _presenceService.stopPresenceTracking();
      _stopIncomingCallListener();
      if (!Platform.isWindows) {
        _startVerificationPolling(activeUser);
      } else {
        _startWindowsTokenPolling(activeUser);
      }
      _setBootstrapState(
        message: 'Email verification required',
        progress: 1,
        loading: false,
        showEmailVerification: true,
      );
      return;
    }

    _stopVerificationPolling();
    _setBootstrapState(message: 'Preparing your profile...', progress: 0.36);
    await _bootstrapForUser(activeUser);
    if (!mounted || generation != _authGeneration) return;
    _setBootstrapState(message: 'Ready', progress: 1, loading: false);
  }

  Future<void> _forceSignOut() async {
    if (_forceSignOutInProgress) return;
    _forceSignOutInProgress = true;
    try {
      _cancelAuthRestoreGrace();
      _presenceService.stopPresenceTracking();
      UserService().stopUserDocListener();
      UserCacheService().clear();
      ConversationCacheService().clearAll();
      _stopIncomingCallListener();
      _stopVerificationPolling();
      _e2eeInitialized = false;
      _verificationCheckUid = null;
      _authRestoreHintUid = null;
      _pendingCallPayload = null;
      _verificationService.clearLocallyVerified(_bootstrappedUid ?? '');
      unawaited(NotificationService().clearPendingCallIntent());
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
      _setBootstrapState(message: 'Loading your profile...', progress: 0.44);
      unawaited(
        UserService()
            .saveUserToFirestore(user: user)
            .timeout(const Duration(seconds: 5))
            .catchError((e) {
              debugPrint('User document save failed during bootstrap: $e');
            }),
      );
      unawaited(UserService().loadCachedProfile());
      UserService().startUserDocListener();
      _setBootstrapState(
        message: 'Connecting realtime services...',
        progress: 0.58,
      );
      _startIncomingCallListener(user.uid);
      unawaited(_restorePendingCallIntent());
      _setBootstrapState(message: 'Setting presence...', progress: 0.9);
      _presenceService.startPresenceTracking();
      _bootstrappedUid = user.uid;
      unawaited(_rememberAuthRestoreHint(user.uid));
      unawaited(_warmServicesAfterEntry(user.uid));
    } catch (e) {
      debugPrint('Auth bootstrap failed, forcing sign-out: $e');
      await _forceSignOut();
    } finally {
      _bootstrapInProgress = false;
    }
  }

  Future<void> _warmServicesAfterEntry(String uid) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;

    if (!_e2eeInitialized) {
      try {
        await _initializeE2EEForUser();
        if (FirebaseAuth.instance.currentUser?.uid == uid) {
          _e2eeInitialized = true;
        }
      } catch (e) {
        debugPrint('Deferred E2EE initialization failed: $e');
      }
    }

    try {
      await ChatService().initializeEncryption();
    } catch (e) {
      debugPrint('Deferred chat encryption priming failed: $e');
    }

    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    await AppPrefetchService().warmUpForUser(uid);
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
        if (mounted) {
          setState(() {
            _showEmailVerification = false;
            _showBootstrapLoading = true;
            _bootstrapMessage = 'Verification confirmed...';
            _bootstrapProgress = 0.32;
          });
        }
        await _handleAuthUserChanged(current);
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
        if (mounted) {
          setState(() {
            _showEmailVerification = false;
            _showBootstrapLoading = true;
            _bootstrapMessage = 'Verification confirmed...';
            _bootstrapProgress = 0.32;
          });
        }
        await _handleAuthUserChanged(refreshed);
        return;
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
    if (_windowsTokenPollTimer != null && _verificationCheckUid == user.uid) {
      return;
    }

    _windowsTokenPollTimer?.cancel();
    _windowsTokenPollTimer = Timer.periodic(const Duration(seconds: 8), (
      _,
    ) async {
      if (_windowsTokenCheckInProgress) return;
      _windowsTokenCheckInProgress = true;
      try {
        final current = FirebaseAuth.instance.currentUser;
        if (!mounted || current == null || current.uid != user.uid) {
          _windowsTokenPollTimer?.cancel();
          _windowsTokenPollTimer = null;
          return;
        }

        final verified = await _verificationService.refreshEmailVerified(
          current,
        );
        if (verified) {
          _verificationService.markLocallyVerified(user.uid);
          _windowsTokenPollTimer?.cancel();
          _windowsTokenPollTimer = null;
          if (mounted) {
            setState(() {
              _showEmailVerification = false;
              _showBootstrapLoading = true;
              _bootstrapMessage = 'Verification confirmed...';
              _bootstrapProgress = 0.32;
            });
          }
          await _handleAuthUserChanged(current);
        }
      } catch (e) {
        debugPrint('Windows token verify poll failed: $e');
      } finally {
        _windowsTokenCheckInProgress = false;
      }
    });
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
      final fromUserId = message['from']?.toString().trim() ?? '';
      final payload = <String, dynamic>{
        'type': 'call',
        'callId': callId,
        'fromId': fromUserId,
        if (fromUserId.isNotEmpty)
          'conversationId': ChatService().getDirectConversationId(
            fromUserId,
            uid,
          ),
        'fromClientId': message['fromClientId']?.toString(),
        'callerName': message['callerName']?.toString() ?? 'User',
        'callerPhotoUrl': message['callerPhotoUrl']?.toString(),
        'isVideo': message['isVideo'] == true,
      };
      final pendingCallId = _pendingCallPayload?['callId']?.toString();
      if (_callRouteOpen ||
          _activeIncomingCallId == callId ||
          pendingCallId == callId) {
        return;
      }

      final callerName = message['callerName']?.toString() ?? 'User';
      final isVideoRequested = message['isVideo'] == true;
      final isVideo = isVideoRequested;

      if (_appLifecycleState != AppLifecycleState.resumed ||
          Platform.isWindows) {
        _pendingCallPayload = payload;
        unawaited(NotificationService().cachePendingCallIntent(payload));
        NotificationService().showIncomingCallNotification(
          callId: callId,
          callerName: callerName,
          isVideo: isVideo,
          fromId: message['from']?.toString(),
          conversationId: payload['conversationId']?.toString(),
          fromClientId: message['fromClientId']?.toString(),
          callerPhotoUrl: message['callerPhotoUrl']?.toString(),
          sdp: message['sdp']?.toString(),
          sdpType: message['sdpType']?.toString(),
        );
        return;
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

      unawaited(_pushIncomingCallRoute(invite));
    });
  }

  void _stopIncomingCallListener() {
    _incomingCallSub?.cancel();
    _incomingCallSub = null;
    SignalingService().disconnect();
    _activeIncomingCallId = null;
    _callRouteOpen = false;
  }

  Future<void> _handleCallNotification(Map<String, dynamic> payload) async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final callId = payload['callId']?.toString() ?? '';
    if (callId.isEmpty) {
      await NotificationService().clearPendingCallIntent();
      return;
    }
    if (_appLifecycleState != AppLifecycleState.resumed) {
      _pendingCallPayload = Map<String, dynamic>.from(payload);
      await NotificationService().cachePendingCallIntent(payload);
      return;
    }

    final autoAnswer =
        payload['autoAnswer'] == true || payload['autoAnswer'] == 'true';
    if (_callRouteOpen || _activeIncomingCallId == callId) {
      _pendingCallPayload = null;
      await NotificationService().clearPendingCallIntent(callId: callId);
      return;
    }

    try {
      final invite = await _loadIncomingInvite(
        payload: payload,
        userId: user.uid,
      );
      if (invite == null) {
        _pendingCallPayload = null;
        await NotificationService().clearPendingCallIntent(callId: callId);
        return;
      }

      final pushed = await _pushIncomingCallRoute(
        invite,
        autoAnswer: autoAnswer,
      );
      if (pushed) {
        _pendingCallPayload = null;
        await NotificationService().clearPendingCallIntent(callId: callId);
      }
    } catch (e) {
      debugPrint('Failed to handle call notification: $e');
    }
  }

  Future<CallInvite?> _loadIncomingInvite({
    required Map<String, dynamic> payload,
    required String userId,
  }) async {
    final callId = payload['callId']?.toString() ?? '';
    if (callId.isEmpty) return null;

    final fromId = (payload['fromId']?.toString() ?? '').trim();
    final payloadConversationId = (payload['conversationId']?.toString() ?? '')
        .trim();
    final conversationId = payloadConversationId.isNotEmpty
        ? payloadConversationId
        : (fromId.isNotEmpty
              ? ChatService().getDirectConversationId(fromId, userId)
              : '');

    Map<String, dynamic> data = payload;
    if (conversationId.isNotEmpty) {
      final callDoc = await ChatService().loadCallMessage(
        conversationId: conversationId,
        callId: callId,
      );
      if (callDoc != null && callDoc.isNotEmpty) {
        data = callDoc;
        final toId = data['toId']?.toString() ?? '';
        if (toId.isNotEmpty && toId != userId) {
          return null;
        }

        final status = data['status']?.toString() ?? 'ringing';
        if (status != 'ringing') {
          return null;
        }
      }
    }

    final offerData = data['offer'];
    final offer = offerData is Map
        ? Map<String, dynamic>.from(offerData)
        : null;
    final sdp = offer?['sdp']?.toString() ?? payload['sdp']?.toString();
    final sdpType =
        offer?['type']?.toString() ?? payload['sdpType']?.toString();
    if (sdp == null || sdpType == null) {
      return null;
    }

    return CallInvite(
      callId: callId,
      fromId: data['fromId']?.toString() ?? payload['fromId']?.toString() ?? '',
      fromClientId:
          data['fromClientId']?.toString() ??
          payload['fromClientId']?.toString(),
      callerName:
          data['callerName']?.toString() ??
          payload['callerName']?.toString() ??
          'User',
      callerPhotoUrl:
          data['callerPhotoUrl']?.toString() ??
          payload['callerPhotoUrl']?.toString(),
      isVideo: data['isVideo'] == true || payload['isVideo'] == true,
      offer: {'sdp': sdp, 'type': sdpType},
    );
  }

  Future<bool> _pushIncomingCallRoute(
    CallInvite invite, {
    bool autoAnswer = false,
  }) async {
    final navigator = appNavigatorKey.currentState;
    if (!mounted || navigator == null) {
      return false;
    }

    _activeIncomingCallId = invite.callId;
    _callRouteOpen = true;

    navigator
        .push(
          MaterialPageRoute(
            builder: (_) => CallScreen.incoming(
              incomingInvite: invite,
              autoAnswer: autoAnswer,
            ),
          ),
        )
        .whenComplete(() {
          _callRouteOpen = false;
          if (_activeIncomingCallId == invite.callId) {
            _activeIncomingCallId = null;
          }
        });
    return true;
  }

  Future<void> _restorePendingCallIntent() async {
    if (!mounted || _restorePendingCallInProgress) return;
    if (_appLifecycleState != AppLifecycleState.resumed) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _restorePendingCallInProgress = true;
    try {
      final payload =
          _pendingCallPayload ??
          await NotificationService().getPendingCallIntent();
      if (payload == null) {
        return;
      }
      await _handleCallNotification(Map<String, dynamic>.from(payload));
    } finally {
      _restorePendingCallInProgress = false;
    }
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
    _callNotificationSub?.cancel();
    _cancelAuthRestoreGrace();
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
        unawaited(_restorePendingCallIntent());
        unawaited(AppPrefetchService().warmUpForUser(user.uid));
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
    if (!_authHintLoaded || !_authEventReceived || _showBootstrapLoading) {
      return _BootstrapLoadingScreen(
        message: _bootstrapMessage,
        progress: _bootstrapProgress,
      );
    }

    if (_authUser != null) {
      if (_showEmailVerification) {
        return const EmailVerificationScreen();
      }
      return const HomeScreen();
    }

    _stopVerificationPolling();
    return const LoginScreen();
  }
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen({
    required this.message,
    required this.progress,
  });

  final String message;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 78,
                    height: 78,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Shoq',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: progress <= 0 ? null : progress.clamp(0.05, 0.98),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
