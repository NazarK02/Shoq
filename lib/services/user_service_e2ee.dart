import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto_service.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final CryptoService _crypto = CryptoService();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  Map<String, dynamic>? _cachedUserData;

  /// Automatically detect deviceId + deviceType
  Future<Map<String, String>> _getDeviceInfo() async {
    if (kIsWeb) {
      return {
        'deviceId': 'web',
        'deviceType': 'web',
      };
    }

    if (Platform.isAndroid) {
      final android = await _deviceInfo.androidInfo;
      return {
        'deviceId': android.id,
        'deviceType': 'android',
      };
    }

    if (Platform.isIOS) {
      final ios = await _deviceInfo.iosInfo;
      return {
        'deviceId': ios.identifierForVendor ?? 'ios',
        'deviceType': 'ios',
      };
    }

    if (Platform.isWindows) {
      final windows = await _deviceInfo.windowsInfo;
      return {
        'deviceId': windows.deviceId,
        'deviceType': 'windows',
      };
    }

    if (Platform.isMacOS) {
      final mac = await _deviceInfo.macOsInfo;
      return {
        'deviceId': mac.systemGUID ?? 'macos',
        'deviceType': 'macos',
      };
    }

    return {
      'deviceId': 'unknown',
      'deviceType': 'unknown',
    };
  }

  /// Create or update user document (basic info only, no E2EE yet)
  Future<void> saveUserToFirestore({
    required User user,
  }) async {
    try {
      final device = await _getDeviceInfo();
      final deviceId = device['deviceId']!;
      final deviceType = device['deviceType']!;

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
        'devices': {
          deviceId: {
            'deviceType': deviceType,
            'lastActive': FieldValue.serverTimestamp(),
          }
        }
      }, SetOptions(merge: true));

      print('✅ User document saved successfully');

    } catch (e) {
      print('❌ Error saving user: $e');
      rethrow;
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
        _cachedUserData = {
          ..._cachedUserData ?? {},
          ...decoded,
        };
        return decoded;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _persistProfileCache(String uid, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = <String, dynamic>{
      'displayName': data['displayName'] ?? '',
      'photoUrl': data['photoUrl'] ?? '',
      'bio': data['bio'] ?? '',
      'website': data['website'] ?? '',
      'location': data['location'] ?? '',
    };
    await prefs.setString('profile_cache_$uid', jsonEncode(cache));
  }

  /// Initialize E2EE for existing user (call AFTER user document is created)
  Future<void> initializeE2EE() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in');

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.data()?['publicKey'] != null) {
        print('E2EE already initialized for user: ${user.uid}');
        return;
      }

      print('Initializing E2EE for user: ${user.uid}');

      await _crypto.initialize();

      final publicKey = _crypto.myPublicKeyBase64;

      if (publicKey == null) {
        throw Exception('Failed to generate encryption keys');
      }

      print('E2EE initialized, public key: ${publicKey.substring(0, 20)}...');

      // Update user document with public key
      await _firestore.collection('users').doc(user.uid).set({
        'publicKey': publicKey,
        'publicKeyUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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

    final device = await _getDeviceInfo();
    final deviceId = device['deviceId']!;

    await _firestore.collection('users').doc(user.uid).update({
      'lastSeen': FieldValue.serverTimestamp(),
      'lastHeartbeat': FieldValue.serverTimestamp(),
      'devices.$deviceId.lastActive': FieldValue.serverTimestamp(),
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
    await _auth.signOut();
  }
}
