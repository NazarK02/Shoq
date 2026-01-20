import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'encryption_service.dart';

class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Create a direct conversation (1-on-1)
  Future<String> createDirectConversation(String otherUserId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    // Create conversation ID (consistent order)
    final conversationId = _getDirectConversationId(currentUser.uid, otherUserId);

    // Check if conversation already exists
    final existing = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .get();
    
    if (existing.exists) {
      return conversationId;
    }

    // Generate conversation encryption key
    final conversationKey = EncryptionService.generateConversationKey();

    // Create conversation
    await _firestore.collection('conversations').doc(conversationId).set({
      'type': 'direct',
      'participants': [currentUser.uid, otherUserId],
      'createdBy': currentUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
      'encryptionKeys': {
        currentUser.uid: conversationKey, // In production, encrypt with user's public key
        otherUserId: conversationKey,
      },
    });

    return conversationId;
  }

  /// Create a group conversation
  Future<String> createGroupConversation({
    required String groupName,
    required List<String> participantIds,
    String? groupIcon,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    // Add current user to participants
    if (!participantIds.contains(currentUser.uid)) {
      participantIds.add(currentUser.uid);
    }

    // Generate conversation ID
    final conversationId = 'group_${DateTime.now().millisecondsSinceEpoch}';

    // Generate conversation encryption key
    final conversationKey = EncryptionService.generateConversationKey();

    // Create encryption keys for all participants
    final encryptionKeys = <String, String>{};
    for (var userId in participantIds) {
      encryptionKeys[userId] = conversationKey; // In production, encrypt with each user's public key
    }

    // Create group
    await _firestore.collection('conversations').doc(conversationId).set({
      'type': 'group',
      'name': groupName,
      'groupIcon': groupIcon,
      'participants': participantIds,
      'admin': [currentUser.uid],
      'createdBy': currentUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
      'encryptionKeys': encryptionKeys,
    });

    return conversationId;
  }

  /// Send a message (works for both direct and group chats)
  Future<void> sendMessage({
    required String conversationId,
    required String messageText,
    String type = 'text',
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Not logged in');

    // Get conversation to retrieve encryption key
    final conversation = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .get();

    if (!conversation.exists) {
      throw Exception('Conversation not found');
    }

    final conversationData = conversation.data()!;
    final encryptionKeys = conversationData['encryptionKeys'] as Map<String, dynamic>;
    final conversationKey = encryptionKeys[currentUser.uid] as String;

    // Encrypt the message
    final encryptedText = EncryptionService.encryptMessage(
      messageText,
      conversationKey,
    );

    // Send message
    await _firestore
        .collection('messages')
        .doc(conversationId)
        .collection('messages')
        .add({
      'senderId': currentUser.uid,
      'senderName': currentUser.displayName ?? 'User',
      'text': encryptedText,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'isEncrypted': true,
      'readBy': {currentUser.uid: FieldValue.serverTimestamp()},
      'reactions': {},
    });

    // Update conversation last message
    await _firestore.collection('conversations').doc(conversationId).update({
      'lastMessage': {
        'text': 'Encrypted message',
        'senderId': currentUser.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'isEncrypted': true,
      },
    });
  }

  /// Get messages stream (automatically decrypts)
  Stream<List<Message>> getMessages(String conversationId) async* {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      yield [];
      return;
    }

    // Get conversation key
    final conversation = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .get();

    if (!conversation.exists) {
      yield [];
      return;
    }

    final conversationData = conversation.data()!;
    final encryptionKeys = conversationData['encryptionKeys'] as Map<String, dynamic>;
    final conversationKey = encryptionKeys[currentUser.uid] as String?;

    if (conversationKey == null) {
      yield [];
      return;
    }

    yield* _firestore
        .collection('messages')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();

        // Decrypt the message
        final decryptedText = data['isEncrypted'] == true
            ? EncryptionService.decryptMessage(
                data['text'],
                conversationKey,
              )
            : data['text'];

        return Message(
          id: doc.id,
          text: decryptedText,
          senderId: data['senderId'],
          senderName: data['senderName'] ?? 'User',
          timestamp: data['timestamp'],
          isMe: data['senderId'] == currentUser.uid,
          type: data['type'] ?? 'text',
          readBy: Map<String, Timestamp>.from(data['readBy'] ?? {}),
          reactions: Map<String, String>.from(data['reactions'] ?? {}),
        );
      }).toList();
    });
  }

  /// Get list of conversations
  Stream<List<ConversationPreview>> getConversations() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);

    return _firestore
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots()
        .map((snapshot) {
      final conversations = snapshot.docs.map((doc) {
        final data = doc.data();
        
        return ConversationPreview(
          id: doc.id,
          type: data['type'] ?? 'direct',
          name: data['name'],
          groupIcon: data['groupIcon'],
          participants: List<String>.from(data['participants']),
          lastMessage: data['lastMessage'] != null
              ? LastMessage(
                  text: data['lastMessage']['text'],
                  senderId: data['lastMessage']['senderId'],
                  timestamp: data['lastMessage']['timestamp'],
                )
              : null,
        );
      }).toList();

      // Sort by last message time
      conversations.sort((a, b) {
        if (a.lastMessage == null && b.lastMessage == null) return 0;
        if (a.lastMessage == null) return 1;
        if (b.lastMessage == null) return -1;
        return b.lastMessage!.timestamp.compareTo(a.lastMessage!.timestamp);
      });

      return conversations;
    });
  }

  /// Mark message as read
  Future<void> markAsRead(String conversationId, String messageId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    await _firestore
        .collection('messages')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'readBy.${currentUser.uid}': FieldValue.serverTimestamp(),
    });
  }

  /// Add reaction to message
  Future<void> addReaction(String conversationId, String messageId, String emoji) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    await _firestore
        .collection('messages')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'reactions.${currentUser.uid}': emoji,
    });
  }

  /// Generate consistent conversation ID for direct chats
  String _getDirectConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return 'direct_${sortedIds.join('_')}';
  }
}

// Data Models
class Message {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final Timestamp? timestamp;
  final bool isMe;
  final String type;
  final Map<String, Timestamp> readBy;
  final Map<String, String> reactions;

  Message({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.timestamp,
    required this.isMe,
    required this.type,
    required this.readBy,
    required this.reactions,
  });
}

class ConversationPreview {
  final String id;
  final String type;
  final String? name;
  final String? groupIcon;
  final List<String> participants;
  final LastMessage? lastMessage;

  ConversationPreview({
    required this.id,
    required this.type,
    this.name,
    this.groupIcon,
    required this.participants,
    this.lastMessage,
  });
}

class LastMessage {
  final String text;
  final String senderId;
  final Timestamp timestamp;

  LastMessage({
    required this.text,
    required this.senderId,
    required this.timestamp,
  });
}