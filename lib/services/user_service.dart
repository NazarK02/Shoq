import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// 🔍 Automatically detect deviceId + deviceType
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
        'deviceId': android.id ?? android.serialNumber ?? 'android',
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

  /// ✅ Create or update user document + device + set online status
  Future<void> saveUserToFirestore({
    required User user,
  }) async {
    try {
      final device = await _getDeviceInfo();
      final deviceId = device['deviceId']!;
      final deviceType = device['deviceType']!;

      final userRef = _firestore.collection('users').doc(user.uid);

      await userRef.set({
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
        'status': 'online', // Set as online on login/registration
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

      print('✅ User + device saved successfully');
    } catch (e) {
      print('❌ Error saving user: $e');
    }
  }

  /// 📥 Get user data
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data();
    } catch (e) {
      print('❌ Error fetching user data: $e');
      return null;
    }
  }

  /// 🟢 Update lastSeen + current device activity
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

  /// 🟢 Set user status to online
  Future<void> setOnline() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).update({
      'status': 'online',
      'lastSeen': FieldValue.serverTimestamp(),
      'lastHeartbeat': FieldValue.serverTimestamp(),
    });
  }

  /// 🔴 Set user status to offline
  Future<void> setOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).update({
      'status': 'offline',
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  /// ✏️ Update profile
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

  /// 🔐 Current user
  User? getCurrentUser() => _auth.currentUser;

  /// 🚪 Sign out (set offline before signing out)
  Future<void> signOut() async {
    await setOffline();
    await _auth.signOut();
  }
}