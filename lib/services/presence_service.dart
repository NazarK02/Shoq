import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

/// Service to manage user online/offline presence and last seen
class PresenceService {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  Timer? _heartbeatTimer;
  bool _isOnline = false;

  /// Start tracking user presence
  Future<void> startPresenceTracking() async {
    final user = _auth.currentUser;
    if (user == null) return;

    print('🟢 Starting presence tracking for user: ${user.uid}');

    // Set user online immediately
    await setOnline();

    // Set up periodic heartbeat (every 30 seconds)
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      await _updateHeartbeat();
    });

    // Listen to app lifecycle changes
    _setupLifecycleObserver();
  }

  /// Stop tracking user presence
  Future<void> stopPresenceTracking() async {
    print('🔴 Stopping presence tracking');
    
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    await setOffline();
  }

  /// Set user as online
  Future<void> setOnline() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'status': 'online',
        'lastSeen': FieldValue.serverTimestamp(),
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
      
      _isOnline = true;
      print('✅ User set to online');
    } catch (e) {
      print('❌ Error setting user online: $e');
    }
  }

  /// Set user as offline
  Future<void> setOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'status': 'offline',
        'lastSeen': FieldValue.serverTimestamp(),
      });
      
      _isOnline = false;
      print('✅ User set to offline');
    } catch (e) {
      print('❌ Error setting user offline: $e');
    }
  }

  /// Update heartbeat to show user is still active
  Future<void> _updateHeartbeat() async {
    final user = _auth.currentUser;
    if (user == null || !_isOnline) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'lastHeartbeat': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
      });
      
      print('💓 Heartbeat updated');
    } catch (e) {
      print('❌ Error updating heartbeat: $e');
    }
  }

  /// Set up app lifecycle observer
  void _setupLifecycleObserver() {
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver(
      onResumed: () async {
        print('📱 App resumed - setting online');
        await setOnline();
      },
      onPaused: () async {
        print('📱 App paused - setting offline');
        await setOffline();
      },
    ));
  }

  /// Get user status stream
  Stream<Map<String, dynamic>?> getUserStatusStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      
      final data = snapshot.data()!;
      return {
        'status': data['status'] ?? 'offline',
        'lastSeen': data['lastSeen'],
        'isOnline': data['status'] == 'online',
      };
    });
  }

  /// Check if user is online based on last heartbeat
  /// If last heartbeat was more than 2 minutes ago, consider offline
  static bool isUserOnline(Map<String, dynamic> userData) {
    final status = userData['status'] as String?;
    final lastHeartbeat = userData['lastHeartbeat'] as Timestamp?;
    
    // First check explicit status
    if (status != 'online') return false;
    
    // If status is online but no heartbeat, they just logged in
    if (lastHeartbeat == null) return true;
    
    final lastHeartbeatTime = lastHeartbeat.toDate();
    final now = DateTime.now();
    final difference = now.difference(lastHeartbeatTime);
    
    // Consider offline if no heartbeat in last 2 minutes (allows for network delays)
    return difference.inSeconds < 120;
  }

  /// Format last seen time (returns just the relative time)
  static String formatLastSeen(Timestamp? lastSeen) {
    if (lastSeen == null) return 'unknown time';
    
    final lastSeenTime = lastSeen.toDate();
    final now = DateTime.now();
    final difference = now.difference(lastSeenTime);
    
    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      return '${lastSeenTime.day}/${lastSeenTime.month}/${lastSeenTime.year}';
    }
  }

  /// Get formatted status text
  static String getStatusText(Map<String, dynamic>? statusData) {
    if (statusData == null) return 'Offline';
    
    final isOnline = isUserOnline(statusData);
    
    if (isOnline) {
      return 'Online';
    } else {
      final lastSeen = statusData['lastSeen'] as Timestamp?;
      if (lastSeen == null) return 'Offline';
      return 'Last seen ${formatLastSeen(lastSeen)}';
    }
  }

  /// Dispose resources
  void dispose() {
    _heartbeatTimer?.cancel();
  }
}

/// App lifecycle observer
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final Function()? onResumed;
  final Function()? onPaused;

  _AppLifecycleObserver({
    this.onResumed,
    this.onPaused,
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onResumed?.call();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        onPaused?.call();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
}