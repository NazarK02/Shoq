import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Track message counts per conversation for notification grouping
  final Map<String, int> _messageCountPerSender = {};
  // Track all messages per sender for inbox style
  final Map<String, List<String>> _messagesPerSender = {};

  // Initialize notifications
  Future<void> initialize() async {
    // Request permission
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
      
      // Get FCM token
      String? token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }

      // Listen for token refresh
      _fcm.onTokenRefresh.listen(_saveTokenToFirestore);

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

  // Initialize local notifications for Android
  Future<void> _initializeLocalNotifications() async {
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

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Create notification channel for Android
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

    final plugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    await plugin?.createNotificationChannel(channel);
    await plugin?.createNotificationChannel(friendRequestsChannel);
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
    
    // Clear all local notifications
    await _localNotifications.cancelAll();
    
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
    final data = message.data;
    final type = data['type'];
    final senderId = data['senderId'];

    if (type == 'new_message' && senderId != null) {
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

      // Use senderId hash as notification ID to update the same notification
      final notificationId = senderId.hashCode;
      
      final senderName = data['senderName'] ?? 'Someone';

      // Create inbox style notification showing all messages
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'messages_channel',
        'Messages',
        channelDescription: 'Notifications for new messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        groupKey: 'messages',
        setAsGroupSummary: false,
        styleInformation: InboxStyleInformation(
          _messagesPerSender[senderId]!,
          contentTitle: senderName,
          summaryText: messageCount > 1 ? '$messageCount messages' : null,
        ),
        number: messageCount,
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

      await _localNotifications.show(
        notificationId,
        senderName,
        messageCount > 1 ? '$messageCount new messages' : messageText,
        notificationDetails,
        payload: '{"type": "message", "senderId": "$senderId"}',
      );

      // Show group summary for Android (if multiple conversations)
      if (_messageCountPerSender.length > 1) {
        await _showGroupSummaryNotification();
      }
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

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        message.notification?.title ?? 'New Friend Request',
        message.notification?.body ?? 'You have a new friend request',
        notificationDetails,
        payload: '{"type": "friend_request", "senderId": "$senderId"}',
      );
    }
  }

  // Show group summary notification (Android only)
  Future<void> _showGroupSummaryNotification() async {
    final totalMessages = _messageCountPerSender.values.fold<int>(0, (sum, count) => sum + count);
    
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'messages_channel',
      'Messages',
      channelDescription: 'Notifications for new messages',
      importance: Importance.high,
      priority: Priority.high,
      groupKey: 'messages',
      setAsGroupSummary: true,
      styleInformation: InboxStyleInformation(
        [],
        contentTitle: 'New messages',
        summaryText: '$totalMessages new messages from ${_messageCountPerSender.length} conversations',
      ),
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _localNotifications.show(
      0, // Group summary always uses ID 0
      'New messages',
      '$totalMessages new messages',
      notificationDetails,
    );
  }

  // Clear notifications for a specific sender (when opening chat)
  Future<void> clearNotificationsForSender(String senderId) async {
    final notificationId = senderId.hashCode;
    await _localNotifications.cancel(notificationId);
    _messageCountPerSender.remove(senderId);
    _messagesPerSender.remove(senderId);

    // Update group summary if needed
    if (_messageCountPerSender.isNotEmpty) {
      await _showGroupSummaryNotification();
    } else {
      await _localNotifications.cancel(0); // Clear group summary
    }
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