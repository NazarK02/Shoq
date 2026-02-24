import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import '../services/notification_service.dart';
import '../services/presence_service.dart';
import '../services/chat_service_e2ee.dart';
import '../services/user_cache_service.dart';
import '../services/file_download_service.dart';
import 'user_profile_view_screen.dart';
import 'image_viewer_screen.dart';
import 'call_screen.dart';

/// Improved E2EE chat with torrent-like file handling
class ImprovedChatScreen extends StatefulWidget {
  final String recipientId;
  final String recipientName;

  const ImprovedChatScreen({
    super.key,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  State<ImprovedChatScreen> createState() => _ImprovedChatScreenState();
}

class _ImprovedChatScreenState extends State<ImprovedChatScreen>
    with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  final NotificationService _notificationService = NotificationService();
  final UserCacheService _userCache = UserCacheService();
  final FileDownloadService _downloadService = FileDownloadService();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  static const double _autoScrollThreshold = 110;
  static const double _scrollButtonThreshold = 320;

  String? _conversationId;
  Map<String, dynamic>? _recipientData;
  bool _hasMessages = false;
  String? _initError;
  bool _sendPulse = false;
  bool _showScrollToBottomButton = false;
  _ReplyDraft? _replyDraft;
  final List<_PendingTextMessage> _pendingTextMessages = [];
  final List<_PendingUpload> _pendingUploads = [];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _notificationService.setActiveChat(widget.recipientId);
    _recipientData = _userCache.getCachedUser(widget.recipientId);
    _userCache.warmUsers([widget.recipientId], listen: false);
    _downloadService.addListener(_onDownloadProgressUpdate);
    _scrollController.addListener(_handleScrollChanged);

    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      _conversationId = _chatService.getDirectConversationId(
        currentUser.uid,
        widget.recipientId,
      );
    }

    _initializeQuietly();
  }

  Future<void> _initializeQuietly() async {
    try {
      await _chatService.initializeEncryption();
      _conversationId = await _chatService.initializeConversation(
        widget.recipientId,
      );
      _listenToRecipientData();

      if (_conversationId != null) {
        unawaited(
          _chatService.backfillSenderPublicKeyForConversation(_conversationId!),
        );
        _listenToConversationMetadata();
      }

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

  void _onDownloadProgressUpdate() {
    if (mounted) setState(() {});
  }

  void _handleScrollChanged() {
    if (!_scrollController.hasClients) return;
    final distance =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    final shouldShow = distance > _scrollButtonThreshold;
    if (!mounted || shouldShow == _showScrollToBottomButton) return;
    setState(() {
      _showScrollToBottomButton = shouldShow;
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final distance =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    return distance <= _autoScrollThreshold;
  }

  void _listenToConversationMetadata() {
    _firestore
        .collection('conversations')
        .doc(_conversationId)
        .snapshots()
        .listen((snapshot) {
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
    _downloadService.removeListener(_onDownloadProgressUpdate);
    _scrollController.removeListener(_handleScrollChanged);
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _messageFocusNode.dispose();
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
    _firestore.collection('users').doc(widget.recipientId).snapshots().listen((
      snapshot,
    ) {
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
    final replyDraft = _replyDraft;

    try {
      _messageController.clear();
      _messageFocusNode.requestFocus();
      if (mounted) {
        setState(() {
          _sendPulse = true;
          _replyDraft = null;
        });
      }
      Future.delayed(const Duration(milliseconds: 170), () {
        if (!mounted) return;
        setState(() {
          _sendPulse = false;
        });
      });

      await _chatService.sendMessage(
        conversationId: _conversationId!,
        messageText: messageText,
        recipientId: widget.recipientId,
        replyToMessageId: replyDraft?.messageId,
        replyToText: replyDraft?.previewText,
        replyToSenderId: replyDraft?.senderId,
      );

      try {
        final senderName = currentUser.displayName ?? 'Someone';
        await _notificationService.sendMessageNotification(
          recipientId: widget.recipientId,
          senderName: senderName,
          messageText: 'Sent a message',
          conversationId: _conversationId,
        );
      } catch (notificationError) {
        print('Error sending notification: $notificationError');
      }

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        if (_messageController.text.trim().isEmpty) {
          _messageController.text = messageText;
          _messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: _messageController.text.length),
          );
        }
        setState(() {
          _replyDraft = replyDraft;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: ${e.toString()}')),
        );
      }
    }
  }

  void _setReplyDraft(_ReplyDraft draft) {
    if (!mounted) return;
    setState(() {
      _replyDraft = draft;
    });
    _messageFocusNode.requestFocus();
  }

  void _scrollToBottom({bool force = false, bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (!force && !_isNearBottom()) return;

      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        return;
      }

      _scrollController.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.recipientName)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Encryption Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
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
      appBar: _buildAppBar(displayName, photoUrl),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _MessagesList(
                    conversationId: _conversationId,
                    recipientName: widget.recipientName,
                    scrollController: _scrollController,
                    chatService: _chatService,
                    downloadService: _downloadService,
                    hasMessages: _hasMessages,
                    recipientId: widget.recipientId,
                    pendingTextMessages: _pendingTextMessages,
                    pendingUploads: _pendingUploads,
                    onPendingTextDelivered: _ackPendingTextMessages,
                    onCancelUpload: _cancelPendingUpload,
                    onReplyRequested: _setReplyDraft,
                    shouldAutoScroll: _isNearBottom,
                    onAutoScrollToBottom: () =>
                        _scrollToBottom(force: true, animated: true),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: AnimatedSlide(
                    offset: _showScrollToBottomButton
                        ? Offset.zero
                        : const Offset(0, 1.1),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _showScrollToBottomButton ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: FloatingActionButton.small(
                        heroTag: 'chat_scroll_bottom',
                        onPressed: () =>
                            _scrollToBottom(force: true, animated: true),
                        tooltip: 'Jump to latest',
                        child: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String displayName, String? photoUrl) {
    return AppBar(
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
                  stream: PresenceService().getUserStatusStream(
                    widget.recipientId,
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    final isOnline = PresenceService.isUserOnline(
                      snapshot.data ?? {},
                    );

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
        IconButton(
          icon: const Icon(Icons.call),
          tooltip: 'Audio call',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen.outgoing(
                  peerId: widget.recipientId,
                  peerName: displayName,
                  peerPhotoUrl: photoUrl,
                  isVideo: false,
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.videocam),
          tooltip: 'Video call',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen.outgoing(
                  peerId: widget.recipientId,
                  peerName: displayName,
                  peerPhotoUrl: photoUrl,
                  isVideo: true,
                ),
              ),
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
            const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatar(String? photoUrl, double radius) {
    final placeholder = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[300],
      child: Icon(Icons.person, size: radius, color: Colors.grey[600]),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return placeholder;
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (radius * 2 * dpr).round().clamp(32, 256);
    // Windows-specific handling to prevent crashes
    if (Platform.isWindows) {
      return ClipOval(
        child: Container(
          width: radius * 2,
          height: radius * 2,
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Image(
            image: CachedNetworkImageProvider(photoUrl),
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: frame == null ? placeholder : child,
              );
            },
            errorBuilder: (_, __, ___) => placeholder,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return placeholder;
            },
          ),
        ),
      );
    }

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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyDraft != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(color: colorScheme.primary, width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Replying to ${_replyDraft!.senderName}',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _replyDraft!.previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() => _replyDraft = null);
                      },
                      tooltip: 'Cancel reply',
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Material(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _showAttachmentSheet,
                    tooltip: 'Attach',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isCollapsed: true,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _messageController,
                  builder: (context, value, _) {
                    final canSend =
                        _conversationId != null && value.text.trim().isNotEmpty;

                    return AnimatedScale(
                      scale: _sendPulse ? 0.86 : 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutBack,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: canSend
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        child: IconButton(
                          icon: Icon(
                            Icons.send_rounded,
                            color: canSend
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                          onPressed: canSend ? _sendMessage : null,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
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

      final detectedMime =
          lookupMimeType(file.path!) ?? 'application/octet-stream';
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
          conversationId: _conversationId,
        );
      } catch (notificationError) {
        print('Error sending notification: $notificationError');
      }

      _removePendingUpload(upload.messageId);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send file: ${e.toString()}')),
        );
      }
      if (pendingId != null) {
        _removePendingUpload(pendingId);
      }
    }
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

  void _removePendingTextMessage(String id) {
    if (!mounted) return;
    final index = _pendingTextMessages.indexWhere(
      (pending) => pending.id == id,
    );
    if (index == -1) return;
    setState(() {
      _pendingTextMessages.removeAt(index);
    });
  }

  void _ackPendingTextMessages(Set<String> deliveredIds) {
    if (!mounted || deliveredIds.isEmpty) return;
    setState(() {
      _pendingTextMessages.removeWhere((m) => deliveredIds.contains(m.id));
    });
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

/// Messages list with image preview and on-demand downloads
class _MessagesList extends StatefulWidget {
  final String? conversationId;
  final String recipientId;
  final String recipientName;
  final ScrollController scrollController;
  final ChatService chatService;
  final FileDownloadService downloadService;
  final bool hasMessages;
  final List<_PendingTextMessage> pendingTextMessages;
  final List<_PendingUpload> pendingUploads;
  final void Function(Set<String> ids) onPendingTextDelivered;
  final void Function(String id) onCancelUpload;
  final void Function(_ReplyDraft draft) onReplyRequested;
  final bool Function() shouldAutoScroll;
  final VoidCallback onAutoScrollToBottom;

  const _MessagesList({
    required this.conversationId,
    required this.recipientId,
    required this.recipientName,
    required this.scrollController,
    required this.chatService,
    required this.downloadService,
    required this.hasMessages,
    required this.pendingTextMessages,
    required this.pendingUploads,
    required this.onPendingTextDelivered,
    required this.onCancelUpload,
    required this.onReplyRequested,
    required this.shouldAutoScroll,
    required this.onAutoScrollToBottom,
  });

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList>
    with AutomaticKeepAliveClientMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, String> _decryptedCache = {};
  final Map<String, Future<String>> _decryptFutureCache = {};
  final Map<String, String> _decryptInputSignature = {};
  final Set<String> _animatedMessageIds = {};
  bool _animationCachePrimed = false;
  int _lastTotalItems = 0;
  bool _markReadInFlight = false;

  @override
  bool get wantKeepAlive => true;

  String _mapSignature(dynamic value) {
    if (value is! Map) return '';
    final parts = <String>[];
    value.forEach((key, val) {
      parts.add('${key.toString()}:${val?.toString() ?? ''}');
    });
    parts.sort();
    return parts.join('|');
  }

  String _decryptSignature(Map<String, dynamic> message) {
    return [
      message['senderId']?.toString() ?? '',
      message['senderDeviceId']?.toString() ?? '',
      message['senderPublicKey']?.toString() ?? '',
      message['senderKeyId']?.toString() ?? '',
      message['ciphertext']?.toString() ?? '',
      message['senderCiphertext']?.toString() ?? '',
      _mapSignature(message['ciphertexts']),
      _mapSignature(message['senderCiphertexts']),
      _mapSignature(message['ciphertextsByKey']),
      _mapSignature(message['senderCiphertextsByKey']),
    ].join('||');
  }

  Widget _animateOnFirstPaint({required String id, required Widget child}) {
    final shouldAnimate = _animatedMessageIds.add(id);
    if (!shouldAnimate) return child;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        final offsetY = (1 - value) * 16;
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0, offsetY), child: child),
        );
      },
    );
  }

  void _scheduleAutoScrollIfNeeded(int totalItems) {
    if (totalItems <= 0) {
      _lastTotalItems = 0;
      return;
    }

    final firstLoad = _lastTotalItems == 0;
    final hasNewItems = totalItems > _lastTotalItems;
    final shouldAutoScroll =
        firstLoad || (hasNewItems && widget.shouldAutoScroll());
    _lastTotalItems = totalItems;

    if (!shouldAutoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onAutoScrollToBottom();
    });
  }

  void _markIncomingMessagesAsRead(
    List<QueryDocumentSnapshot> messages,
    String currentUserId,
  ) {
    if (_markReadInFlight || widget.conversationId == null) return;

    final hasUnreadFromPeer = messages.any((doc) {
      final data = doc.data();
      if (data is! Map) return false;
      final map = Map<String, dynamic>.from(data as Map);
      final senderId = map['senderId']?.toString();
      final isRead = map['read'] == true;
      return senderId == widget.recipientId && !isRead;
    });

    if (!hasUnreadFromPeer) return;
    _markReadInFlight = true;
    unawaited(
      widget.chatService
          .markMessagesAsRead(
            conversationId: widget.conversationId!,
            otherUserId: widget.recipientId,
          )
          .catchError((error) {
            if (!mounted) return;
            debugPrint('markMessagesAsRead failed: $error');
          })
          .whenComplete(() {
            _markReadInFlight = false;
          }),
    );
  }

  Map<String, String> _extractReactions(Map<String, dynamic> message) {
    final raw = message['reactions'];
    if (raw is! Map) return const <String, String>{};
    final result = <String, String>{};
    raw.forEach((key, value) {
      final uid = key.toString().trim();
      final emoji = value?.toString().trim() ?? '';
      if (uid.isEmpty || emoji.isEmpty) return;
      result[uid] = emoji;
    });
    return result;
  }

  String _formatDetailsTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';
    final date = timestamp.toDate();
    return DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  Future<void> _showEditDialog({
    required String messageId,
    required String originalText,
  }) async {
    final conversationId = widget.conversationId;
    if (conversationId == null) return;

    final controller = TextEditingController(text: originalText);
    final editedText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Edit your message',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || editedText == null) return;
    if (editedText.isEmpty || editedText == originalText.trim()) return;

    try {
      await widget.chatService.editMessage(
        conversationId: conversationId,
        messageId: messageId,
        recipientId: widget.recipientId,
        messageText: editedText,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not edit message: $e')));
    }
  }

  Future<void> _showReactionPicker({
    required String messageId,
    required Map<String, dynamic> message,
  }) async {
    final conversationId = widget.conversationId;
    final currentUserId = _auth.currentUser?.uid;
    if (conversationId == null || currentUserId == null) return;

    const emojis = ['👍', '❤️', '😂', '🔥', '😮', '😢', '🙏'];
    final currentReaction = _extractReactions(message)[currentUserId];

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final emoji in emojis)
                  ChoiceChip(
                    label: Text(emoji, style: const TextStyle(fontSize: 22)),
                    selected: currentReaction == emoji,
                    onSelected: (_) async {
                      Navigator.pop(context);
                      try {
                        final ref = _firestore
                            .collection('conversations')
                            .doc(conversationId)
                            .collection('messages')
                            .doc(messageId);
                        if (currentReaction == emoji) {
                          await ref.update({
                            'reactions.$currentUserId': FieldValue.delete(),
                          });
                        } else {
                          await ref.set({
                            'reactions': {currentUserId: emoji},
                          }, SetOptions(merge: true));
                        }
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text('Could not save reaction: $e'),
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMessageActions({
    required String messageId,
    required Map<String, dynamic> message,
    required String displayText,
    required bool isMe,
    required Timestamp? sentAt,
    required Timestamp? readAt,
  }) async {
    final canEdit = isMe && (message['type']?.toString() ?? 'text') == 'text';
    final rootContext = context;

    await showModalBottomSheet<void>(
      context: rootContext,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onReplyRequested(
                    _ReplyDraft(
                      messageId: messageId,
                      senderId: message['senderId']?.toString() ?? '',
                      senderName: isMe ? 'You' : widget.recipientName,
                      previewText: displayText,
                    ),
                  );
                },
              ),
              if (canEdit)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showEditDialog(
                      messageId: messageId,
                      originalText: displayText,
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward'),
                subtitle: const Text('Copies message text'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Clipboard.setData(ClipboardData(text: displayText));
                  if (!mounted) return;
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Message copied for forward')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('React'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReactionPicker(messageId: messageId, message: message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Read details'),
                subtitle: Text(
                  isMe
                      ? (readAt != null
                            ? 'Read ${_formatDetailsTime(readAt)}'
                            : 'Not read yet')
                      : 'Sent ${_formatDetailsTime(sentAt)}',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showDialog<void>(
                    context: rootContext,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Message details'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sent: ${_formatDetailsTime(sentAt)}'),
                          const SizedBox(height: 8),
                          Text(
                            isMe
                                ? (readAt != null
                                      ? 'Read: ${_formatDetailsTime(readAt)}'
                                      : 'Read: Not read yet')
                                : 'Read receipt is shown for your own messages',
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReactionsRow(Map<String, dynamic> message) {
    final reactions = _extractReactions(message);
    if (reactions.isEmpty) return const SizedBox.shrink();

    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final entry in counts.entries)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${entry.key} ${entry.value}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

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

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            widget.pendingTextMessages.isEmpty &&
            widget.pendingUploads.isEmpty) {
          return const SizedBox.shrink();
        }

        final messages = snapshot.data?.docs ?? [];
        if (!_animationCachePrimed && messages.isNotEmpty) {
          _animationCachePrimed = true;
          _animatedMessageIds.addAll(messages.map((doc) => 'msg_${doc.id}'));
          _animatedMessageIds.addAll(messages.map((doc) => 'file_${doc.id}'));
        }

        final visibleMessageIds = messages.map((doc) => doc.id).toSet();
        _markIncomingMessagesAsRead(messages, currentUser.uid);
        final deliveredPendingIds = widget.pendingTextMessages
            .where((pending) => visibleMessageIds.contains(pending.id))
            .map((pending) => pending.id)
            .toSet();
        if (deliveredPendingIds.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onPendingTextDelivered(deliveredPendingIds);
          });
        }

        _decryptedCache.removeWhere(
          (key, _) => !visibleMessageIds.contains(key),
        );
        _decryptFutureCache.removeWhere(
          (key, _) => !visibleMessageIds.contains(key),
        );
        _decryptInputSignature.removeWhere(
          (key, _) => !visibleMessageIds.contains(key),
        );

        if (messages.isEmpty &&
            widget.pendingTextMessages.isEmpty &&
            widget.pendingUploads.isEmpty) {
          return _buildEmptyState();
        }

        final pendingText = widget.pendingTextMessages;
        final pendingUploads = widget.pendingUploads;
        final totalItems =
            messages.length + pendingText.length + pendingUploads.length;
        _scheduleAutoScrollIfNeeded(totalItems);

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index >= messages.length) {
              final pendingIndex = index - messages.length;
              if (pendingIndex < pendingText.length) {
                final textMessage = pendingText[pendingIndex];
                return _animateOnFirstPaint(
                  id: 'pending_text_${textMessage.id}',
                  child: _buildPendingTextBubble(
                    textMessage,
                    key: ValueKey('pending_text_${textMessage.id}'),
                  ),
                );
              }

              final upload = pendingUploads[pendingIndex - pendingText.length];
              return _animateOnFirstPaint(
                id: 'pending_upload_${upload.id}',
                child: _buildPendingUploadBubble(
                  upload,
                  key: ValueKey('pending_upload_${upload.id}'),
                ),
              );
            }

            final messageDoc = messages[index];
            final message = messageDoc.data() as Map<String, dynamic>;
            final messageId = messageDoc.id;
            final isMe = message['senderId'] == currentUser.uid;
            final timestamp =
                (message['timestamp'] as Timestamp?) ??
                (message['clientTimestamp'] as Timestamp?);
            final isPending = messageDoc.metadata.hasPendingWrites;
            final isRead = message['read'] == true;
            final readAt = message['readAt'] as Timestamp?;
            final type = message['type']?.toString() ?? 'text';

            if (type == 'file') {
              return _animateOnFirstPaint(
                id: 'file_$messageId',
                child: _buildFileBubble(
                  message,
                  isMe,
                  timestamp,
                  isPending: isPending,
                  isRead: isRead,
                  messageId: messageId,
                  key: ValueKey(messageId),
                ),
              );
            }

            if (_decryptedCache.containsKey(messageId)) {
              return _animateOnFirstPaint(
                id: 'msg_$messageId',
                child: _buildMessageBubble(
                  _decryptedCache[messageId]!,
                  isMe,
                  timestamp,
                  messageId: messageId,
                  messageData: message,
                  isPending: isPending,
                  isRead: isRead,
                  readAt: readAt,
                  key: ValueKey(messageId),
                ),
              );
            }

            final signature = _decryptSignature(message);
            if (_decryptInputSignature[messageId] != signature) {
              _decryptInputSignature[messageId] = signature;
              _decryptFutureCache.remove(messageId);
              _decryptedCache.remove(messageId);
            }

            final decryptFuture = _decryptFutureCache.putIfAbsent(
              messageId,
              () {
                final future = widget.chatService.isEncryptionReady
                    ? widget.chatService.decryptMessage(messageData: message)
                    : Future.value('');

                return future.then((decrypted) {
                  if (widget.chatService.isEncryptionReady &&
                      decrypted.isNotEmpty) {
                    _decryptedCache[messageId] = decrypted;
                  }
                  return decrypted;
                });
              },
            );

            return FutureBuilder<String>(
              future: decryptFuture,
              builder: (context, decryptSnapshot) {
                String displayText;

                if (!widget.chatService.isEncryptionReady) {
                  displayText = _decryptedCache[messageId] ?? '';
                } else if (decryptSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  displayText = _decryptedCache[messageId] ?? '';
                } else if (decryptSnapshot.hasError) {
                  displayText = _decryptedCache[messageId] ?? '';
                  if (displayText.isEmpty) {
                    displayText = 'Unable to decrypt this message';
                  }
                } else {
                  displayText = decryptSnapshot.data ?? '';
                  if (displayText.isEmpty) {
                    displayText = _decryptedCache[messageId] ?? '';
                  }
                  if (displayText.isEmpty) {
                    displayText = 'Unable to decrypt this message';
                  }
                }

                return _animateOnFirstPaint(
                  id: 'msg_$messageId',
                  child: _buildMessageBubble(
                    displayText,
                    isMe,
                    timestamp,
                    messageId: messageId,
                    messageData: message,
                    isPending: isPending,
                    isRead: isRead,
                    readAt: readAt,
                    key: ValueKey(messageId),
                  ),
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
    required String messageId,
    required Map<String, dynamic> messageData,
    required bool isPending,
    required bool isRead,
    required Timestamp? readAt,
    Key? key,
  }) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final receivedTextColor = colorScheme.onSurface;
    final receivedMetaColor = colorScheme.onSurfaceVariant;
    final incomingBubbleColor = isDarkTheme
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.92)
        : colorScheme.surfaceContainerHigh;

    final replyText = messageData['replyToText']?.toString().trim() ?? '';
    final replySenderId = messageData['replyToSenderId']?.toString() ?? '';
    final replySenderName = replySenderId == _auth.currentUser?.uid
        ? 'You'
        : widget.recipientName;
    final isEdited = messageData['edited'] == true;
    final sentAtText = timestamp != null
        ? DateFormat('HH:mm').format(timestamp.toDate())
        : '';
    final statusIcon = isPending ? Icons.done : Icons.done_all;
    final statusColor = isPending
        ? colorScheme.onPrimary.withValues(alpha: 0.72)
        : (isRead
              ? colorScheme.tertiary
              : colorScheme.onPrimary.withValues(alpha: 0.72));

    return Align(
      key: key,
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          _showMessageActions(
            messageId: messageId,
            message: messageData,
            displayText: text,
            isMe: isMe,
            sentAt: timestamp,
            readAt: readAt,
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMe ? colorScheme.primary : incomingBubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            border: !isMe && isDarkTheme
                ? Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (replyText.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  decoration: BoxDecoration(
                    color: isMe
                        ? colorScheme.onPrimary.withValues(alpha: 0.16)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        replySenderName,
                        style: TextStyle(
                          color: isMe
                              ? colorScheme.onPrimary.withValues(alpha: 0.92)
                              : colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        replyText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMe
                              ? colorScheme.onPrimary.withValues(alpha: 0.8)
                              : receivedMetaColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                text,
                style: TextStyle(
                  color: isMe ? colorScheme.onPrimary : receivedTextColor,
                  fontSize: 15,
                ),
              ),
              if (isEdited) ...[
                const SizedBox(height: 2),
                Text(
                  'edited',
                  style: TextStyle(
                    color: isMe
                        ? colorScheme.onPrimary.withValues(alpha: 0.72)
                        : receivedMetaColor,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              _buildReactionsRow(messageData),
              if (timestamp != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sentAtText,
                      style: TextStyle(
                        color: isMe
                            ? colorScheme.onPrimary.withValues(alpha: 0.72)
                            : receivedMetaColor,
                        fontSize: 11,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(statusIcon, size: 14, color: statusColor),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingTextBubble(_PendingTextMessage pending, {Key? key}) {
    return Align(
      key: key,
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.82),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pending.text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Sending...',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(width: 6),
                Text(
                  DateFormat('HH:mm').format(pending.createdAt),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingUploadBubble(_PendingUpload upload, {Key? key}) {
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
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
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
    required bool isPending,
    required bool isRead,
    required String messageId,
    Key? key,
  }) {
    final fileName = message['fileName']?.toString() ?? 'File';
    final fileSize = message['fileSize'] is int
        ? message['fileSize'] as int
        : 0;
    final fileUrl = message['fileUrl']?.toString() ?? '';
    final mimeType = message['mimeType']?.toString() ?? '';
    final isImage = mimeType.toLowerCase().startsWith('image/');

    // Check download status
    final downloadProgress = widget.downloadService.getProgress(messageId);
    final isDownloading =
        downloadProgress?.status == DownloadStatus.downloading;
    final isDownloaded = downloadProgress?.status == DownloadStatus.completed;
    final localPath = downloadProgress?.localPath;
    final progress = downloadProgress?.progress ?? 0;
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final incomingBubbleColor = isDarkTheme
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.92)
        : colorScheme.surfaceContainerHigh;

    return Align(
      key: key,
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: isImage ? EdgeInsets.zero : const EdgeInsets.all(8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isImage
              ? Colors.transparent
              : (isMe ? colorScheme.primary : incomingBubbleColor),
          borderRadius: BorderRadius.circular(isImage ? 12 : 16),
          border: !isImage && !isMe && isDarkTheme
              ? Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                )
              : null,
        ),
        child: isImage
            ? _buildImagePreview(
                fileUrl: fileUrl,
                fileName: fileName,
                fileSize: fileSize,
                localPath: localPath,
                timestamp: timestamp,
                isMe: isMe,
              )
            : _buildFileInfo(
                fileName: fileName,
                fileSize: fileSize,
                mimeType: mimeType,
                isDownloading: isDownloading,
                isDownloaded: isDownloaded,
                progress: progress,
                timestamp: timestamp,
                isMe: isMe,
                isPending: isPending,
                isRead: isRead,
                onAction: () => _handleFileAction(
                  messageId: messageId,
                  url: fileUrl,
                  fileName: fileName,
                  mimeType: mimeType,
                  fileSize: fileSize,
                  isDownloaded: isDownloaded,
                  localPath: localPath,
                ),
              ),
      ),
    );
  }

  Widget _buildImagePreview({
    required String fileUrl,
    required String fileName,
    required int fileSize,
    required String? localPath,
    required Timestamp? timestamp,
    required bool isMe,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(
              imageUrl: fileUrl,
              localPath: localPath,
              fileName: fileName,
              fileSize: fileSize,
            ),
          ),
        );
      },
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
                maxHeight: 400,
              ),
              child: CachedNetworkImage(
                imageUrl: fileUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 200,
                  color: Colors.grey[800],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 200,
                  color: Colors.grey[800],
                  child: const Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 48,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Timestamp overlay
          if (timestamp != null)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  DateFormat('HH:mm').format(timestamp.toDate()),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileInfo({
    required String fileName,
    required int fileSize,
    required String mimeType,
    required bool isDownloading,
    required bool isDownloaded,
    required double progress,
    required Timestamp? timestamp,
    required bool isMe,
    required bool isPending,
    required bool isRead,
    required VoidCallback onAction,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final receivedTextColor = colorScheme.onSurface;
    final receivedMetaColor = colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _iconForMime(mimeType),
          color: isMe ? colorScheme.onPrimary : receivedTextColor,
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
                  color: isMe ? colorScheme.onPrimary : receivedTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatBytes(fileSize),
                style: TextStyle(
                  color: isMe
                      ? colorScheme.onPrimary.withValues(alpha: 0.7)
                      : receivedMetaColor,
                  fontSize: 12,
                ),
              ),
              if (isDownloading) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: isMe
                      ? colorScheme.onPrimary.withValues(alpha: 0.22)
                      : colorScheme.onSurface.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isMe ? colorScheme.onPrimary : receivedMetaColor,
                  ),
                  minHeight: 3,
                ),
              ],
              if (timestamp != null && !isDownloading) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('HH:mm').format(timestamp.toDate()),
                      style: TextStyle(
                        color: isMe
                            ? colorScheme.onPrimary.withValues(alpha: 0.7)
                            : receivedMetaColor,
                        fontSize: 11,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isPending ? Icons.done : Icons.done_all,
                        size: 14,
                        color: isPending
                            ? colorScheme.onPrimary.withValues(alpha: 0.72)
                            : (isRead
                                  ? colorScheme.tertiary
                                  : colorScheme.onPrimary.withValues(
                                      alpha: 0.72,
                                    )),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: isDownloading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isMe ? colorScheme.onPrimary : receivedMetaColor,
                    ),
                  ),
                )
              : Icon(
                  isDownloaded ? Icons.open_in_new : Icons.download,
                  size: 18,
                  color: isMe
                      ? colorScheme.onPrimary.withValues(alpha: 0.72)
                      : receivedMetaColor,
                ),
          onPressed: isDownloading ? null : onAction,
          tooltip: isDownloaded ? 'Open' : 'Download',
        ),
      ],
    );
  }

  Future<void> _handleFileAction({
    required String messageId,
    required String url,
    required String fileName,
    required String mimeType,
    required int fileSize,
    required bool isDownloaded,
    required String? localPath,
  }) async {
    if (isDownloaded && localPath != null) {
      final result = await OpenFilex.open(localPath);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } else {
      try {
        await widget.downloadService.downloadFile(
          messageId: messageId,
          url: url,
          fileName: fileName,
          mimeType: mimeType,
          fileSize: fileSize,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: ${e.toString()}')),
          );
        }
      }
    }
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
    final value = size < 10 && unit > 0
        ? size.toStringAsFixed(1)
        : size.toStringAsFixed(0);
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
          return const Text('Loading...', style: TextStyle(fontSize: 12));
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

class _ReplyDraft {
  final String messageId;
  final String senderId;
  final String senderName;
  final String previewText;

  _ReplyDraft({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.previewText,
  });
}

class _PendingTextMessage {
  final String id;
  final String text;
  final DateTime createdAt;

  _PendingTextMessage({
    required this.id,
    required this.text,
    required this.createdAt,
  });
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
