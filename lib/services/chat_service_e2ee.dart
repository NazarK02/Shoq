import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'crypto_service.dart';

class ChatFileUpload {
  final String messageId;
  final String storagePath;
  final UploadTask task;
  final String contentType;

  ChatFileUpload({
    required this.messageId,
    required this.storagePath,
    required this.task,
    required this.contentType,
  });
}

/// Chat service with end-to-end encryption
/// 
/// All messages are encrypted before being sent to Firestore.
/// Automatically initializes E2EE for both users when needed.
class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final CryptoService _crypto = CryptoService();

  User? get currentUser => _auth.currentUser;
  bool get isEncryptionReady => _crypto.isEncryptionEnabled;

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
  /// Also ensures both users have E2EE enabled
  Future<String?> initializeConversation(String recipientId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return null;

    // Ensure current user has E2EE
    await _ensureUserHasE2EE(currentUser.uid);
    
    // Ensure recipient has E2EE
    await _ensureUserHasE2EE(recipientId);

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
        'lastMessage': null,
        'lastMessageTime': null,
        'encrypted': true,
        'hasMessages': false, // Track if conversation has any messages
      });
    }

    return conversationId;
  }

  /// Ensure a user has E2EE keys (initialize if needed)
  Future<void> _ensureUserHasE2EE(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final hasPublicKey = userDoc.data()?['publicKey'] != null;

    if (!hasPublicKey) {
      print('⚠️  User $userId missing E2EE keys, initializing...');
      
      // If it's the current user, we can initialize
      if (userId == _auth.currentUser?.uid) {
        await _crypto.initialize();
        final publicKey = _crypto.myPublicKeyBase64;
        
        if (publicKey != null) {
          await _firestore.collection('users').doc(userId).update({
            'publicKey': publicKey,
            'publicKeyUpdatedAt': FieldValue.serverTimestamp(),
          });
          print('✅ E2EE initialized for current user');
        }
      } else {
        print('⚠️  Cannot initialize E2EE for other user, they must login first');
      }
    }
  }

  /// Send an encrypted message
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
      // Ensure recipient has E2EE before sending
      await _ensureUserHasE2EE(recipientId);

      // Encrypt the message
      final ciphertext = await _crypto.encryptMessage(
        plaintext: messageText,
        recipientUserId: recipientId,
      );
      // Encrypt a copy for the sender so they can decrypt their own messages
      final senderCiphertext = await _crypto.encryptMessage(
        plaintext: messageText,
        recipientUserId: currentUser.uid,
      );

      // Get first 50 chars of plaintext for preview (will be shown as encrypted in UI)
      final preview = messageText.length > 50 
          ? '${messageText.substring(0, 50)}...' 
          : messageText;

      // Store encrypted message
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'ciphertext': ciphertext,
        'senderCiphertext': senderCiphertext,
        'timestamp': FieldValue.serverTimestamp(),
        'clientTimestamp': Timestamp.now(),
        'read': false,
        'encrypted': true,
        'type': 'text',
      });

      // Update conversation metadata with plaintext preview for UI
      await _firestore.collection('conversations').doc(conversationId).update({
        'lastMessage': preview, // Store plaintext preview
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': currentUser.uid,
        'hasMessages': true,
      });

      print('✅ Encrypted message sent successfully');
    } catch (e) {
      print('❌ Failed to send encrypted message: $e');
      rethrow;
    }
  }

  /// Send a file message (non-encrypted file contents).
  Future<void> sendFileMessage({
    required String conversationId,
    required String recipientId,
    required String filePath,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    final upload = startFileUpload(
      conversationId: conversationId,
      filePath: filePath,
      fileName: fileName,
      mimeType: mimeType,
    );

    await upload.task;

    await commitFileMessage(
      conversationId: conversationId,
      messageId: upload.messageId,
      storagePath: upload.storagePath,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: upload.contentType,
    );
  }

  ChatFileUpload startFileUpload({
    required String conversationId,
    required String filePath,
    required String fileName,
    String? mimeType,
  }) {
    if (filePath.trim().isEmpty) {
      throw Exception('Invalid file path');
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('File not found');
    }

    final displayName = fileName.trim().isEmpty ? 'file' : fileName.trim();
    final safeName = displayName.replaceAll(RegExp(r'[\\\\/]+'), '_');
    final messageId = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc()
        .id;
    final storagePath = 'chat_files/$conversationId/${messageId}_$safeName';
    final ref = _storage.ref().child(storagePath);

    final contentType = (mimeType == null || mimeType.trim().isEmpty)
        ? 'application/octet-stream'
        : mimeType.trim();

    final task = ref.putFile(
      file,
      SettableMetadata(contentType: contentType),
    );

    return ChatFileUpload(
      messageId: messageId,
      storagePath: storagePath,
      task: task,
      contentType: contentType,
    );
  }

  Future<void> commitFileMessage({
    required String conversationId,
    required String messageId,
    required String storagePath,
    String? downloadUrl,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('User not logged in');

    final displayName = fileName.trim().isEmpty ? 'file' : fileName.trim();
    final contentType = (mimeType == null || mimeType.trim().isEmpty)
        ? 'application/octet-stream'
        : mimeType.trim();

    final payload = <String, dynamic>{
      'senderId': currentUser.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'clientTimestamp': Timestamp.now(),
      'read': false,
      'encrypted': false,
      'type': 'file',
      'fileName': displayName,
      'fileSize': fileSize,
      'mimeType': contentType,
      'storagePath': storagePath,
    };

    if (downloadUrl != null && downloadUrl.trim().isNotEmpty) {
      payload['fileUrl'] = downloadUrl.trim();
    }

    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .set(payload);

    await _firestore.collection('conversations').doc(conversationId).update({
      'lastMessage': 'File: $displayName',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': currentUser.uid,
      'hasMessages': true,
    });
  }

  /// Get messages stream (returns encrypted messages)
  Stream<QuerySnapshot> getMessages(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('clientTimestamp', descending: false)
        .snapshots();
  }

  /// Decrypt a single message
  Future<String> decryptMessage({
    required Map<String, dynamic> messageData,
  }) async {
    if (!_crypto.isEncryptionEnabled) {
      return '';
    }

    try {
      // Check if message is encrypted
      if (messageData['encrypted'] != true) {
        return messageData['text'] ?? '';
      }

      final senderId = messageData['senderId'] as String?;
      if (senderId == null) {
        return '';
      }

      final currentUserId = _auth.currentUser?.uid;
      String? ciphertext;
      if (currentUserId != null && senderId == currentUserId) {
        // For my own messages, use the self-encrypted copy if available.
        ciphertext = messageData['senderCiphertext'] as String?;
        if (ciphertext == null) {
          // Legacy messages (before senderCiphertext) can't be decrypted by sender.
          return '[Sent]';
        }
      } else {
        ciphertext = messageData['ciphertext'] as String?;
      }

      if (ciphertext == null) {
        return '';
      }

      // Decrypt
      final plaintext = await _crypto.decryptMessage(
        ciphertextBase64: ciphertext,
        senderUserId: senderId,
      );

      return plaintext;
    } catch (e) {
      print('❌ Decryption failed: $e');
      return '';
    }
  }

  /// Get conversation stream
  Stream<DocumentSnapshot> getConversation(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .snapshots();
  }

  /// Clear all messages in a conversation
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
      'hasMessages': false,
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
}
