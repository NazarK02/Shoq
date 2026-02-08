import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/notification_service.dart';
import '../services/presence_service.dart';
import '../services/chat_service_e2ee.dart';
import '../services/user_cache_service.dart';
import 'user_profile_view_screen.dart';

/// E2EE-enabled chat screen with smooth loading
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
  final UserCacheService _userCache = UserCacheService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  String? _conversationId;
  Map<String, dynamic>? _recipientData;
  bool _hasMessages = false;
  String? _initError;
  final List<_PendingUpload> _pendingUploads = [];

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addObserver(this);
    _notificationService.setActiveChat(widget.recipientId);
    _recipientData = _userCache.getCachedUser(widget.recipientId);
    _userCache.warmUsers([widget.recipientId], listen: false);

    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      _conversationId = _chatService.getDirectConversationId(
        currentUser.uid,
        widget.recipientId,
      );
    }
    
    _initializeQuietly();
  }

  /// Initialize without showing loading spinner
  Future<void> _initializeQuietly() async {
    try {
      // Initialize encryption silently
      await _chatService.initializeEncryption();
      
      // Initialize conversation (will auto-create E2EE keys if needed)
      _conversationId = await _chatService.initializeConversation(widget.recipientId);
      
      // Listen to recipient data
      _listenToRecipientData();
      
      // Check if conversation has messages
      if (_conversationId != null) {
        _listenToConversationMetadata();
      }
      
      // Only update state once at the end
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
        });
      }
    }
  }

  void _listenToConversationMetadata() {
    _firestore.collection('conversations').doc(_conversationId).snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data();
        setState(() {
          _hasMessages = data?['hasMessages'] ?? false;
        });
      }
    });
  }

  @override
  void dispose() {
    _notificationService.setActiveChat(null);
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    for (final upload in _pendingUploads) {
      upload.sub?.cancel();
      upload.task?.cancel();
    }
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
        _userCache.mergeUserData(widget.recipientId, snapshot.data()!);
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

      // Send push notification (generic)
      try {
        final senderName = currentUser.displayName ?? 'Someone';
        await _notificationService.sendMessageNotification(
          recipientId: widget.recipientId,
          senderName: senderName,
          messageText: 'Sent a message',
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
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show error screen if initialization failed
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
                  _buildAvatar(photoUrl, 18),
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
          Expanded(
            child: _MessagesList(
              conversationId: _conversationId,
              recipientName: widget.recipientName,
              scrollController: _scrollController,
              chatService: _chatService,
              hasMessages: _hasMessages,
              pendingUploads: _pendingUploads,
              onCancelUpload: _cancelPendingUpload,
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Future<void> _showAttachmentSheet() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Image'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendFile(type: FileType.image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('File'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendFile(type: FileType.any);
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Location'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location sharing coming soon')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendFile({required FileType type}) async {
    if (_conversationId == null) return;

    String? pendingId;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
        type: type,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null || file.path!.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access selected file')),
          );
        }
        return;
      }

      final detectedMime = lookupMimeType(file.path!) ?? 'application/octet-stream';
      final upload = _chatService.startFileUpload(
        conversationId: _conversationId!,
        filePath: file.path!,
        fileName: file.name,
        mimeType: detectedMime,
      );
      pendingId = upload.messageId;

      final pending = _PendingUpload(
        id: upload.messageId,
        fileName: file.name,
        fileSize: file.size,
        mimeType: detectedMime,
        progress: 0,
      );
      pending.task = upload.task;

      setState(() {
        _pendingUploads.add(pending);
      });
      _scrollToBottom();

      pending.sub = upload.task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        final transferred = snapshot.bytesTransferred;
        if (total > 0 && mounted) {
          setState(() {
            pending.progress = (transferred / total).clamp(0, 1);
          });
        }
      });

      final snapshot = await upload.task;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      if (!_pendingUploads.any((u) => u.id == upload.messageId)) {
        return;
      }

      await _chatService.commitFileMessage(
        conversationId: _conversationId!,
        messageId: upload.messageId,
        storagePath: upload.storagePath,
        downloadUrl: downloadUrl,
        fileName: file.name,
        fileSize: file.size,
        mimeType: upload.contentType,
      );

      try {
        final currentUser = _auth.currentUser;
        final senderName = currentUser?.displayName ?? 'Someone';
        await _notificationService.sendMessageNotification(
          recipientId: widget.recipientId,
          senderName: senderName,
          messageText: 'Sent a file',
        );
      } catch (notificationError) {
        print('Error sending notification: $notificationError');
      }

      _removePendingUpload(upload.messageId);
      _scrollToBottom();
    } on FirebaseException catch (e) {
      if (e.code != 'canceled' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: ${e.message ?? e.code}')),
        );
      }
      if (pendingId != null) {
        _removePendingUpload(pendingId!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: ${e.toString()}')),
        );
      }
      if (pendingId != null) {
        _removePendingUpload(pendingId!);
      }
    }
  }

  Widget _buildAvatar(String? photoUrl, double radius) {
    final placeholder = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: radius,
        color: Colors.grey[600],
      ),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return placeholder;
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (radius * 2 * dpr).round().clamp(32, 256);

    return ClipOval(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
          fadeInDuration: const Duration(milliseconds: 150),
          fadeOutDuration: const Duration(milliseconds: 150),
        ),
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
              onPressed: _showAttachmentSheet,
              tooltip: 'Attach',
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

  void _removePendingUpload(String id) {
    final index = _pendingUploads.indexWhere((upload) => upload.id == id);
    if (index == -1) return;
    final upload = _pendingUploads[index];
    upload.sub?.cancel();
    if (mounted) {
      setState(() {
        _pendingUploads.removeAt(index);
      });
    }
  }

  void _cancelPendingUpload(String id) {
    final index = _pendingUploads.indexWhere((upload) => upload.id == id);
    if (index == -1) return;
    final upload = _pendingUploads[index];
    upload.sub?.cancel();
    upload.task?.cancel();
    if (mounted) {
      setState(() {
        _pendingUploads.removeAt(index);
      });
    }
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat'),
        content: const Text('Delete all messages? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_conversationId != null) {
                await _chatService.clearChat(_conversationId!);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// Optimized messages list with cached decryption
class _MessagesList extends StatefulWidget {
  final String? conversationId;
  final String recipientName;
  final ScrollController scrollController;
  final ChatService chatService;
  final bool hasMessages;
  final List<_PendingUpload> pendingUploads;
  final void Function(String id) onCancelUpload;

  const _MessagesList({
    required this.conversationId,
    required this.recipientName,
    required this.scrollController,
    required this.chatService,
    required this.hasMessages,
    required this.pendingUploads,
    required this.onCancelUpload,
  });

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> with AutomaticKeepAliveClientMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Map<String, _DownloadEntry> _downloads = {};
  // Cache decrypted messages to avoid re-decryption
  final Map<String, String> _decryptedCache = {};

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
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: widget.chatService.getMessages(widget.conversationId!),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        // Avoid showing empty-state flicker while loading
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            widget.pendingUploads.isEmpty) {
          return const SizedBox.shrink();
        }

        final messages = snapshot.data?.docs ?? [];

        if (messages.isEmpty && widget.pendingUploads.isEmpty) {
          return _buildEmptyState();
        }
        final pending = widget.pendingUploads;

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length + pending.length,
          itemBuilder: (context, index) {
            if (index >= messages.length) {
              final upload = pending[index - messages.length];
              return _buildPendingUploadBubble(
                upload,
                key: ValueKey('pending_${upload.id}'),
              );
            }
            final messageDoc = messages[index];
            final message = messageDoc.data() as Map<String, dynamic>;
            final messageId = messageDoc.id;
            final isMe = message['senderId'] == currentUser.uid;
            final timestamp = (message['timestamp'] as Timestamp?) ??
                (message['clientTimestamp'] as Timestamp?);
            final type = message['type']?.toString() ?? 'text';

            if (type == 'file') {
              return _buildFileBubble(
                message,
                isMe,
                timestamp,
                messageId: messageId,
                key: ValueKey(messageId),
              );
            }

            // Check cache first
            if (_decryptedCache.containsKey(messageId)) {
              return _buildMessageBubble(
                _decryptedCache[messageId]!,
                isMe,
                timestamp,
                key: ValueKey(messageId),
              );
            }

            final decryptFuture = widget.chatService.isEncryptionReady
                ? widget.chatService.decryptMessage(messageData: message)
                : Future.value('');

            return FutureBuilder<String>(
              future: decryptFuture.then((decrypted) {
                // Cache only successful decrypts to allow retries after init.
                if (widget.chatService.isEncryptionReady &&
                    decrypted.isNotEmpty &&
                    !decrypted.startsWith('[')) {
                  _decryptedCache[messageId] = decrypted;
                }
                return decrypted;
              }),
              builder: (context, decryptSnapshot) {
                String displayText;

                if (!widget.chatService.isEncryptionReady) {
                  displayText = _decryptedCache[messageId] ?? '';
                } else if (decryptSnapshot.connectionState == ConnectionState.waiting) {
                  // Use cached version if available during refresh
                  displayText = _decryptedCache[messageId] ?? '';
                } else if (decryptSnapshot.hasError) {
                  displayText = _decryptedCache[messageId] ?? '';
                  if (displayText.startsWith('[') && displayText != '[Sent]') {
                    displayText = '';
                  }
                } else {
                  displayText = decryptSnapshot.data ?? '';
                  if (displayText.startsWith('[') && displayText != '[Sent]') {
                    displayText = '';
                  }
                }

                return _buildMessageBubble(
                  displayText,
                  isMe,
                  timestamp,
                  key: ValueKey(messageId),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
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

  Widget _buildMessageBubble(
    String text,
    bool isMe,
    Timestamp? timestamp, {
    Key? key,
  }) {
    // Don't show empty messages while loading
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

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

  Widget _buildPendingUploadBubble(
    _PendingUpload upload, {
    Key? key,
  }) {
    return Align(
      key: key,
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_upload, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    upload.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: upload.progress,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 3,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(upload.progress * 100).toStringAsFixed(0)}% • ${_formatBytes(upload.fileSize)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              onPressed: () => widget.onCancelUpload(upload.id),
              tooltip: 'Cancel',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileBubble(
    Map<String, dynamic> message,
    bool isMe,
    Timestamp? timestamp, {
    required String messageId,
    Key? key,
  }) {
    final fileName = message['fileName']?.toString() ?? 'File';
    final fileSize = message['fileSize'] is int ? message['fileSize'] as int : 0;
    final fileUrl = message['fileUrl']?.toString() ?? '';
    final mimeType = message['mimeType']?.toString() ?? '';
    final isImage = mimeType.toLowerCase().startsWith('image/');
    final download = _downloads[messageId];
    final isDownloading = download?.status == _DownloadStatus.downloading;
    final isDownloaded =
        download?.status == _DownloadStatus.done && (download?.localPath?.isNotEmpty ?? false);
    final progress = download?.progress ?? 0;
    final localPath = download?.localPath;

    void handleTap() {
      if (isDownloaded && localPath != null) {
        if (isImage) {
          _openImageViewer(localPath, fileName);
        } else {
          _openDownloadedFile(localPath);
        }
        return;
      }
      if (!isDownloading && fileUrl.isNotEmpty) {
        _downloadFile(
          messageId: messageId,
          url: fileUrl,
          fileName: fileName,
        );
      }
    }

    return Align(
      key: key,
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        child: InkWell(
          onTap: fileUrl.isEmpty ? null : handleTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: isMe ? Colors.white12 : Colors.white,
                    child: isDownloaded && localPath != null
                        ? Image.file(
                            File(localPath),
                            fit: BoxFit.cover,
                            width: 48,
                            height: 48,
                          )
                        : Icon(
                            Icons.image,
                            color: isMe ? Colors.white : Colors.black54,
                          ),
                  ),
                )
              else
                Icon(
                  _iconForMime(mimeType),
                  color: isMe ? Colors.white : Colors.black87,
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatBytes(fileSize),
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        backgroundColor: isMe ? Colors.white24 : Colors.black12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isMe ? Colors.white : Colors.black54,
                        ),
                        minHeight: 3,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (timestamp != null && !isDownloading) ...[
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
              if (fileUrl.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: isDownloading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: progress > 0 ? progress : null,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isMe ? Colors.white : Colors.black54,
                            ),
                          ),
                        )
                      : Icon(
                          isDownloaded ? Icons.open_in_new : Icons.download,
                          size: 18,
                          color: isMe ? Colors.white70 : Colors.black54,
                        ),
                  onPressed: isDownloading ? null : handleTap,
                  tooltip: isDownloaded ? 'Open' : 'Download',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadFile({
    required String messageId,
    required String url,
    required String fileName,
  }) async {
    final existing = _downloads[messageId];
    if (existing?.status == _DownloadStatus.downloading) return;

    setState(() {
      _downloads[messageId] = _DownloadEntry(
        status: _DownloadStatus.downloading,
        progress: 0,
        localPath: null,
      );
    });

    final client = HttpClient();
    try {
      final targetPath = await _resolveDownloadPath(fileName);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode}');
      }

      final total = response.contentLength;
      final file = File(targetPath);
      final sink = file.openWrite();
      int received = 0;

      await response.listen((chunk) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && mounted) {
          final entry = _downloads[messageId];
          if (entry == null) return;
          setState(() {
            entry.progress = (received / total).clamp(0, 1);
          });
        }
      }).asFuture();

      await sink.close();

      if (!mounted) return;
      setState(() {
        _downloads[messageId] = _DownloadEntry(
          status: _DownloadStatus.done,
          progress: 1,
          localPath: targetPath,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloads[messageId] = _DownloadEntry(
          status: _DownloadStatus.failed,
          progress: 0,
          localPath: null,
          error: e.toString(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: ${e.toString()}')),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openDownloadedFile(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  void _openImageViewer(String path, String fileName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ImageViewerScreen(
          filePath: path,
          fileName: fileName,
        ),
      ),
    );
  }

  Future<String> _resolveDownloadPath(String fileName) async {
    final baseDir = await _getDownloadDirectory();
    final safeName = _sanitizeFileName(fileName);
    final folder = Directory(p.join(baseDir.path, 'ShoqDownloads'));
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }

    final candidate = p.join(folder.path, safeName);
    if (!File(candidate).existsSync()) {
      return candidate;
    }

    final name = p.basenameWithoutExtension(safeName);
    final ext = p.extension(safeName);
    int i = 1;
    while (true) {
      final next = p.join(folder.path, '${name}_$i$ext');
      if (!File(next).existsSync()) return next;
      i++;
    }
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isWindows) {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir;
    }
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  String _sanitizeFileName(String name) {
    final trimmed = name.trim().isEmpty ? 'file' : name.trim();
    return trimmed.replaceAll(RegExp(r'[\\\\/]+'), '_');
  }

  IconData _iconForMime(String mime) {
    final m = mime.toLowerCase();
    if (m.startsWith('image/')) return Icons.image;
    if (m.startsWith('video/')) return Icons.videocam;
    if (m.startsWith('audio/')) return Icons.audiotrack;
    if (m.contains('pdf')) return Icons.picture_as_pdf;
    if (m.contains('zip') || m.contains('compressed')) return Icons.folder_zip;
    if (m.contains('spreadsheet') || m.contains('excel')) return Icons.grid_on;
    if (m.contains('word') || m.contains('document')) return Icons.description;
    return Icons.insert_drive_file;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final value = size < 10 && unit > 0 ? size.toStringAsFixed(1) : size.toStringAsFixed(0);
    return '$value ${units[unit]}';
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

class _ImageViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const _ImageViewerScreen({
    required this.filePath,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);

    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _saveCopy(context),
            tooltip: 'Save copy',
          ),
        ],
      ),
      body: Center(
        child: file.existsSync()
            ? InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(file),
              )
            : const Text('Image not found'),
      ),
    );
  }

  Future<void> _saveCopy(BuildContext context) async {
    try {
      final targetDir = await _getDownloadDirectory();
      final folder = Directory(p.join(targetDir.path, 'ShoqDownloads'));
      if (!folder.existsSync()) {
        await folder.create(recursive: true);
      }

      final safeName = fileName.trim().isEmpty ? 'image' : fileName.trim();
      final sanitized = safeName.replaceAll(RegExp(r'[\\\\/]+'), '_');
      final base = p.join(folder.path, sanitized);
      final targetPath = await _uniquePath(base);

      if (filePath != targetPath) {
        await File(filePath).copy(targetPath);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to $targetPath')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isWindows) {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir;
    }
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<String> _uniquePath(String basePath) async {
    if (!File(basePath).existsSync()) return basePath;
    final dir = p.dirname(basePath);
    final name = p.basenameWithoutExtension(basePath);
    final ext = p.extension(basePath);
    int i = 1;
    while (true) {
      final next = p.join(dir, '${name}_$i$ext');
      if (!File(next).existsSync()) return next;
      i++;
    }
  }
}

class _PendingUpload {
  final String id;
  final String fileName;
  final int fileSize;
  final String mimeType;
  double progress;
  UploadTask? task;
  StreamSubscription<TaskSnapshot>? sub;

  _PendingUpload({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.progress,
  });
}

enum _DownloadStatus { downloading, done, failed }

class _DownloadEntry {
  _DownloadStatus status;
  double progress;
  String? localPath;
  String? error;

  _DownloadEntry({
    required this.status,
    required this.progress,
    required this.localPath,
    this.error,
  });
}
