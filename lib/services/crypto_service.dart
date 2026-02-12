import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';
import 'package:sodium_libs/sodium_libs.dart' as sodium_libs;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'device_info_service.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final DeviceInfoService _deviceInfo = DeviceInfoService();

  late Sodium _sodium;
  KeyPair? _keyPair;
  bool _initialized = false;
  static const _legacyStoragePrivateKey = 'crypto_private_key';
  static const _legacyStoragePublicKey = 'crypto_public_key';

  String _privateKeyStorageKey(String uid) => 'crypto_private_key_$uid';
  String _publicKeyStorageKey(String uid) => 'crypto_public_key_$uid';

  /// Initialize libsodium + load/generate keys
  Future<void> initialize() async {
    if (_initialized) return;

    _sodium = await sodium_libs.SodiumInit.init();

    await _loadOrCreateKeyPair();
    _initialized = _keyPair != null;
  }

  /// Load or generate keypair
  Future<void> _loadOrCreateKeyPair() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final privateKeyKey = _privateKeyStorageKey(user.uid);
    final publicKeyKey = _publicKeyStorageKey(user.uid);

    String? storedPrivateKey =
        await _secureStorage.read(key: privateKeyKey);
    String? storedPublicKey =
        await _secureStorage.read(key: publicKeyKey);

    // Migrate legacy keys (non-user-scoped) if present.
    if (storedPrivateKey == null) {
      storedPrivateKey =
          await _secureStorage.read(key: _legacyStoragePrivateKey);
      if (storedPrivateKey != null) {
        await _secureStorage.write(key: privateKeyKey, value: storedPrivateKey);
      }
    }
    if (storedPublicKey == null) {
      storedPublicKey =
          await _secureStorage.read(key: _legacyStoragePublicKey);
      if (storedPublicKey != null) {
        await _secureStorage.write(key: publicKeyKey, value: storedPublicKey);
      }
    }

    if (storedPrivateKey != null && storedPublicKey != null) {
      final secretKeyBytes = base64.decode(storedPrivateKey);
      final publicKeyBytes = base64.decode(storedPublicKey);
      final secretKey = SecureKey.fromList(_sodium, secretKeyBytes);
      _keyPair = KeyPair(
        publicKey: Uint8List.fromList(publicKeyBytes),
        secretKey: secretKey,
      );
      await _syncDevicePublicKey(base64.encode(_keyPair!.publicKey));
      return;
    }

    if (storedPrivateKey != null && storedPublicKey == null) {
      final secretKeyBytes = base64.decode(storedPrivateKey);
      final secretKey = SecureKey.fromList(_sodium, secretKeyBytes);

      // Try to load the public key from Firestore (should have been
      // written when the keypair was first created). If it's missing,
      // store it locally. If it's missing, generate a fresh keypair.
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final storedPublicKeyBase64 = userDoc.data()?['publicKey'] as String?;

      if (storedPublicKeyBase64 != null) {
        final publicKey = Uint8List.fromList(base64.decode(storedPublicKeyBase64));
        _keyPair = KeyPair(publicKey: publicKey, secretKey: secretKey);
        await _secureStorage.write(
          key: publicKeyKey,
          value: storedPublicKeyBase64,
        );
        await _syncDevicePublicKey(storedPublicKeyBase64);
      } else {
        // Public key missing and cannot be derived from secret key.
        // Generate a fresh keypair and replace stored keys.
        _keyPair = _sodium.crypto.box.keyPair();

        await _secureStorage.write(
          key: privateKeyKey,
          value: base64.encode(_keyPair!.secretKey.extractBytes()),
        );
        await _secureStorage.write(
          key: publicKeyKey,
          value: base64.encode(_keyPair!.publicKey),
        );

        final publicKeyBase64 = base64.encode(_keyPair!.publicKey);
        await _syncDevicePublicKey(publicKeyBase64);
        await _maybeWriteLegacyPublicKey(publicKeyBase64);
      }
    } else {
      _keyPair = _sodium.crypto.box.keyPair();

      final publicKeyBase64 = base64.encode(_keyPair!.publicKey);
      await _secureStorage.write(
        key: privateKeyKey,
        value: base64.encode(_keyPair!.secretKey.extractBytes()),
      );
      await _secureStorage.write(
        key: publicKeyKey,
        value: publicKeyBase64,
      );

      await _syncDevicePublicKey(publicKeyBase64);
      await _maybeWriteLegacyPublicKey(publicKeyBase64);
    }
  }

  Future<void> _syncDevicePublicKey(String publicKeyBase64) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final device = await _deviceInfo.getDeviceInfo();
    final deviceId = device['deviceId'] ?? 'unknown';
    final deviceType = device['deviceType'] ?? 'unknown';

    await _firestore.collection('users').doc(user.uid).set({
      'devices.$deviceId.deviceType': deviceType,
      'devices.$deviceId.publicKey': publicKeyBase64,
      'devices.$deviceId.publicKeyUpdatedAt': FieldValue.serverTimestamp(),
      'devices.$deviceId.lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _maybeWriteLegacyPublicKey(String publicKeyBase64) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final existing = userDoc.data()?['publicKey'] as String?;
    if (existing != null && existing.isNotEmpty) return;

    await _firestore.collection('users').doc(user.uid).set({
      'publicKey': publicKeyBase64,
      'publicKeyUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Encrypt message
  Future<String> encryptMessage({
    required String plaintext,
    required String recipientUserId,
  }) async {
    if (!_initialized || _keyPair == null) {
      throw Exception('CryptoService not ready');
    }

    final recipientDoc =
        await _firestore.collection('users').doc(recipientUserId).get();

    final recipientPublicKeyBase64 =
        recipientDoc.data()?['publicKey'] as String?;

    if (recipientPublicKeyBase64 == null) {
      throw Exception('Recipient has no public key');
    }

    return encryptMessageWithPublicKey(
      plaintext: plaintext,
      recipientPublicKeyBase64: recipientPublicKeyBase64,
    );
  }

  /// Decrypt message
  Future<String> decryptMessage({
    required String ciphertextBase64,
    required String senderUserId,
  }) async {
    if (!_initialized || _keyPair == null) {
      throw Exception('CryptoService not ready');
    }

    final senderDoc =
        await _firestore.collection('users').doc(senderUserId).get();

    final senderPublicKeyBase64 =
        senderDoc.data()?['publicKey'] as String?;

    if (senderPublicKeyBase64 == null) {
      throw Exception('Sender has no public key');
    }

    return decryptMessageWithSenderPublicKey(
      ciphertextBase64: ciphertextBase64,
      senderPublicKeyBase64: senderPublicKeyBase64,
    );
  }

  Future<String> encryptMessageWithPublicKey({
    required String plaintext,
    required String recipientPublicKeyBase64,
  }) async {
    if (!_initialized || _keyPair == null) {
      throw Exception('CryptoService not ready');
    }

    final recipientPublicKey =
        Uint8List.fromList(base64.decode(recipientPublicKeyBase64));

    final nonce = _sodium.randombytes
        .buf(_sodium.crypto.box.nonceBytes);

    final messageBytes = Uint8List.fromList(utf8.encode(plaintext));

    final cipherText = _sodium.crypto.box.easy(
      message: messageBytes,
      nonce: nonce,
      publicKey: recipientPublicKey,
      secretKey: _keyPair!.secretKey,
    );

    final combined = Uint8List.fromList([...nonce, ...cipherText]);
    return base64.encode(combined);
  }

  Future<String> decryptMessageWithSenderPublicKey({
    required String ciphertextBase64,
    required String senderPublicKeyBase64,
  }) async {
    if (!_initialized || _keyPair == null) {
      throw Exception('CryptoService not ready');
    }

    final senderPublicKey =
        Uint8List.fromList(base64.decode(senderPublicKeyBase64));

    final combined = base64.decode(ciphertextBase64);

    final nonceLength = _sodium.crypto.box.nonceBytes;
    final nonce = combined.sublist(0, nonceLength);
    final cipherText = combined.sublist(nonceLength);

    final plainBytes = _sodium.crypto.box.openEasy(
      cipherText: cipherText,
      nonce: nonce,
      publicKey: senderPublicKey,
      secretKey: _keyPair!.secretKey,
    );

    return utf8.decode(plainBytes);
  }

  bool get isEncryptionEnabled => _initialized && _keyPair != null;

  String? get myPublicKeyBase64 =>
      _keyPair == null ? null : base64.encode(_keyPair!.publicKey);

  Future<void> clear() async {
    _keyPair?.secretKey.dispose();
    _keyPair = null;
    _initialized = false;
  }
}
