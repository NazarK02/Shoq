import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service to manage user online/offline presence and last seen.
/// Lifecycle handling is done ONLY in main.dart's AuthWrapper —
/// this class does NOT add any WidgetsBindingObserver itself.
class PresenceService {
  static final PresenceService _instance = PresenceService._internal();
  factory PresenceService() => _instance;
  PresenceService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Timer? _heartbeatTimer;
  bool _isOnline = false;

  /// Start tracking user presence (called once on login).
  Future<void> startPresenceTracking() async {
    final user = _auth.currentUser;
    if (user == null) return;

    print('🟢 Starting presence tracking for user: ${user.uid}');

    await setOnline();

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _updateHeartbeat();
    });
  }

  /// Stop tracking (called on logout / auth-state null).
  Future<void> stopPresenceTracking() async {
    print('🔴 Stopping presence tracking');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await setOffline();
  }

  /// Set user as online.
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

  /// Set user as offline.
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

  // ---------------------------------------------------------------------------
  // Streams & helpers (static — no instance state needed)
  // ---------------------------------------------------------------------------

  /// Live stream of a single user's status fields.
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
        'lastHeartbeat': data['lastHeartbeat'],
      };
    });
  }

  /// One-off fetch of a user's status (safe for Windows polling)
  Future<Map<String, dynamic>?> getUserStatusOnce(String userId) async {
    try {
      final snapshot = await _firestore.collection('users').doc(userId).get();
      if (!snapshot.exists) return null;
      final data = snapshot.data()!;
      return {
        'status': data['status'] ?? 'offline',
        'lastSeen': data['lastSeen'],
        'lastHeartbeat': data['lastHeartbeat'],
      };
    } catch (e) {
      print('❌ Error fetching user status once: $e');
      return null;
    }
  }

  /// Returns true when status == online AND lastHeartbeat is fresh (< 2 min).
  static bool isUserOnline(Map<String, dynamic> userData) {
    final status = userData['status'] as String?;
    if (status != 'online') return false;

    final lastHeartbeat = userData['lastHeartbeat'] as Timestamp?;
    if (lastHeartbeat == null) return true; // just logged in, no heartbeat yet

    return DateTime.now().difference(lastHeartbeat.toDate()).inSeconds < 120;
  }

  /// Human-readable relative time string (no prefix/suffix).
  static String formatLastSeen(Timestamp? lastSeen) {
    if (lastSeen == null) return 'unknown time';

    final diff = DateTime.now().difference(lastSeen.toDate());

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return '$d ${d == 1 ? 'day' : 'days'} ago';
    }
    final t = lastSeen.toDate();
    return '${t.day}/${t.month}/${t.year}';
  }

  /// Full display string: "Online" or "Last seen …".
  static String getStatusText(Map<String, dynamic>? statusData) {
    if (statusData == null) return 'Offline';
    if (isUserOnline(statusData)) return 'Online';

    final lastSeen = statusData['lastSeen'] as Timestamp?;
    if (lastSeen == null) return 'Offline';
    return 'Last seen ${formatLastSeen(lastSeen)}';
  }

  void dispose() {
    _heartbeatTimer?.cancel();
  }
}