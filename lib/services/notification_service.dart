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
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // Save FCM token to Firestore
  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
    }
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

  // Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
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
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      notificationDetails,
      payload: message.data.toString(),
    );
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