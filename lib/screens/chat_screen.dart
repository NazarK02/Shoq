import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../services/presence_service.dart';
import 'user_profile_view_screen.dart';
import 'dart:async';

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
  final NotificationService _notificationService = NotificationService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  String? _conversationId;
  bool _isLoading = true;
  
  // Real-time recipient data (name, photo, status updated live)
  Map<String, dynamic>? _recipientData;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addObserver(this);
    _notificationService.setActiveChat(widget.recipientId);
    
    _initializeConversation();
    _listenToRecipientData();
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

  // Listen to recipient's profile data in real-time
  void _listenToRecipientData() {
    _firestore.collection('users').doc(widget.recipientId).snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data()!;
        setState(() {
          _recipientData = data;
        });
      }
    });
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

      // Send push notification
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.recipientName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final displayName = _recipientData?['displayName'] ?? widget.recipientName;
    final photoUrl = _recipientData?['photoUrl'];

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfileViewScreen(
                  userId: widget.recipientId,
                  userData: _recipientData,
                ),
              ),
            );
          },
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null ? Icon(Icons.person) : null,
                  ),
                  // Online indicator dot (using _LiveStatusWidget's data)
                  StreamBuilder<Map<String, dynamic>?>(
                    stream: PresenceService().getUserStatusStream(widget.recipientId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();
                      final isOnline = PresenceService.isUserOnline(snapshot.data ?? {});
                      
                      if (!isOnline) return const SizedBox.shrink();
                      
                      return Positioned(
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
                      );
                    },
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
                    // Real-time status (self-refreshing)
                    _LiveStatusWidget(userId: widget.recipientId),
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
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear chat'),
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
              recipientName: widget.recipientName,
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

// Separate widget for messages list with AutomaticKeepAliveClientMixin
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin

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

        // Show loading spinner only during initial connection
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Show empty state only when actually empty
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

        // Build list with date dividers
        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final messageDoc = messages[index];
            final message = messageDoc.data() as Map<String, dynamic>;
            final isMe = message['senderId'] == currentUser.uid;
            final timestamp = message['timestamp'] as Timestamp?;

            // Check if we need a date divider
            final showDivider = _shouldShowDateDivider(messages, index);

            return Column(
              children: [
                if (showDivider)
                  _buildDateDivider(timestamp),
                _buildMessageBubble(
                  message['text'] ?? '',
                  isMe,
                  timestamp,
                  key: ValueKey(messageDoc.id),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Returns true if a date divider should be shown before this message
  bool _shouldShowDateDivider(List<QueryDocumentSnapshot> messages, int index) {
    if (index == 0) return true; // Always show divider for first message

    final currentMsg = messages[index].data() as Map<String, dynamic>;
    final prevMsg = messages[index - 1].data() as Map<String, dynamic>;

    final currentTimestamp = currentMsg['timestamp'] as Timestamp?;
    final prevTimestamp = prevMsg['timestamp'] as Timestamp?;

    if (currentTimestamp == null || prevTimestamp == null) return false;

    final currentDate = currentTimestamp.toDate();
    final prevDate = prevTimestamp.toDate();

    // Different day = show divider
    return currentDate.year != prevDate.year ||
           currentDate.month != prevDate.month ||
           currentDate.day != prevDate.day;
  }

  /// Build a date divider like "Today", "Yesterday", or "February 26, 2026"
  Widget _buildDateDivider(Timestamp? timestamp) {
    if (timestamp == null) return const SizedBox.shrink();

    final date = timestamp.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    String label;
    if (messageDate == today) {
      label = 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMMM d, y').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[400])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[400])),
        ],
      ),
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

/// A small stateful widget that listens to the user's Firestore doc AND
/// ticks every 30 seconds so that isUserOnline() (which compares
/// lastHeartbeat to DateTime.now()) is re-evaluated even when no new
/// Firestore snapshot arrives (i.e. the other user's app just died).
class _LiveStatusWidget extends StatefulWidget {
  final String userId;
  const _LiveStatusWidget({required this.userId});

  @override
  State<_LiveStatusWidget> createState() => _LiveStatusWidgetState();
}

class _LiveStatusWidgetState extends State<_LiveStatusWidget> {
  Timer? _tick;
  Map<String, dynamic>? _lastData;
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: PresenceService().getUserStatusStream(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _lastData = snapshot.data;
          _hasData = true;
        }

        if (!_hasData) {
          return const Text(
            'Loading...',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          );
        }

        final isOnline = PresenceService.isUserOnline(_lastData ?? {});
        final statusText = PresenceService.getStatusText(_lastData);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: isOnline ? Colors.green : Colors.grey[600],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}