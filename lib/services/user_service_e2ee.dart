import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'crypto_service.dart';
import 'device_info_service.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CryptoService _crypto = CryptoService();
  final DeviceInfoService _deviceInfo = DeviceInfoService();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  Map<String, dynamic>? _cachedUserData;
  String? _lastProfileCacheJson;

  /// Automatically detect deviceId + deviceType
  Future<Map<String, String>> _getDeviceInfo() async {
    return _deviceInfo.getDeviceInfo();
  }

  /// Create or update user document (basic info only, no E2EE yet)
  Future<void> saveUserToFirestore({required User user}) async {
    try {
      final userRef = _firestore.collection('users').doc(user.uid);

      print('💾 Saving user document for: ${user.uid}');

      // Create/update user document WITHOUT E2EE (that happens separately)
      await userRef.set({
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
        'status': 'online',
        'lastSeen': FieldValue.serverTimestamp(),
        'lastHeartbeat': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _cleanupLegacyDeviceMetadata(user.uid);

      print('✅ User document saved successfully');
    } catch (e) {
      print('❌ Error saving user: $e');
      rethrow;
    }
  }

  Future<void> _cleanupLegacyDeviceMetadata(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return;

    final devices = data['devices'];
    if (devices is! Map) return;

    final deletes = <String, dynamic>{};

    void walk(dynamic node, String path) {
      if (node is! Map) return;

      for (final entry in node.entries) {
        final key = entry.key.toString();
        final nextPath = path.isEmpty ? key : '$path.$key';

        if (key == 'deviceType' || key == 'lastActive') {
          deletes['devices.$nextPath'] = FieldValue.delete();
          continue;
        }

        walk(entry.value, nextPath);
      }
    }

    walk(devices, '');

    if (deletes.isNotEmpty) {
      await _firestore.collection('users').doc(uid).update(deletes);
    }
  }

  /// Start a live listener for the current user's document.
  void startUserDocListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    _userDocSub?.cancel();
    _userDocSub = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data();
            _cachedUserData = data;
            if (data != null) {
              _persistProfileCache(user.uid, data);
            }
          }
        });
  }

  void stopUserDocListener() {
    _userDocSub?.cancel();
    _userDocSub = null;
    _cachedUserData = null;
  }

  Map<String, dynamic>? get cachedUserData => _cachedUserData;

  Future<Map<String, dynamic>?> loadCachedProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('profile_cache_${user.uid}');
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cachedUserData = {..._cachedUserData ?? {}, ...decoded};
        return decoded;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _persistProfileCache(
    String uid,
    Map<String, dynamic> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = <String, dynamic>{
      'displayName': data['displayName'] ?? '',
      'photoUrl': data['photoUrl'] ?? '',
      'bio': data['bio'] ?? '',
      'website': data['website'] ?? '',
      'location': data['location'] ?? '',
      'socialLinks': data['socialLinks'] ?? [],
    };
    final jsonCache = jsonEncode(cache);
    if (jsonCache == _lastProfileCacheJson) return;
    _lastProfileCacheJson = jsonCache;
    await prefs.setString('profile_cache_$uid', jsonCache);
  }

  /// Initialize E2EE for existing user (call AFTER user document is created)
  Future<void> initializeE2EE() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in');

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      await _crypto.initialize();

      final publicKey = _crypto.myPublicKeyBase64;

      if (publicKey == null) {
        throw Exception('Failed to generate encryption keys');
      }

      print('E2EE initialized, public key: ${publicKey.substring(0, 20)}...');

      final device = await _getDeviceInfo();
      final deviceId = device['deviceId'] ?? 'unknown';

      final updates = <String, dynamic>{
        'devices.$deviceId.publicKey': publicKey,
        'devices.$deviceId.publicKeyUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (userDoc.data()?['publicKey'] == null) {
        updates['publicKey'] = publicKey;
        updates['publicKeyUpdatedAt'] = FieldValue.serverTimestamp();
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(updates, SetOptions(merge: true));

      print('Public key saved to Firestore');
    } catch (e) {
      print('Error initializing E2EE: $e');
      rethrow;
    }
  }

  /// Get user data
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      print('❌ Error fetching user data: $e');
      return null;
    }
  }

  /// Update lastSeen + current device activity
  Future<void> updateLastSeen() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).update({
      'lastSeen': FieldValue.serverTimestamp(),
      'lastHeartbeat': FieldValue.serverTimestamp(),
    });
  }

  /// Set user status to online
  Future<void> setOnline() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).update({
      'status': 'online',
      'lastSeen': FieldValue.serverTimestamp(),
      'lastHeartbeat': FieldValue.serverTimestamp(),
    });
  }

  /// Set user status to offline
  Future<void> setOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).update({
      'status': 'offline',
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  /// Update profile
  Future<void> updateUserProfile({
    String? displayName,
    String? photoUrl,
    String? status,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final updates = <String, dynamic>{};

    if (displayName != null) updates['displayName'] = displayName;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    if (status != null) updates['status'] = status;

    if (updates.isNotEmpty) {
      await _firestore.collection('users').doc(user.uid).update(updates);
    }

    if (displayName != null) await user.updateDisplayName(displayName);
    if (photoUrl != null) await user.updatePhotoURL(photoUrl);
  }

  /// Current user
  User? getCurrentUser() => _auth.currentUser;

  /// Sign out (clear encryption keys and set offline)
  Future<void> signOut() async {
    await setOffline();
    await _crypto.clear();
    stopUserDocListener();
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      await googleSignIn.disconnect();
    } catch (e) {
      print('Google sign-out skipped/failed: $e');
    }
    await _auth.signOut();
  }
}
