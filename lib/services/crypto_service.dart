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
  static const _accountKeyBackupDocId = 'e2ee_keys';

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

    String? storedPrivateKey = await _secureStorage.read(key: privateKeyKey);
    String? storedPublicKey = await _secureStorage.read(key: publicKeyKey);

    // Migrate legacy keys (non-user-scoped) if present.
    if (storedPrivateKey == null) {
      storedPrivateKey = await _secureStorage.read(
        key: _legacyStoragePrivateKey,
      );
      if (storedPrivateKey != null) {
        await _secureStorage.write(key: privateKeyKey, value: storedPrivateKey);
      }
    }
    if (storedPublicKey == null) {
      storedPublicKey = await _secureStorage.read(key: _legacyStoragePublicKey);
      if (storedPublicKey != null) {
        await _secureStorage.write(key: publicKeyKey, value: storedPublicKey);
      }
    }

    final legacyPublicKey = await _fetchLegacyPublicKey(user.uid);
    final localMaterial = await _resolveLocalKeyMaterial(
      uid: user.uid,
      privateKeyBase64: storedPrivateKey,
      publicKeyBase64: storedPublicKey,
    );
    final backupMaterial = await _loadAccountKeyBackup(uid: user.uid);

    _ResolvedKeyMaterial selected;
    var shouldPersistBackup = false;

    if (backupMaterial != null) {
      final backupMatchesLegacy = _matchesLegacyPublicKey(
        backupMaterial.publicKeyBase64,
        legacyPublicKey,
      );
      final localMatchesLegacy =
          localMaterial != null &&
          _matchesLegacyPublicKey(
            localMaterial.publicKeyBase64,
            legacyPublicKey,
          );

      if (!backupMatchesLegacy && localMatchesLegacy) {
        selected = localMaterial;
        shouldPersistBackup = true;
      } else {
        selected = backupMaterial;
      }
    } else if (localMaterial != null) {
      selected = localMaterial;
      shouldPersistBackup = _matchesLegacyPublicKey(
        selected.publicKeyBase64,
        legacyPublicKey,
      );
    } else {
      final generated = _sodium.crypto.box.keyPair();
      final generatedMaterial = _ResolvedKeyMaterial(
        privateKeyBase64: base64.encode(generated.secretKey.extractBytes()),
        publicKeyBase64: base64.encode(generated.publicKey),
      );
      generated.secretKey.dispose();

      selected = generatedMaterial;
      shouldPersistBackup = _matchesLegacyPublicKey(
        selected.publicKeyBase64,
        legacyPublicKey,
      );
    }

    if (shouldPersistBackup) {
      await _saveAccountKeyBackup(uid: user.uid, material: selected);
    }

    final selectedSecretBytes = _decodeBase64OrNull(selected.privateKeyBase64);
    final selectedPublicBytes = _decodeBase64OrNull(selected.publicKeyBase64);
    if (selectedSecretBytes == null || selectedPublicBytes == null) {
      throw Exception('Failed to load account encryption key material');
    }

    final secretKey = SecureKey.fromList(_sodium, selectedSecretBytes);
    _keyPair = KeyPair(
      publicKey: Uint8List.fromList(selectedPublicBytes),
      secretKey: secretKey,
    );

    await _secureStorage.write(
      key: privateKeyKey,
      value: selected.privateKeyBase64,
    );
    await _secureStorage.write(
      key: publicKeyKey,
      value: selected.publicKeyBase64,
    );

    await _syncDevicePublicKey(selected.publicKeyBase64);
    await _maybeWriteLegacyPublicKey(selected.publicKeyBase64);
  }

  bool _matchesLegacyPublicKey(
    String publicKeyBase64,
    String? legacyPublicKey,
  ) {
    if (legacyPublicKey == null || legacyPublicKey.trim().isEmpty) {
      return true;
    }
    return legacyPublicKey.trim() == publicKeyBase64.trim();
  }

  Future<_ResolvedKeyMaterial?> _resolveLocalKeyMaterial({
    required String uid,
    required String? privateKeyBase64,
    required String? publicKeyBase64,
  }) async {
    final secretKeyBytes = _decodeBase64OrNull(privateKeyBase64);
    if (secretKeyBytes == null) return null;

    String? resolvedPublicKeyBase64 = publicKeyBase64?.trim();

    if (resolvedPublicKeyBase64 != null && resolvedPublicKeyBase64.isNotEmpty) {
      final publicKeyBytes = _decodeBase64OrNull(resolvedPublicKeyBase64);
      if (publicKeyBytes == null ||
          !_isMatchingKeyPair(
            publicKey: publicKeyBytes,
            secretKeyBytes: secretKeyBytes,
          )) {
        resolvedPublicKeyBase64 = null;
      }
    } else {
      resolvedPublicKeyBase64 = null;
    }

    resolvedPublicKeyBase64 ??= await _recoverPublicKeyForSecret(
      uid: uid,
      secretKeyBytes: secretKeyBytes,
    );
    if (resolvedPublicKeyBase64 == null || resolvedPublicKeyBase64.isEmpty) {
      return null;
    }

    final recoveredPublicBytes = _decodeBase64OrNull(resolvedPublicKeyBase64);
    if (recoveredPublicBytes == null ||
        !_isMatchingKeyPair(
          publicKey: recoveredPublicBytes,
          secretKeyBytes: secretKeyBytes,
        )) {
      return null;
    }

    return _ResolvedKeyMaterial(
      privateKeyBase64: base64.encode(secretKeyBytes),
      publicKeyBase64: resolvedPublicKeyBase64,
    );
  }

  Future<String?> _fetchLegacyPublicKey(String uid) async {
    try {
      final serverDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final value = serverDoc.data()?['publicKey'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    } catch (_) {}

    try {
      final cacheDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      final value = cacheDoc.data()?['publicKey'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    } catch (_) {}

    return null;
  }

  Future<_ResolvedKeyMaterial?> _loadAccountKeyBackup({
    required String uid,
  }) async {
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc(_accountKeyBackupDocId);

    Map<String, dynamic>? data;

    try {
      final server = await ref.get(const GetOptions(source: Source.server));
      data = server.data();
    } catch (_) {}

    if (data == null) {
      try {
        final cache = await ref.get(const GetOptions(source: Source.cache));
        data = cache.data();
      } catch (_) {}
    }

    if (data == null) return null;

    final privateKey = data['privateKey'];
    final publicKey = data['publicKey'];
    if (privateKey is! String || publicKey is! String) {
      return null;
    }

    final privateBytes = _decodeBase64OrNull(privateKey);
    final publicBytes = _decodeBase64OrNull(publicKey);
    if (privateBytes == null || publicBytes == null) {
      return null;
    }

    if (!_isMatchingKeyPair(
      publicKey: publicBytes,
      secretKeyBytes: privateBytes,
    )) {
      return null;
    }

    return _ResolvedKeyMaterial(
      privateKeyBase64: base64.encode(privateBytes),
      publicKeyBase64: base64.encode(publicBytes),
    );
  }

  Future<void> _saveAccountKeyBackup({
    required String uid,
    required _ResolvedKeyMaterial material,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc(_accountKeyBackupDocId)
          .set({
            'privateKey': material.privateKeyBase64,
            'publicKey': material.publicKeyBase64,
            'version': 1,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Backup sync is best-effort; local keypair remains the source of truth.
    }
  }

  Uint8List? _decodeBase64OrNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      return Uint8List.fromList(base64.decode(value.trim()));
    } catch (_) {
      return null;
    }
  }

  bool _isMatchingKeyPair({
    required Uint8List publicKey,
    required Uint8List secretKeyBytes,
  }) {
    try {
      final probe = Uint8List.fromList(const [1, 2, 3, 4]);
      final nonce = _sodium.randombytes.buf(_sodium.crypto.box.nonceBytes);
      final secretKey = SecureKey.fromList(_sodium, secretKeyBytes);
      final peerKeyPair = _sodium.crypto.box.keyPair();

      try {
        final cipher = _sodium.crypto.box.easy(
          message: probe,
          nonce: nonce,
          publicKey: publicKey,
          secretKey: peerKeyPair.secretKey,
        );
        final opened = _sodium.crypto.box.openEasy(
          cipherText: cipher,
          nonce: nonce,
          publicKey: peerKeyPair.publicKey,
          secretKey: secretKey,
        );
        return _listEquals(probe, opened);
      } finally {
        secretKey.dispose();
        peerKeyPair.secretKey.dispose();
      }
    } catch (_) {
      return false;
    }
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _fetchUserDataForRecovery(String uid) async {
    try {
      final serverDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final data = serverDoc.data();
      if (data != null) return data;
    } catch (_) {}

    try {
      final cacheDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      return cacheDoc.data() ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<String?> _recoverPublicKeyForSecret({
    required String uid,
    required Uint8List secretKeyBytes,
  }) async {
    final data = await _fetchUserDataForRecovery(uid);
    if (data.isEmpty) return null;

    final candidates = <String>[];

    void addCandidate(String? value) {
      if (value == null) return;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (!candidates.contains(trimmed)) {
        candidates.add(trimmed);
      }
    }

    final devices = data['devices'];
    final device = await _deviceInfo.getDeviceInfo();
    final currentDeviceId = device['deviceId'] ?? '';
    if (currentDeviceId.isNotEmpty && devices is Map) {
      final currentEntry = devices[currentDeviceId];
      if (currentEntry is Map && currentEntry['publicKey'] is String) {
        addCandidate(currentEntry['publicKey'] as String?);
      }
    }

    addCandidate(data['publicKey'] as String?);

    void walk(dynamic node) {
      if (node is! Map) return;
      for (final value in node.values) {
        if (value is Map && value['publicKey'] is String) {
          addCandidate(value['publicKey'] as String?);
        }
        walk(value);
      }
    }

    walk(devices);

    for (final candidate in candidates) {
      final publicKeyBytes = _decodeBase64OrNull(candidate);
      if (publicKeyBytes == null) continue;
      if (_isMatchingKeyPair(
        publicKey: publicKeyBytes,
        secretKeyBytes: secretKeyBytes,
      )) {
        return candidate;
      }
    }

    return null;
  }

  Future<void> _syncDevicePublicKey(String publicKeyBase64) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final device = await _deviceInfo.getDeviceInfo();
    final deviceId = device['deviceId'] ?? 'unknown';

    await _firestore.collection('users').doc(user.uid).set({
      'devices.$deviceId.publicKey': publicKeyBase64,
      'devices.$deviceId.publicKeyUpdatedAt': FieldValue.serverTimestamp(),
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

    final recipientDoc = await _firestore
        .collection('users')
        .doc(recipientUserId)
        .get();

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

    final senderDoc = await _firestore
        .collection('users')
        .doc(senderUserId)
        .get();

    final senderPublicKeyBase64 = senderDoc.data()?['publicKey'] as String?;

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

    final recipientPublicKey = Uint8List.fromList(
      base64.decode(recipientPublicKeyBase64),
    );

    final nonce = _sodium.randombytes.buf(_sodium.crypto.box.nonceBytes);

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

    final senderPublicKey = Uint8List.fromList(
      base64.decode(senderPublicKeyBase64),
    );

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

class _ResolvedKeyMaterial {
  final String privateKeyBase64;
  final String publicKeyBase64;

  const _ResolvedKeyMaterial({
    required this.privateKeyBase64,
    required this.publicKeyBase64,
  });
}
