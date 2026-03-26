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
  bool _windowsTokenVerified = false;
  String? _windowsTokenVerifiedUid;
  String? _verificationCheckUid;
  Timer? _verificationPollTimer;
  bool _forceSignOutInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _callNotificationSub = NotificationService().callIntents.listen(
      _handleCallNotification,
    );

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
        final shouldSaveUser = !Platform.isWindows || !requiresVerification;
        if (shouldSaveUser) {
          try {
            await UserService().saveUserToFirestore(user: user);
          } catch (e) {
            debugPrint('User document save failed: $e');
          }
        } else {
          debugPrint(
            'Skipping user document save until verification on Windows.',
          );
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
        _windowsTokenVerified = false;
        _windowsTokenVerifiedUid = null;
        _pendingCallPayload = null;
        _verificationService.clearLocallyVerified(previousBootstrappedUid ?? '');
        unawaited(NotificationService().clearPendingCallIntent());
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
      try {
        await UserService().saveUserToFirestore(user: user);
      } catch (e) {
        debugPrint('User document save failed during bootstrap: $e');
      }
      UserService().loadCachedProfile();
      UserService().startUserDocListener();
      _startIncomingCallListener(user.uid);
      unawaited(_restorePendingCallIntent());
      // Initialize E2EE for logged-in users (only once per session)
      if (!_e2eeInitialized) {
        await _initializeE2EEForUser();
        _e2eeInitialized = true;
      }

      try {
        await ChatService().initializeEncryption();
      } catch (e) {
        debugPrint('Chat encryption priming failed: $e');
      }

      unawaited(AppPrefetchService().warmUpForUser(user.uid));

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
    final payloadConversationId =
        (payload['conversationId']?.toString() ?? '').trim();
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
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          unawaited(
            _logCrash('AuthStream', snapshot.error, snapshot.stackTrace),
          );
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

        if (Platform.isWindows &&
            _verificationService.isLocallyVerified(activeUser.uid)) {
          _stopVerificationPolling();
          return const HomeScreen();
        }

        if (activeUser.emailVerified) {
          _stopVerificationPolling();
          return const HomeScreen();
        }

          final tokenVerified =
              _windowsTokenVerified &&
              _windowsTokenVerifiedUid == activeUser.uid;
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
