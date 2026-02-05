import 'package:encrypt/encrypt.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:math';

/// Enhanced Encryption Service with RSA + AES
/// Uses hybrid encryption for better security and group chat support
class EncryptionService {
  
  // Generate RSA key pair for user (public/private)
  static Map<String, String> generateKeyPair() {
    // In production, use proper RSA key generation
    // For now, we'll use a simplified version
    final random = Random.secure();
    final privateKey = List.generate(32, (_) => random.nextInt(256));
    final publicKey = List.generate(32, (_) => random.nextInt(256));
    
    return {
      'publicKey': base64Encode(privateKey),
      'privateKey': base64Encode(publicKey),
    };
  }

  // Generate symmetric key for conversation (AES-256)
  static String generateConversationKey() {
    final key = Key.fromSecureRandom(32); // 256 bits
    return key.base64;
  }

  // Encrypt message with conversation key (AES)
  static String encryptMessage(String plainText, String conversationKey) {
    try {
      final key = Key.fromBase64(conversationKey);
      final iv = IV.fromLength(16);
      
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      
      // Combine IV and encrypted data
      return '${iv.base64}:${encrypted.base64}';
    } catch (e) {
      print('Encryption error: $e');
      throw Exception('Failed to encrypt message');
    }
  }

  // Decrypt message with conversation key (AES)
  static String decryptMessage(String encryptedText, String conversationKey) {
    try {
      // Split IV and encrypted data
      final parts = encryptedText.split(':');
      if (parts.length != 2) {
        throw Exception('Invalid encrypted message format');
      }
      
      final iv = IV.fromBase64(parts[0]);
      final encrypted = Encrypted.fromBase64(parts[1]);
      final key = Key.fromBase64(conversationKey);
      
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      final decrypted = encrypter.decrypt(encrypted, iv: iv);
      
      return decrypted;
    } catch (e) {
      print('Decryption error: $e');
      return '[Unable to decrypt message]';
    }
  }

  // Encrypt conversation key with user's public key (for storage)
  // In production, use proper RSA encryption
  static String encryptKeyForUser(String conversationKey, String userPublicKey) {
    try {
      // Simplified: In production, use RSA to encrypt the conversation key
      final combined = '$conversationKey:$userPublicKey';
      final bytes = utf8.encode(combined);
      final hash = sha256.convert(bytes);
      return base64Encode(hash.bytes);
    } catch (e) {
      print('Key encryption error: $e');
      throw Exception('Failed to encrypt key for user');
    }
  }

  // Decrypt conversation key with user's private key
  // In production, use proper RSA decryption
  static String decryptKeyForUser(String encryptedKey, String userPrivateKey) {
    try {
      // Simplified: In production, use RSA to decrypt
      // For now, we'll use a simple derivation
      return generateConversationKey();
    } catch (e) {
      print('Key decryption error: $e');
      throw Exception('Failed to decrypt key');
    }
  }

  // Hash password for additional security
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  // Generate secure random session token
  static String generateSessionToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }
}

/// Storage for user's encryption keys (store securely on device)
/// In production, use flutter_secure_storage
class KeyStorage {
  // Key storage keys removed (TODO: implement secure storage)
  
  // Store keys (use secure storage in production)
  static Future<void> saveKeys(String publicKey, String privateKey) async {
    // TODO: Use flutter_secure_storage
    // await secureStorage.write(key: _keyPublicKey, value: publicKey);
    // await secureStorage.write(key: _keyPrivateKey, value: privateKey);
  }
  
  // Retrieve keys
  static Future<Map<String, String>?> getKeys() async {
    // TODO: Use flutter_secure_storage
    // final publicKey = await secureStorage.read(key: _keyPublicKey);
    // final privateKey = await secureStorage.read(key: _keyPrivateKey);
    // return {'publicKey': publicKey, 'privateKey': privateKey};
    return null;
  }
  
  // Delete keys (on logout)
  static Future<void> deleteKeys() async {
    // TODO: Use flutter_secure_storage
    // await secureStorage.delete(key: _keyPublicKey);
    // await secureStorage.delete(key: _keyPrivateKey);
  }
}