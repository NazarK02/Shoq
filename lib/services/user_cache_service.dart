import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight user profile cache (memory + SharedPreferences).
/// Keeps the UI responsive and avoids waiting on Firestore for every screen.
class UserCacheService extends ChangeNotifier {
  static final UserCacheService _instance = UserCacheService._internal();
  factory UserCacheService() => _instance;
  UserCacheService._internal();

  static const String _indexKey = 'user_cache_index';
  static const int _maxPersistedUsers = 200;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Map<String, dynamic>> _cache = {};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _subs = {};
  final Map<String, Future<void>> _inflight = {};

  Map<String, dynamic>? getCachedUser(String uid) => _cache[uid];

  Future<void> warmUsers(Iterable<String> ids, {bool listen = false}) async {
    final unique = ids.where((id) => id.trim().isNotEmpty).toSet();
    if (unique.isEmpty) return;
    await Future.wait(unique.map((id) => _loadUser(id, listen: listen)));
  }

  /// Merge partial data (e.g., from contacts docs) into the cache.
  void mergeUserData(String uid, Map<String, dynamic> partial) {
    if (uid.trim().isEmpty) return;
    final normalized = _normalizeUserData(partial);
    if (normalized.isEmpty) return;
    _cache[uid] = {
      ..._cache[uid] ?? {},
      ...normalized,
    };
    _persistUser(uid, _cache[uid]!);
    notifyListeners();
  }

  void clear() {
    for (final sub in _subs.values) {
      sub.cancel();
    }
    _subs.clear();
    _cache.clear();
    notifyListeners();
  }

  Future<void> _loadUser(String uid, {bool listen = true}) async {
    if (_inflight.containsKey(uid)) return _inflight[uid];
    final future = _loadUserInternal(uid, listen: listen);
    _inflight[uid] = future;
    try {
      await future;
    } finally {
      _inflight.remove(uid);
    }
  }

  Future<void> _loadUserInternal(String uid, {bool listen = true}) async {
    if (_cache.containsKey(uid)) {
      if (listen) _ensureListener(uid);
      return;
    }

    final fromPrefs = await _loadFromPrefs(uid);
    if (fromPrefs != null) {
      _cache[uid] = fromPrefs;
      if (listen) _ensureListener(uid);
      notifyListeners();
    }

    // Try Firestore cache first, then server.
    try {
      final cachedDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      if (cachedDoc.exists && cachedDoc.data() != null) {
        _updateFromFirestore(uid, cachedDoc.data()!);
      }
    } catch (_) {}

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        _updateFromFirestore(uid, doc.data()!);
      }
    } catch (_) {}

    if (listen) _ensureListener(uid);
  }

  void _ensureListener(String uid) {
    if (_subs.containsKey(uid)) return;

    // Avoid live Firestore listeners on Windows due to platform-channel
    // threading issues observed in the Flutter Windows shell. Instead,
    // rely on one-off fetches which are already performed elsewhere.
    if (Platform.isWindows) return;

    _subs[uid] = _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      _updateFromFirestore(uid, data, notify: true);
    });
  }

  void _updateFromFirestore(
    String uid,
    Map<String, dynamic> data, {
    bool notify = false,
  }) {
    final normalized = _normalizeUserData(data);
    if (normalized.isEmpty) return;
    _cache[uid] = {
      ..._cache[uid] ?? {},
      ...normalized,
    };
    _persistUser(uid, _cache[uid]!);
    if (notify) notifyListeners();
  }

  Map<String, dynamic> _normalizeUserData(Map<String, dynamic> data) {
    final normalized = <String, dynamic>{};

    final photo = data['photoUrl'] ?? data['photoURL'];
    if (photo != null) normalized['photoUrl'] = photo;

    for (final key in [
      'displayName',
      'email',
      'bio',
      'website',
      'location',
      'status',
      'socialLinks',
    ]) {
      final value = data[key];
      if (value != null) normalized[key] = value;
    }

    for (final key in ['createdAt', 'lastSeen', 'lastHeartbeat']) {
      final value = data[key];
      if (value is Timestamp) {
        normalized[key] = value;
      } else if (value is int) {
        normalized[key] = Timestamp.fromMillisecondsSinceEpoch(value);
      }
    }

    return normalized;
  }

  Future<Map<String, dynamic>?> _loadFromPrefs(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_cache_$uid');
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final data = <String, dynamic>{};
        for (final entry in decoded.entries) {
          if (entry.key == 'createdAt' ||
              entry.key == 'lastSeen' ||
              entry.key == 'lastHeartbeat') {
            if (entry.value is int) {
              data[entry.key] = Timestamp.fromMillisecondsSinceEpoch(entry.value as int);
            }
          } else {
            data[entry.key] = entry.value;
          }
        }
        return _normalizeUserData(data);
      }
    } catch (_) {}

    return null;
  }

  Future<void> _persistUser(String uid, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{};

    for (final entry in data.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is Timestamp) {
        payload[entry.key] = value.millisecondsSinceEpoch;
      } else {
        payload[entry.key] = value;
      }
    }

    await prefs.setString('user_cache_$uid', jsonEncode(payload));
    await _touchIndex(prefs, uid);
  }

  Future<void> _touchIndex(SharedPreferences prefs, String uid) async {
    final list = prefs.getStringList(_indexKey) ?? <String>[];
    list.remove(uid);
    list.add(uid);

    while (list.length > _maxPersistedUsers) {
      final removed = list.removeAt(0);
      await prefs.remove('user_cache_$removed');
      _cache.remove(removed);
    }

    await prefs.setStringList(_indexKey, list);
  }
}
