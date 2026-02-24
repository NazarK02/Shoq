import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'chat_service_e2ee.dart';
import 'device_info_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  unawaited(
    NotificationService().handleNotificationResponse(
      response,
      fromBackground: true,
    ),
  );
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _markReadActionId = 'mark_read';
  static const String _replyActionId = 'reply';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoService _deviceInfo = DeviceInfoService();
  final ChatService _chatService = ChatService();

  FirebaseMessaging? _fcm;
  FlutterLocalNotificationsPlugin? _localNotifications;
  StreamSubscription<User?>? _authSubscription;
  String? _cachedToken;
  bool _fcmInitialized = false;
  bool _localInitialized = false;

  final Map<String, int> _messageCountPerSender = {};
  final Map<String, List<String>> _messagesPerSender = {};

  String? _activeChatUserId;

  bool get supportsFcm {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  bool get supportsLocalNotifications {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isWindows;
  }

  void setActiveChat(String? userId) {
    _activeChatUserId = userId;
    print('Active chat set to: $userId');

    if (userId != null && supportsLocalNotifications) {
      clearNotificationsForSender(userId);
    }
  }

  String? getActiveChat() => _activeChatUserId;

  Future<void> initialize() async {
    print('Initializing NotificationService...');

    if (!supportsFcm && !supportsLocalNotifications) {
      print('Notifications are not supported on this platform.');
      return;
    }

    _localNotifications ??= FlutterLocalNotificationsPlugin();
    if (supportsLocalNotifications && !_localInitialized) {
      try {
        await _initializeLocalNotifications();
        _localInitialized = true;
      } catch (e) {
        print('Failed to initialize local notifications: $e');
      }
    }

    if (!supportsFcm) {
      return;
    }

    _fcm ??= FirebaseMessaging.instance;

    _authSubscription ??= _auth.authStateChanges().listen((user) {
      if (user != null && _cachedToken != null) {
        _saveTokenToFirestore(_cachedToken!);
      }
    });

    if (_fcmInitialized) {
      if (_cachedToken != null && _auth.currentUser != null) {
        await _saveTokenToFirestore(_cachedToken!);
      }
      return;
    }

    final settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      final token = await _fcm!.getToken();
      if (token != null) {
        _cachedToken = token;
        await _saveTokenToFirestore(token);
      } else {
        print('Failed to get FCM token');
      }

      _fcm!.onTokenRefresh.listen((newToken) {
        _cachedToken = newToken;
        _saveTokenToFirestore(newToken);
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

      _fcmInitialized = true;
      print('Notification service initialized');
    } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
      print('Notification permission denied');
    } else {
      print('Notification permission not granted yet');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (!supportsLocalNotifications || _localNotifications == null) return;

    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettingsWindows = WindowsInitializationSettings(
      appName: 'Shoq',
      appUserModelId: 'com.example.shoq',
      guid: '3f0f0f85-9151-4f18-b68f-8e8f6f1e7b1a',
    );

    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      windows: initializationSettingsWindows,
    );

    await _localNotifications!.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'messages_channel',
        'Messages',
        description: 'Notifications for new messages',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      const callsChannel = AndroidNotificationChannel(
        'calls_channel',
        'Calls',
        description: 'Incoming calls',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      );

      const friendRequestsChannel = AndroidNotificationChannel(
        'friend_requests_channel',
        'Friend Requests',
        description: 'Notifications for friend requests',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      final plugin = _localNotifications!
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await plugin?.createNotificationChannel(channel);
      await plugin?.createNotificationChannel(callsChannel);
      await plugin?.createNotificationChannel(friendRequestsChannel);
    }
  }

  Future<String> _getCurrentDeviceId() async {
    try {
      final device = await _deviceInfo.getDeviceInfo();
      final id = device['deviceId']?.trim();
      if (id != null && id.isNotEmpty) {
        return id;
      }
    } catch (_) {}
    return 'unknown_device';
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null) {
      print('Cannot save FCM token: no user logged in');
      return;
    }

    try {
      final deviceId = await _getCurrentDeviceId();
      await _firestore.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokens.$deviceId': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
        'lastTokenDeviceId': deviceId,
      }, SetOptions(merge: true));

      print('Saved FCM token for ${user.uid} on device $deviceId');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  Future<void> clearToken() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final deviceId = await _getCurrentDeviceId();
        await _firestore.collection('users').doc(user.uid).set({
          'fcmToken': FieldValue.delete(),
          'fcmTokens.$deviceId': FieldValue.delete(),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
          'lastTokenDeviceId': deviceId,
        }, SetOptions(merge: true));
        print('Cleared FCM token for ${user.uid} on device $deviceId');
      } catch (e) {
        print('Error clearing FCM token: $e');
      }
    }

    _activeChatUserId = null;

    if (supportsLocalNotifications && _localNotifications != null) {
      if (_localInitialized) {
        await _localNotifications!.cancelAll();
      }
    }

    _messageCountPerSender.clear();
    _messagesPerSender.clear();
  }

  List<String> _extractRecipientTokens(Map<String, dynamic>? userData) {
    final tokens = <String>{};

    final legacyToken = userData?['fcmToken'];
    if (legacyToken is String && legacyToken.trim().isNotEmpty) {
      tokens.add(legacyToken.trim());
    }

    final tokenMap = userData?['fcmTokens'];
    if (tokenMap is Map) {
      for (final value in tokenMap.values) {
        if (value is String && value.trim().isNotEmpty) {
          tokens.add(value.trim());
        }
      }
    }

    return tokens.toList(growable: false);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    print('Foreground push received: ${message.messageId}');
    if (message.notification != null || message.data['type'] != null) {
      _showLocalNotification(message);
    }
  }

  void _handleBackgroundMessage(RemoteMessage message) {
    print('Push tapped from background: ${message.messageId}');
  }

  void _handleNotificationTap(NotificationResponse response) {
    unawaited(handleNotificationResponse(response));
  }

  Future<void> handleNotificationResponse(
    NotificationResponse response, {
    bool fromBackground = false,
  }) async {
    print(
      'Notification response: type=${response.notificationResponseType}, action=${response.actionId}, fromBackground=$fromBackground',
    );

    final payload = _decodePayload(response.payload);
    if (payload == null) return;

    final type = payload['type']?.toString();
    if (type != 'message') return;

    final senderId = payload['senderId']?.toString();
    final conversationId = payload['conversationId']?.toString();
    if (senderId == null || senderId.trim().isEmpty) {
      return;
    }

    if (response.notificationResponseType ==
        NotificationResponseType.selectedNotificationAction) {
      if (response.actionId == _markReadActionId) {
        await _markMessageNotificationAsRead(
          senderId: senderId,
          conversationId: conversationId,
        );
        return;
      }

      if (response.actionId == _replyActionId) {
        final replyText = response.input?.trim() ?? '';
        if (replyText.isEmpty) return;

        await _replyFromNotification(
          senderId: senderId,
          conversationId: conversationId,
          replyText: replyText,
        );
        return;
      }
    }
  }

  Map<String, dynamic>? _decodePayload(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      print('Invalid notification payload: $e');
    }
    return null;
  }

  Future<String?> _resolveConversationId(
    String senderId,
    String? conversationId,
  ) async {
    final trimmed = conversationId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return _chatService.initializeConversation(senderId);
  }

  Future<void> _markMessageNotificationAsRead({
    required String senderId,
    String? conversationId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final resolvedConversationId = await _resolveConversationId(
        senderId,
        conversationId,
      );
      if (resolvedConversationId == null) return;

      await _chatService.markMessagesAsRead(
        conversationId: resolvedConversationId,
        otherUserId: senderId,
      );

      await clearNotificationsForSender(senderId);
    } catch (e) {
      print('Failed to mark from notification: $e');
    }
  }

  Future<void> _replyFromNotification({
    required String senderId,
    String? conversationId,
    required String replyText,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final trimmed = replyText.trim();
    if (trimmed.isEmpty) return;

    try {
      await _chatService.initializeEncryption();
      final resolvedConversationId = await _resolveConversationId(
        senderId,
        conversationId,
      );
      if (resolvedConversationId == null) return;

      await _chatService.sendMessage(
        conversationId: resolvedConversationId,
        messageText: trimmed,
        recipientId: senderId,
      );

      await clearNotificationsForSender(senderId);
    } catch (e) {
      print('Failed to reply from notification: $e');
    }
  }

  Future<void> showIncomingCallNotification({
    required String callId,
    required String callerName,
    required bool isVideo,
  }) async {
    if (!supportsLocalNotifications ||
        _localNotifications == null ||
        !_localInitialized) {
      return;
    }

    final notificationId = callId.hashCode.abs() % 100000;
    final title = callerName.isEmpty ? 'Incoming call' : callerName;
    final body = isVideo ? 'Incoming video call' : 'Incoming call';

    final androidDetails = AndroidNotificationDetails(
      'calls_channel',
      'Calls',
      channelDescription: 'Incoming calls',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      timeoutAfter: 35000,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final windowsDetails = WindowsNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      windows: windowsDetails,
    );

    await _localNotifications!.show(
      notificationId,
      title,
      body,
      details,
      payload: jsonEncode({'type': 'call', 'callId': callId}),
    );
  }

  Future<void> clearCallNotification(String callId) async {
    if (!supportsLocalNotifications ||
        _localNotifications == null ||
        !_localInitialized) {
      return;
    }
    final notificationId = callId.hashCode.abs() % 100000;
    await _localNotifications!.cancel(notificationId);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (!supportsLocalNotifications ||
        _localNotifications == null ||
        !_localInitialized) {
      return;
    }

    final data = message.data;
    final type = data['type'];
    final senderId = data['senderId']?.toString();

    if (type == 'new_message' && senderId != null && senderId.isNotEmpty) {
      if (_activeChatUserId == senderId) {
        return;
      }

      _messageCountPerSender[senderId] =
          (_messageCountPerSender[senderId] ?? 0) + 1;
      final messageCount = _messageCountPerSender[senderId]!;

      final messageText =
          message.notification?.body ??
          data['messageText']?.toString() ??
          'New message';
      final senderName = data['senderName']?.toString() ?? 'Someone';
      final conversationId = data['conversationId']?.toString();

      final senderMessages = _messagesPerSender.putIfAbsent(
        senderId,
        () => <String>[],
      );
      senderMessages.add(messageText);
      if (senderMessages.length > 5) {
        senderMessages.removeAt(0);
      }

      final notificationId = senderId.hashCode.abs() % 100000;

      final androidDetails = AndroidNotificationDetails(
        'messages_channel',
        'Messages',
        channelDescription: 'Notifications for new messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        styleInformation: InboxStyleInformation(
          senderMessages,
          contentTitle: senderName,
          summaryText: messageCount > 1 ? '$messageCount messages' : null,
        ),
        number: messageCount,
        tag: 'message_$senderId',
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            _markReadActionId,
            'Mark read',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            _replyActionId,
            'Reply',
            showsUserInterface: true,
            allowGeneratedReplies: true,
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(label: 'Type your reply'),
            ],
          ),
        ],
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'messages',
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications!.show(
        notificationId,
        senderName,
        messageCount > 1 ? '$messageCount new messages' : messageText,
        notificationDetails,
        payload: jsonEncode({
          'type': 'message',
          'senderId': senderId,
          if (conversationId != null && conversationId.isNotEmpty)
            'conversationId': conversationId,
        }),
      );
    } else if (type == 'friend_request') {
      const androidDetails = AndroidNotificationDetails(
        'friend_requests_channel',
        'Friend Requests',
        channelDescription: 'Notifications for friend requests',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications!.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        message.notification?.title ?? 'New Friend Request',
        message.notification?.body ?? 'You have a new friend request',
        notificationDetails,
        payload: jsonEncode({'type': 'friend_request', 'senderId': senderId}),
      );
    }
  }

  Future<void> clearNotificationsForSender(String senderId) async {
    if (!supportsLocalNotifications ||
        _localNotifications == null ||
        !_localInitialized) {
      return;
    }

    final notificationId = senderId.hashCode.abs() % 100000;
    await _localNotifications!.cancel(notificationId);
    _messageCountPerSender.remove(senderId);
    _messagesPerSender.remove(senderId);
  }

  Future<void> sendFriendRequestNotification({
    required String recipientId,
    required String senderName,
  }) async {
    try {
      final recipientDoc = await _firestore
          .collection('users')
          .doc(recipientId)
          .get();

      if (!recipientDoc.exists) {
        print('Recipient user document not found');
        return;
      }

      final recipientData = recipientDoc.data();
      final tokens = _extractRecipientTokens(recipientData);

      if (tokens.isEmpty) {
        print('Recipient has no FCM tokens');
        return;
      }

      await _firestore.collection('notifications').add({
        'type': 'friend_request',
        'recipientId': recipientId,
        'senderId': _auth.currentUser?.uid,
        'fcmToken': tokens.first,
        'fcmTokens': tokens,
        'title': 'New Friend Request',
        'body': '$senderName sent you a friend request',
        'data': {
          'type': 'friend_request',
          'senderId': _auth.currentUser?.uid,
          'senderName': senderName,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      print('Error sending friend request notification: $e');
    }
  }

  Future<void> sendMessageNotification({
    required String recipientId,
    required String senderName,
    required String messageText,
    String? conversationId,
  }) async {
    try {
      final recipientDoc = await _firestore
          .collection('users')
          .doc(recipientId)
          .get();

      if (!recipientDoc.exists) {
        print('Recipient user document not found');
        return;
      }

      final recipientData = recipientDoc.data();
      final tokens = _extractRecipientTokens(recipientData);

      if (tokens.isEmpty) {
        print('Recipient has no FCM tokens');
        return;
      }

      final trimmedConversationId = conversationId?.trim();

      await _firestore.collection('notifications').add({
        'type': 'new_message',
        'recipientId': recipientId,
        'senderId': _auth.currentUser?.uid,
        'fcmToken': tokens.first,
        'fcmTokens': tokens,
        'title': senderName,
        'body': messageText.length > 100
            ? '${messageText.substring(0, 100)}...'
            : messageText,
        'data': {
          'type': 'new_message',
          'senderId': _auth.currentUser?.uid,
          'senderName': senderName,
          'messageText': messageText,
          if (trimmedConversationId != null && trimmedConversationId.isNotEmpty)
            'conversationId': trimmedConversationId,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      print('Error sending message notification: $e');
    }
  }

  Future<Map<String, bool>> getNotificationSettings() async {
    final user = _auth.currentUser;
    if (user == null) return {'friendRequests': true, 'messages': true};

    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications')
          .get();

      if (doc.exists) {
        return {
          'friendRequests': doc.data()?['friendRequests'] ?? true,
          'messages': doc.data()?['messages'] ?? true,
        };
      }
    } catch (e) {
      print('Error getting notification settings: $e');
    }

    return {'friendRequests': true, 'messages': true};
  }

  Future<void> updateNotificationSettings({
    required bool friendRequests,
    required bool messages,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications')
          .set({
            'friendRequests': friendRequests,
            'messages': messages,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error updating notification settings: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling background message: ${message.messageId}');
  print('Data: ${message.data}');
}
