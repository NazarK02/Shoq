import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'crypto_service.dart';

/// Chat service with end-to-end encryption
/// 
/// All messages are encrypted before being sent to Firestore.
/// Firestore only stores:
/// - Encrypted ciphertext
/// - Sender ID (for routing)
/// - Timestamp (for ordering)
/// - Read status (no plaintext content)
class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CryptoService _crypto = CryptoService();

  User? get currentUser => _auth.currentUser;

  /// Initialize encryption before using chat
  Future<void> initializeEncryption() async {
    await _crypto.initialize();
  }

  /// Generate conversation ID for direct messages
  String getDirectConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return 'direct_${sortedIds.join('_')}';
  }

  /// Initialize or get existing conversation
  Future<String?> initializeConversation(String recipientId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return null;

    final conversationId = getDirectConversationId(currentUser.uid, recipientId);
    
    final conversationDoc = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .get();

    if (!conversationDoc.exists) {
      await _firestore.collection('conversations').doc(conversationId).set({
        'type': 'direct',
        'participants': [currentUser.uid, recipientId],
        'createdBy': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '🔒 Encrypted message', // Generic placeholder
        'lastMessageTime': null,
        'encrypted': true, // Mark as E2EE conversation
      });
    }

    return conversationId;
  }

  /// Send an encrypted message
  /// 
  /// Process:
  /// 1. Encrypt plaintext with recipient's public key
  /// 2. Store only ciphertext in Firestore
  /// 3. Update conversation metadata (generic text only)
  Future<void> sendMessage({
    required String conversationId,
    required String messageText,
    required String recipientId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('User not logged in');

    if (messageText.trim().isEmpty) return;

    if (!_crypto.isEncryptionEnabled) {
      throw Exception('Encryption not initialized. Call initializeEncryption() first.');
    }

    print('📤 Sending encrypted message...');

    try {
      // Encrypt the message
      final ciphertext = await _crypto.encryptMessage(
        plaintext: messageText,
        recipientUserId: recipientId,
      );

      // Store encrypted message
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'ciphertext': ciphertext, // ← Only encrypted data stored
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'encrypted': true,
      });

      // Update conversation metadata (no actual content exposed)
      await _firestore.collection('conversations').doc(conversationId).update({
        'lastMessage': '🔒 Encrypted message',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': currentUser.uid,
      });

      print('✅ Encrypted message sent successfully');
    } catch (e) {
      print('❌ Failed to send encrypted message: $e');
      rethrow;
    }
  }

  /// Get messages stream (returns encrypted messages)
  Stream<QuerySnapshot> getMessages(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  /// Decrypt a single message
  /// 
  /// Call this for each message when rendering in UI
  Future<String> decryptMessage({
    required Map<String, dynamic> messageData,
  }) async {
    if (!_crypto.isEncryptionEnabled) {
      return '[Encryption not initialized]';
    }

    try {
      // Check if message is encrypted
      if (messageData['encrypted'] != true) {
        // Legacy plaintext message (from before E2EE was enabled)
        return messageData['text'] ?? '[Empty message]';
      }

      final ciphertext = messageData['ciphertext'] as String?;
      if (ciphertext == null) {
        return '[Missing ciphertext]';
      }

      final senderId = messageData['senderId'] as String?;
      if (senderId == null) {
        return '[Unknown sender]';
      }

      // Decrypt
      final plaintext = await _crypto.decryptMessage(
        ciphertextBase64: ciphertext,
        senderUserId: senderId,
      );

      return plaintext;
    } catch (e) {
      print('❌ Decryption failed: $e');
      return '[Failed to decrypt: ${e.toString()}]';
    }
  }

  /// Get conversation stream
  Stream<DocumentSnapshot> getConversation(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .snapshots();
  }

  /// Clear all messages in a conversation (deletes encrypted data)
  Future<void> clearChat(String conversationId) async {
    final messages = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();

    final batch = _firestore.batch();
    for (var doc in messages.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    await _firestore.collection('conversations').doc(conversationId).update({
      'lastMessage': null,
      'lastMessageTime': null,
    });
  }

  /// Delete a specific message
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String otherUserId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final unreadMessages = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .where('senderId', isEqualTo: otherUserId)
        .where('read', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (var doc in unreadMessages.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  /// Get user conversations
  Stream<QuerySnapshot> getUserConversations() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots();
  }

  /// Get user data
  Future<DocumentSnapshot> getUserData(String userId) {
    return _firestore.collection('users').doc(userId).get();
  }

  /// Check if user has encryption enabled
  Future<bool> userHasEncryption(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    return userDoc.data()?['publicKey'] != null;
  }

  /// Note: Edit and reactions removed for E2EE version
  /// Editing encrypted messages is complex (requires re-encryption)
  /// Reactions would need separate encryption handling
  /// These can be added later with proper E2EE implementation
}
