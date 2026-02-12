import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'crypto_service.dart';
import 'device_info_service.dart';

/// Migration helper to add E2EE keys to existing users
class E2EEMigrationHelper {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CryptoService _crypto = CryptoService();
  final DeviceInfoService _deviceInfo = DeviceInfoService();

  /// Check if current user has encryption enabled
  Future<bool> currentUserHasEncryption() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final data = userDoc.data();
    if (data == null) return false;
    if (data['publicKey'] != null) return true;
    final devices = data['devices'];
    if (devices is Map) {
      for (final entry in devices.entries) {
        final value = entry.value;
        if (value is Map && value['publicKey'] is String) {
          return true;
        }
      }
    }
    return false;
  }

  /// Initialize encryption for current user if not already set up
  Future<void> ensureCurrentUserHasEncryption() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in');

    // Check if user already has a public key
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.data()?['publicKey'] != null) {
      print('User already has encryption enabled');
      return;
    }

    print('Migrating user to E2EE...');

    // Initialize crypto service
    await _crypto.initialize();

    final publicKey = _crypto.myPublicKeyBase64;
    if (publicKey == null) {
      throw Exception('Failed to generate encryption keys');
    }

    final device = await _deviceInfo.getDeviceInfo();
    final deviceId = device['deviceId'] ?? 'unknown';
    final deviceType = device['deviceType'] ?? 'unknown';

    final updates = <String, dynamic>{
      'devices.$deviceId.deviceType': deviceType,
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

    print('User migrated to E2EE successfully');
  }

  /// Run migration on app startup
  static Future<void> runMigrationIfNeeded() async {
    final helper = E2EEMigrationHelper();
    
    try {
      final hasEncryption = await helper.currentUserHasEncryption();
      
      if (!hasEncryption) {
        print('⚠️  User does not have E2EE enabled. Running migration...');
        await helper.ensureCurrentUserHasEncryption();
      }
    } catch (e) {
      print('❌ Migration failed: $e');
      // Don't throw - app should still work, just warn user
    }
  }
}
