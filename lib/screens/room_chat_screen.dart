import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service_e2ee.dart';
import '../services/user_cache_service.dart';

class RoomChatScreen extends StatefulWidget {
  final String conversationId;
  final String roomTitle;
  final String conversationType;
  final List<String> initialParticipants;

  const RoomChatScreen({
    super.key,
    required this.conversationId,
    required this.roomTitle,
    required this.conversationType,
    required this.initialParticipants,
  });

  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  final UserCacheService _userCache = UserCacheService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _conversationSub;
  List<String> _participants = [];
  String _title = '';
  bool _isInitializing = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = widget.roomTitle.trim().isEmpty ? 'Room' : widget.roomTitle.trim();
    _participants = widget.initialParticipants.toSet().toList();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _chatService.initializeEncryption();
      _startConversationListener();
      _warmParticipants(_participants);
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = 'Could not open chat room: $e';
      });
    }
  }

  void _startConversationListener() {
    _conversationSub?.cancel();
    _conversationSub = _firestore
        .collection('conversations')
        .doc(widget.conversationId)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          if (data == null) return;

          final title = data['title']?.toString().trim() ?? '';
          final participants = data['participants'] is List
              ? (data['participants'] as List)
                    .whereType<String>()
                    .where((id) => id.trim().isNotEmpty)
                    .toSet()
                    .toList()
              : <String>[];

          _warmParticipants(participants);

          if (!mounted) return;
          setState(() {
            if (title.isNotEmpty) {
              _title = title;
            }
            if (participants.isNotEmpty) {
              _participants = participants;
            }
          });
        });
  }

  void _warmParticipants(List<String> ids) {
    final currentUid = _auth.currentUser?.uid;
    final targets = ids.where((id) => id != currentUid).toSet();
    if (targets.isEmpty) return;
    _userCache.warmUsers(targets, listen: false);
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final participants = _participants.toSet().toList();
    if (!participants.contains(currentUser.uid)) {
      participants.add(currentUser.uid);
    }

    setState(() {
      _isSending = true;
    });
    _messageController.clear();

    try {
      await _chatService.sendRoomMessage(
        conversationId: widget.conversationId,
        messageText: text,
        participantIds: participants,
      );
      _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      _messageController.text = text;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final distance =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    return distance < 120;
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    _conversationSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.conversationType == 'server' ? 'Server' : 'Group',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatService.getMessages(widget.conversationId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Could not load messages: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }

                if (_isNearBottom()) {
                  _scrollToBottom();
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = Map<String, dynamic>.from(
                      docs[index].data() as Map<String, dynamic>,
                    );
                    return _buildMessageTile(data);
                  },
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageTile(Map<String, dynamic> data) {
    final currentUid = _auth.currentUser?.uid ?? '';
    final senderId = data['senderId']?.toString() ?? '';
    final isMe = senderId == currentUid;
    final type = data['type']?.toString() ?? 'text';
    final timestamp = data['timestamp'] is Timestamp
        ? data['timestamp'] as Timestamp
        : (data['clientTimestamp'] is Timestamp
              ? data['clientTimestamp'] as Timestamp
              : null);

    final senderData = _userCache.getCachedUser(senderId);
    final senderName = isMe
        ? 'You'
        : (senderData?['displayName']?.toString().trim().isNotEmpty == true
              ? senderData!['displayName'].toString().trim()
              : 'Member');

    if (!isMe && senderId.isNotEmpty) {
      _userCache.warmUsers([senderId], listen: false);
    }

    final bubbleColor = isMe
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = isMe
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: textColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            _buildMessageBody(type: type, data: data, textColor: textColor),
            if (timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  _formatTime(timestamp.toDate()),
                  style: TextStyle(
                    fontSize: 10,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBody({
    required String type,
    required Map<String, dynamic> data,
    required Color textColor,
  }) {
    if (type == 'file') {
      final fileName = data['fileName']?.toString().trim();
      return Text(
        (fileName != null && fileName.isNotEmpty)
            ? 'Shared file: $fileName'
            : 'Shared a file',
        style: TextStyle(color: textColor),
      );
    }

    return FutureBuilder<String>(
      future: _chatService.decryptMessage(messageData: data),
      builder: (context, snapshot) {
        final text = snapshot.data?.trim() ?? '';
        final message = text.isNotEmpty ? text : 'Encrypted message';
        return Text(message, style: TextStyle(color: textColor, fontSize: 15));
      },
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: 'Message...',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _isSending ? null : _sendMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final sameDay =
        now.year == date.year && now.month == date.month && now.day == date.day;
    if (sameDay) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}
