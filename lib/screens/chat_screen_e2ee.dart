import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/notification_service.dart';
import '../services/presence_service.dart';
import '../services/chat_service_e2ee.dart';
import 'user_profile_view_screen.dart';
import 'dart:async';

/// E2EE-enabled chat screen
/// 
/// All messages are encrypted before sending and decrypted on display.
/// Firestore never sees plaintext.
class ChatScreenE2EE extends StatefulWidget {
  final String recipientId;
  final String recipientName;

  const ChatScreenE2EE({
    super.key,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  State<ChatScreenE2EE> createState() => _ChatScreenE2EEState();
}

class _ChatScreenE2EEState extends State<ChatScreenE2EE> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  final NotificationService _notificationService = NotificationService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  String? _conversationId;
  Map<String, dynamic>? _recipientData;
  bool _isInitializing = true;
  String? _initError;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addObserver(this);
    _notificationService.setActiveChat(widget.recipientId);
    
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Initialize encryption
      await _chatService.initializeEncryption();
      
      // Check if recipient has encryption enabled
      final hasEncryption = await _chatService.userHasEncryption(widget.recipientId);
      if (!hasEncryption) {
        setState(() {
          _initError = 'Recipient does not have E2EE enabled';
          _isInitializing = false;
        });
        return;
      }

      // Initialize conversation
      _conversationId = await _chatService.initializeConversation(widget.recipientId);
      
      // Listen to recipient data
      _listenToRecipientData();
      
      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _initError = e.toString();
        _isInitializing = false;
      });
    }
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

  void _listenToRecipientData() {
    _firestore.collection('users').doc(widget.recipientId).snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _recipientData = snapshot.data()!;
        });
      }
    });
  }

  Future<void> _sendMessage() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || _conversationId == null) return;

    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    try {
      _messageController.clear();

      // Send encrypted message
      await _chatService.sendMessage(
        conversationId: _conversationId!,
        messageText: messageText,
        recipientId: widget.recipientId,
      );

      // Send push notification (generic - no content)
      try {
        final senderName = currentUser.displayName ?? 'Someone';
        await _notificationService.sendMessageNotification(
          recipientId: widget.recipientId,
          senderName: senderName,
          messageText: 'Sent an encrypted message', // Generic text
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
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.recipientName)),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('🔐 Initializing encryption...'),
            ],
          ),
        ),
      );
    }

    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.recipientName)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Encryption Error', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _initError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
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
                    backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
                    child: photoUrl == null ? const Icon(Icons.person) : null,
                  ),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.lock, size: 14, color: Colors.green),
                      ],
                    ),
                    _LiveStatusWidget(userId: widget.recipientId),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
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
          // E2EE indicator banner
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            color: Colors.green.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.lock, size: 14, color: Colors.green),
                SizedBox(width: 6),
                Text(
                  'End-to-end encrypted',
                  style: TextStyle(fontSize: 12, color: Colors.green),
                ),
              ],
            ),
          ),
          Expanded(
            child: _MessagesList(
              conversationId: _conversationId,
              recipientName: widget.recipientName,
              scrollController: _scrollController,
              chatService: _chatService,
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
        content: const Text('Delete all encrypted messages? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _chatService.clearChat(_conversationId!);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// Messages list with decryption
class _MessagesList extends StatefulWidget {
  final String? conversationId;
  final String recipientName;
  final ScrollController scrollController;
  final ChatService chatService;

  const _MessagesList({
    required this.conversationId,
    required this.recipientName,
    required this.scrollController,
    required this.chatService,
  });

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> with AutomaticKeepAliveClientMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Error loading messages'));
    }

    if (widget.conversationId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: widget.chatService.getMessages(widget.conversationId!),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, size: 64, color: Colors.green),
                const SizedBox(height: 16),
                const Text(
                  'Encrypted chat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Messages are end-to-end encrypted.\nOnly you and ${widget.recipientName} can read them.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final messages = snapshot.data!.docs;

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final messageDoc = messages[index];
            final message = messageDoc.data() as Map<String, dynamic>;
            final isMe = message['senderId'] == currentUser.uid;
            final timestamp = message['timestamp'] as Timestamp?;

            return FutureBuilder<String>(
              future: widget.chatService.decryptMessage(messageData: message),
              builder: (context, decryptSnapshot) {
                String displayText;
                
                if (decryptSnapshot.connectionState == ConnectionState.waiting) {
                  displayText = '🔓 Decrypting...';
                } else if (decryptSnapshot.hasError) {
                  displayText = '❌ Decryption failed';
                } else {
                  displayText = decryptSnapshot.data ?? '[Empty]';
                }

                return _buildMessageBubble(
                  displayText,
                  isMe,
                  timestamp,
                  isDecrypting: decryptSnapshot.connectionState == ConnectionState.waiting,
                  key: ValueKey(messageDoc.id),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(
    String text,
    bool isMe,
    Timestamp? timestamp, {
    required bool isDecrypting,
    Key? key,
  }) {
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
            isDecrypting
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isMe ? Colors.white : Colors.black54,
                    ),
                  )
                : Text(
                    text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
            if (timestamp != null && !isDecrypting) ...[
              const SizedBox(height: 4),
              Text(
                DateFormat('HH:mm').format(timestamp.toDate()),
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
}

class _LiveStatusWidget extends StatefulWidget {
  final String userId;
  const _LiveStatusWidget({required this.userId});

  @override
  State<_LiveStatusWidget> createState() => _LiveStatusWidgetState();
}

class _LiveStatusWidgetState extends State<_LiveStatusWidget> {
  Timer? _tick;

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
        if (!snapshot.hasData) {
          return const Text(
            'Loading...',
            style: TextStyle(fontSize: 12),
          );
        }

        final statusText = PresenceService.getStatusText(snapshot.data);

        return Text(
          statusText,
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}