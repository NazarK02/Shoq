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
  
  // These will be null on unsupported platforms
  FirebaseMessaging? _fcm;
  FlutterLocalNotificationsPlugin? _localNotifications;

  // Track message counts per conversation for notification grouping
  final Map<String, int> _messageCountPerSender = {};
  // Track all messages per sender for inbox style
  final Map<String, List<String>> _messagesPerSender = {};
  
  // Track which chat is currently active/open
  String? _activeChatUserId;

  // Check if notifications are supported on this platform
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  // Set the currently active chat
  void setActiveChat(String? userId) {
    _activeChatUserId = userId;
    print('Active chat set to: $userId');
    
    // Clear notifications for this user when opening their chat
    if (userId != null && isSupported) {
      clearNotificationsForSender(userId);
    }
  }

  // Get the currently active chat
  String? getActiveChat() => _activeChatUserId;

  // Initialize notifications
  Future<void> initialize() async {
    // Skip initialization on unsupported platforms
    if (!isSupported) {
      print('Push notifications not supported on this platform (Windows/Web/macOS/Linux)');
      return;
    }

    _fcm = FirebaseMessaging.instance;
    _localNotifications = FlutterLocalNotificationsPlugin();

    // Request permission
    NotificationSettings settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
      
      // Get FCM token
      String? token = await _fcm!.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }

      // Listen for token refresh
      _fcm!.onTokenRefresh.listen(_saveTokenToFirestore);

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background messages
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);
    } else {
      print('User declined or has not accepted permission');
    }
  }

  // Initialize local notifications for Android/iOS
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

    // Create notification channel for Android
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

  // Save FCM token to Firestore
  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // First, remove this token from any other user's document
      await _removeTokenFromOtherUsers(token, user.uid);
      
      // Then save it to the current user
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving token: $e');
    }
  }

  // Remove token from other users (for account switching on same device)
  Future<void> _removeTokenFromOtherUsers(String token, String currentUserId) async {
    try {
      // Find all users with this token
      final usersWithToken = await _firestore
          .collection('users')
          .where('fcmToken', isEqualTo: token)
          .get();

      // Remove token from users that are NOT the current user
      for (var doc in usersWithToken.docs) {
        if (doc.id != currentUserId) {
          await _firestore.collection('users').doc(doc.id).update({
            'fcmToken': FieldValue.delete(),
          });
          print('Removed token from old user: ${doc.id}');
        }
      }
    } catch (e) {
      print('Error removing token from other users: $e');
    }
  }

  // Clear token when logging out (IMPORTANT for account switching)
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
    
    // Clear active chat
    _activeChatUserId = null;
    
    // Clear all local notifications (only on supported platforms)
    if (isSupported && _localNotifications != null) {
      await _localNotifications!.cancelAll();
    }
    
    // Clear message counts and message history
    _messageCountPerSender.clear();
    _messagesPerSender.clear();
  }

  // Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    if (message.notification != null) {
      _showLocalNotification(message);
    }
  }

  // Handle background messages (when user taps notification)
  void _handleBackgroundMessage(RemoteMessage message) {
    print('Message clicked!');
    // Navigate to appropriate screen based on message data
    // This will be handled in your main app navigation
  }

  // Handle notification tap
  void _handleNotificationTap(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
    // Handle navigation based on payload
  }

  // Show local notification with grouping
  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (!isSupported || _localNotifications == null) return;

    final data = message.data;
    final type = data['type'];
    final senderId = data['senderId'];

    if (type == 'new_message' && senderId != null) {
      // Check if user is currently in chat with this sender
      if (_activeChatUserId == senderId) {
        print('User is currently in chat with $senderId, skipping notification');
        return;
      }

      // Increment message count for this sender
      _messageCountPerSender[senderId] = (_messageCountPerSender[senderId] ?? 0) + 1;
      final messageCount = _messageCountPerSender[senderId]!;

      // Add message to the list for this sender
      final messageText = message.notification?.body ?? 'New message';
      if (!_messagesPerSender.containsKey(senderId)) {
        _messagesPerSender[senderId] = [];
      }
      _messagesPerSender[senderId]!.add(messageText);
      
      // Keep only last 5 messages to avoid overflow
      if (_messagesPerSender[senderId]!.length > 5) {
        _messagesPerSender[senderId]!.removeAt(0);
      }

      // Use a consistent notification ID for each sender
      final notificationId = senderId.hashCode.abs() % 100000;
      
      final senderName = data['senderName'] ?? 'Someone';

      print('Showing notification for $senderName (ID: $notificationId, count: $messageCount)');

      // Create inbox style notification showing all messages
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
        tag: 'message_$senderId',
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

      await _localNotifications!.show(
        notificationId,
        senderName,
        messageCount > 1 ? '$messageCount new messages' : messageText,
        notificationDetails,
        payload: '{"type": "message", "senderId": "$senderId"}',
      );

      print('Notification shown successfully');
    } else if (type == 'friend_request') {
      // Friend request notification (separate channel)
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

  // Clear notifications for a specific sender (when opening chat)
  Future<void> clearNotificationsForSender(String senderId) async {
    if (!isSupported || _localNotifications == null) return;

    final notificationId = senderId.hashCode.abs() % 100000;
    await _localNotifications!.cancel(notificationId);
    _messageCountPerSender.remove(senderId);
    _messagesPerSender.remove(senderId);
    
    print('Cleared notifications for sender: $senderId');
  }

  // Send friend request notification
  Future<void> sendFriendRequestNotification({
    required String recipientId,
    required String senderName,
  }) async {
    try {
      final recipientDoc = await _firestore.collection('users').doc(recipientId).get();
      final fcmToken = recipientDoc.data()?['fcmToken'];

      if (fcmToken != null) {
        // Create notification document for Cloud Function to process
        await _firestore.collection('notifications').add({
          'type': 'friend_request',
          'recipientId': recipientId,
          'fcmToken': fcmToken,
          'title': 'New Friend Request',
          'body': '$senderName sent you a friend request',
          'data': {
            'type': 'friend_request',
            'senderId': _auth.currentUser?.uid,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        });
      }
    } catch (e) {
      print('Error sending friend request notification: $e');
    }
  }

  // Send message notification
  Future<void> sendMessageNotification({
    required String recipientId,
    required String senderName,
    required String messageText,
  }) async {
    try {
      final recipientDoc = await _firestore.collection('users').doc(recipientId).get();
      final fcmToken = recipientDoc.data()?['fcmToken'];

      if (fcmToken != null) {
        // Create notification document for Cloud Function to process
        await _firestore.collection('notifications').add({
          'type': 'new_message',
          'recipientId': recipientId,
          'fcmToken': fcmToken,
          'title': senderName,
          'body': messageText.length > 100 ? '${messageText.substring(0, 100)}...' : messageText,
          'data': {
            'type': 'new_message',
            'senderId': _auth.currentUser?.uid,
            'senderName': senderName,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        });
      }
    } catch (e) {
      print('Error sending message notification: $e');
    }
  }

  // Get notification settings
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

  // Update notification settings
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

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
}