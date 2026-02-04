import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import 'user_profile_view_screen.dart';

class ChatScreen extends StatefulWidget {
  final String recipientId;
  final String recipientName;

  const ChatScreen({
    super.key,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _realtimeDb = FirebaseDatabase.instance;
  final NotificationService _notificationService = NotificationService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  String? _conversationId;
  bool _isLoading = true;
  bool _isRecipientOnline = false;
  DateTime? _recipientLastSeen;
  
  // Real-time user data
  Map<String, dynamic>? _recipientData;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addObserver(this);
    _notificationService.setActiveChat(widget.recipientId);
    
    _initializeConversation();
    _listenToRecipientStatus();
    _listenToRecipientData(); // NEW: Listen to profile changes
  }

  @override
  void dispose() {
    _notificationService.setActiveChat(null);
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _notificationService.setActiveChat(widget.recipientId);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _notificationService.setActiveChat(null);
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  // NEW: Listen to recipient's profile data in real-time
  void _listenToRecipientData() {
    _firestore.collection('users').doc(widget.recipientId).snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _recipientData = snapshot.data();
        });
      }
    });
  }

  // Listen to recipient's online status
  void _listenToRecipientStatus() {
    _realtimeDb.ref('status/${widget.recipientId}').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final state = data['state'] as String?;
        final lastSeenTimestamp = data['lastSeen'] as int?;

        if (mounted) {
          setState(() {
            _isRecipientOnline = state == 'online';
            if (lastSeenTimestamp != null) {
              _recipientLastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp);
            }
          });
        }
      }
    });
  }

  String _getStatusText() {
    if (_isRecipientOnline) {
      return 'Online';
    } else if (_recipientLastSeen != null) {
      final now = DateTime.now();
      final diff = now.difference(_recipientLastSeen!);

      if (diff.inMinutes < 1) {
        return 'Just now';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      } else if (diff.inDays == 1) {
        return 'Yesterday';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}d ago';
      } else {
        return DateFormat('MMM d').format(_recipientLastSeen!);
      }
    }
    return '';
  }

  Future<void> _initializeConversation() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _conversationId = _getDirectConversationId(currentUser.uid, widget.recipientId);
    
    final conversationDoc = await _firestore
        .collection('conversations')
        .doc(_conversationId)
        .get();

    if (!conversationDoc.exists) {
      await _firestore.collection('conversations').doc(_conversationId).set({
        'type': 'direct',
        'participants': [currentUser.uid, widget.recipientId],
        'createdBy': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageTime': null,
      });
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getDirectConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return 'direct_${sortedIds.join('_')}';
  }

  Future<void> _sendMessage() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || _conversationId == null) return;

    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    try {
      _messageController.clear();

      await _firestore
          .collection('conversations')
          .doc(_conversationId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'text': messageText,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      await _firestore.collection('conversations').doc(_conversationId).update({
        'lastMessage': messageText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': currentUser.uid,
      });

      try {
        final senderName = currentUser.displayName ?? 'Someone';
        await _notificationService.sendMessageNotification(
          recipientId: widget.recipientId,
          senderName: senderName,
          messageText: messageText,
        );
      } catch (notificationError) {
        print('Error sending notification: $notificationError');
      }

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: ${e.toString()}')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  // NEW: Navigate to user profile
  void _openUserProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileViewScreen(
          userId: widget.recipientId,
          userData: _recipientData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.recipientName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Use real-time data for display name and photo
    final displayName = _recipientData?['displayName'] ?? widget.recipientName;
    final photoUrl = _recipientData?['photoUrl'];

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _openUserProfile, // NEW: Tap to view profile
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? Text(displayName[0].toUpperCase())
                        : null,
                  ),
                  // Online indicator
                  if (_isRecipientOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _getStatusText(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: _isRecipientOnline ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video call feature coming soon')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voice call feature coming soon')),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') {
                _showClearChatDialog();
              } else if (value == 'profile') {
                _openUserProfile();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, size: 20),
                    SizedBox(width: 8),
                    Text('View Profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20),
                    SizedBox(width: 8),
                    Text('Clear chat'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _MessagesList(
              conversationId: _conversationId!,
              recipientName: displayName,
              scrollController: _scrollController,
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Attachments coming soon')),
                );
              },
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat'),
        content: const Text('Are you sure you want to delete all messages? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearChat();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearChat() async {
    if (_conversationId == null) return;

    try {
      final messages = await _firestore
          .collection('conversations')
          .doc(_conversationId)
          .collection('messages')
          .get();

      final batch = _firestore.batch();
      for (var doc in messages.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      await _firestore.collection('conversations').doc(_conversationId).update({
        'lastMessage': null,
        'lastMessageTime': null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing chat: ${e.toString()}')),
        );
      }
    }
  }
}

// Messages list widget
class _MessagesList extends StatefulWidget {
  final String conversationId;
  final String recipientName;
  final ScrollController scrollController;

  const _MessagesList({
    required this.conversationId,
    required this.recipientName,
    required this.scrollController,
  });

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> with AutomaticKeepAliveClientMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  bool get wantKeepAlive => true;

  void _scrollToBottom() {
    if (widget.scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (widget.scrollController.hasClients) {
          widget.scrollController.animateTo(
            widget.scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Error loading messages'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No messages yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Say hi to ${widget.recipientName}!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        final messages = snapshot.data!.docs;
        
        if (messages.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (widget.scrollController.hasClients && 
                widget.scrollController.position.pixels >= widget.scrollController.position.maxScrollExtent - 100) {
              _scrollToBottom();
            }
          });
        }

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final messageDoc = messages[index];
            final message = messageDoc.data() as Map<String, dynamic>;
            final isMe = message['senderId'] == currentUser.uid;
            final timestamp = message['timestamp'] as Timestamp?;

            return _buildMessageBubble(
              message['text'] ?? '',
              isMe,
              timestamp,
              key: ValueKey(messageDoc.id),
            );
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(String text, bool isMe, Timestamp? timestamp, {Key? key}) {
    return Align(
      key: key,
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? Theme.of(context).primaryColor : Colors.grey[300],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
            if (timestamp != null) ...[
              const SizedBox(height: 4),
              Text(
                _formatMessageTime(timestamp),
                style: TextStyle(
                  color: isMe ? Colors.white70 : Colors.black54,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatMessageTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return DateFormat('HH:mm').format(date);
    } else if (diff.inDays == 1) {
      return 'Yesterday ${DateFormat('HH:mm').format(date)}';
    } else if (diff.inDays < 7) {
      return DateFormat('EEE HH:mm').format(date);
    } else {
      return DateFormat('MMM d, HH:mm').format(date);
    }
  }
}