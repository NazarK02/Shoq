import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  FirebaseMessaging? _fcm;
  FlutterLocalNotificationsPlugin? _localNotifications;

  // Track messages per sender for inbox-style notifications
  final Map<String, int> _messageCountPerSender = {};
  final Map<String, List<String>> _messagesPerSender = {};
  
  String? _activeChatUserId;

  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  void setActiveChat(String? userId) {
    _activeChatUserId = userId;
    if (userId != null && isSupported) {
      clearNotificationsForSender(userId);
    }
  }

  String? getActiveChat() => _activeChatUserId;

  Future<void> initialize() async {
    if (!isSupported) {
      print('Push notifications not supported on this platform');
      return;
    }

    _fcm = FirebaseMessaging.instance;
    _localNotifications = FlutterLocalNotificationsPlugin();

    NotificationSettings settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await _fcm!.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }

      _fcm!.onTokenRefresh.listen(_saveTokenToFirestore);
      await _initializeLocalNotifications();
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (!isSupported || _localNotifications == null) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications!.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'messages_channel',
        'Messages',
        description: 'Notifications for new messages',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      const AndroidNotificationChannel friendRequestsChannel = AndroidNotificationChannel(
        'friend_requests_channel',
        'Friend Requests',
        description: 'Notifications for friend requests',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      final plugin = _localNotifications!.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      
      await plugin?.createNotificationChannel(channel);
      await plugin?.createNotificationChannel(friendRequestsChannel);
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _removeTokenFromOtherUsers(token, user.uid);
      
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving token: $e');
    }
  }

  Future<void> _removeTokenFromOtherUsers(String token, String currentUserId) async {
    try {
      final usersWithToken = await _firestore
          .collection('users')
          .where('fcmToken', isEqualTo: token)
          .get();

      for (var doc in usersWithToken.docs) {
        if (doc.id != currentUserId) {
          await _firestore.collection('users').doc(doc.id).update({
            'fcmToken': FieldValue.delete(),
          });
        }
      }
    } catch (e) {
      print('Error removing token from other users: $e');
    }
  }

  Future<void> clearToken() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'fcmToken': FieldValue.delete(),
        });
      } catch (e) {
        print('Error clearing token: $e');
      }
    }
    
    _activeChatUserId = null;
    
    if (isSupported && _localNotifications != null) {
      await _localNotifications!.cancelAll();
    }
    
    _messageCountPerSender.clear();
    _messagesPerSender.clear();
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (message.notification != null) {
      _showLocalNotification(message);
    }
  }

  void _handleBackgroundMessage(RemoteMessage message) {
    print('Message clicked!');
  }

  void _handleNotificationTap(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
  }

  /// KEY FIX: Single notification per sender that gets updated
  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (!isSupported || _localNotifications == null) return;

    final data = message.data;
    final type = data['type'];
    final senderId = data['senderId'];

    if (type == 'new_message' && senderId != null) {
      // Don't show notification if user is in the chat
      if (_activeChatUserId == senderId) {
        return;
      }

      _messageCountPerSender[senderId] = (_messageCountPerSender[senderId] ?? 0) + 1;
      final messageCount = _messageCountPerSender[senderId]!;

      final messageText = message.notification?.body ?? 'New message';
      if (!_messagesPerSender.containsKey(senderId)) {
        _messagesPerSender[senderId] = [];
      }
      _messagesPerSender[senderId]!.add(messageText);
      
      if (_messagesPerSender[senderId]!.length > 5) {
        _messagesPerSender[senderId]!.removeAt(0);
      }

      // CRITICAL: Use the same notification ID for each sender
      // This makes Android UPDATE the notification instead of creating a new one
      final notificationId = senderId.hashCode.abs() % 100000;
      final senderName = data['senderName'] ?? 'Someone';

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'messages_channel',
        'Messages',
        channelDescription: 'Notifications for new messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        styleInformation: InboxStyleInformation(
          _messagesPerSender[senderId]!,
          contentTitle: senderName,
          summaryText: messageCount > 1 ? '$messageCount messages' : null,
        ),
        number: messageCount,
        tag: 'message_$senderId', // Ensures only one notification per sender
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'messages',
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // This UPDATES the existing notification because we use the same ID
      await _localNotifications!.show(
        notificationId,
        senderName,
        messageCount > 1 ? '$messageCount new messages' : messageText,
        notificationDetails,
        payload: '{"type": "message", "senderId": "$senderId"}',
      );
    } else if (type == 'friend_request') {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'friend_requests_channel',
        'Friend Requests',
        channelDescription: 'Notifications for friend requests',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications!.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        message.notification?.title ?? 'New Friend Request',
        message.notification?.body ?? 'You have a new friend request',
        notificationDetails,
        payload: '{"type": "friend_request", "senderId": "$senderId"}',
      );
    }
  }

  Future<void> clearNotificationsForSender(String senderId) async {
    if (!isSupported || _localNotifications == null) return;

    final notificationId = senderId.hashCode.abs() % 100000;
    await _localNotifications!.cancel(notificationId);
    _messageCountPerSender.remove(senderId);
    _messagesPerSender.remove(senderId);
  }

  /// Send friend request notification WITHOUT database storage
  /// Note: This requires Firebase Cloud Functions for production use
  /// For now, this is a placeholder that you can replace with Cloud Functions
  Future<void> sendFriendRequestNotification({
    required String recipientId,
    required String senderName,
  }) async {
    // In production, use Firebase Cloud Functions (see firebase_functions_index.js)
    // For testing, you can use the simplified version below, but it's not recommended
    print('Friend request notification would be sent to: $recipientId from: $senderName');
    print('Deploy Cloud Functions for production notification sending');
  }

  /// Send message notification WITHOUT database storage
  /// Note: This requires Firebase Cloud Functions for production use
  Future<void> sendMessageNotification({
    required String recipientId,
    required String senderName,
    required String messageText,
  }) async {
    // In production, use Firebase Cloud Functions (see firebase_functions_index.js)
    // For testing, you can use the simplified version below, but it's not recommended
    print('Message notification would be sent to: $recipientId');
    print('Deploy Cloud Functions for production notification sending');
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
  print('Handling a background message: ${message.messageId}');
}