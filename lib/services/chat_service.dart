import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Generate conversation ID for direct messages
  String getDirectConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return 'direct_${sortedIds.join('_')}';
  }

  // Initialize or get existing conversation
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
        'lastMessage': null,
        'lastMessageTime': null,
      });
    }

    return conversationId;
  }

  // Send a message
  Future<void> sendMessage({
    required String conversationId,
    required String messageText,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('User not logged in');

    if (messageText.trim().isEmpty) return;

    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .add({
      'senderId': currentUser.uid,
      'text': messageText,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });

    await _firestore.collection('conversations').doc(conversationId).update({
      'lastMessage': messageText,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': currentUser.uid,
    });
  }

  // Get messages stream
  Stream<QuerySnapshot> getMessages(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // Get conversation stream
  Stream<DocumentSnapshot> getConversation(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .snapshots();
  }

  // Clear all messages in a conversation
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

  // Delete a specific message
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

  // Mark messages as read
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

  // Get user conversations
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

  // Get user data
  Future<DocumentSnapshot> getUserData(String userId) {
    return _firestore.collection('users').doc(userId).get();
  }

  // Edit a message
  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String newText,
  }) async {
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'text': newText,
      'edited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  // React to a message
  Future<void> addReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'reactions.${currentUser.uid}': emoji,
    });
  }

  // Remove reaction
  Future<void> removeReaction({
    required String conversationId,
    required String messageId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'reactions.${currentUser.uid}': FieldValue.delete(),
    });
  }
}