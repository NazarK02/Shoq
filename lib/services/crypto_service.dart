import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';
import 'package:sodium_libs/sodium_libs.dart' as sodium_libs;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late Sodium _sodium;
  KeyPair? _keyPair;
  bool _initialized = false;

  /// Initialize libsodium + load/generate keys
  Future<void> initialize() async {
    if (_initialized) return;

    _sodium = await sodium_libs.SodiumInit.init();

    await _loadOrCreateKeyPair();
    _initialized = true;
  }

  /// Load or generate keypair
  Future<void> _loadOrCreateKeyPair() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final storedPrivateKey =
        await _secureStorage.read(key: 'crypto_private_key');

    if (storedPrivateKey != null) {
      final secretKeyBytes = base64.decode(storedPrivateKey);
      final secretKey = SecureKey.fromList(_sodium, secretKeyBytes);

      // Try to load the public key from Firestore (should have been
      // written when the keypair was first created). If it's missing,
      // attempt to derive a keypair from the seed when possible. If all
      // else fails, generate a fresh keypair and store it.
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final storedPublicKeyBase64 = userDoc.data()?['publicKey'] as String?;

      if (storedPublicKeyBase64 != null) {
        final publicKey = Uint8List.fromList(base64.decode(storedPublicKeyBase64));
        _keyPair = KeyPair(publicKey: publicKey, secretKey: secretKey);
      } else {
        try {
          if (secretKey.length == _sodium.crypto.box.seedBytes) {
            // Secret was actually a seed - derive the keypair from it.
            _keyPair = _sodium.crypto.box.seedKeyPair(secretKey);
          } else {
            // Fallback: generate a new keypair and replace stored keys.
            _keyPair = _sodium.crypto.box.keyPair();

            await _secureStorage.write(
              key: 'crypto_private_key',
              value: base64.encode(_keyPair!.secretKey.extractBytes()),
            );

            await _firestore.collection('users').doc(user.uid).update({
              'publicKey': base64.encode(_keyPair!.publicKey),
              'publicKeyUpdatedAt': FieldValue.serverTimestamp(),
            });
          }
        } catch (_) {
          // If deriving failed for any reason, generate a fresh keypair.
          _keyPair = _sodium.crypto.box.keyPair();

          await _secureStorage.write(
            key: 'crypto_private_key',
            value: base64.encode(_keyPair!.secretKey.extractBytes()),
          );

          await _firestore.collection('users').doc(user.uid).update({
            'publicKey': base64.encode(_keyPair!.publicKey),
            'publicKeyUpdatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } else {
      _keyPair = _sodium.crypto.box.keyPair();

      await _secureStorage.write(
        key: 'crypto_private_key',
        value: base64.encode(_keyPair!.secretKey.extractBytes()),
      );

      await _firestore.collection('users').doc(user.uid).update({
        'publicKey': base64.encode(_keyPair!.publicKey),
        'publicKeyUpdatedAt': FieldValue.serverTimestamp(),
      });
    }
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
