import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_streams.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:mime/mime.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../models/chat_sticker.dart';
import '../services/notification_service.dart';
import '../services/video_cache_service.dart';
import '../services/presence_service.dart';
import '../services/chat_service_e2ee.dart';
import '../services/user_cache_service.dart';
import '../services/file_download_service.dart';
import '../services/message_cache_service.dart';
import '../services/theme_service.dart';
import '../services/giphy_service.dart';
import '../widgets/chat_message_text.dart';
import '../widgets/sticker_gif_picker.dart';
import 'user_profile_view_screen.dart';
import 'image_viewer_screen.dart';
import 'video_viewer_screen.dart';
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

enum _RecorderMode { audio, video }

const List<String> _emojiFontFallback = <String>[
  'Segoe UI Emoji',
  'Noto Color Emoji',
  'Apple Color Emoji',
];

TextStyle _withEmojiFallback(TextStyle style) {
  final fallback = <String>{
    ...(style.fontFamilyFallback ?? const <String>[]),
    ..._emojiFontFallback,
  }.toList();
  return style.copyWith(fontFamilyFallback: fallback);
}

bool _looksLikeGifUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  final decoded = Uri.decodeFull(lower);
  if (lower.contains('.gif') ||
      decoded.contains('.gif') ||
      lower.contains('.gifv') ||
      decoded.contains('.gifv') ||
      lower.contains('giphy.com/media/') ||
      lower.contains('media.giphy.com/') ||
      lower.contains('i.giphy.com/') ||
      lower.contains('giphy.com/') ||
      lower.contains('media.tenor.com/') ||
      lower.contains('tenor.com/view/')) {
    return true;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  for (final key in const ['format', 'fm', 'ext', 'content', 'type']) {
    final value = uri.queryParameters[key]?.trim().toLowerCase() ?? '';
    if (value.contains('gif')) return true;
  }
  return false;
}

bool _looksLikeImageUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  final decoded = Uri.decodeFull(lower);
  return lower.contains('.gif') ||
      lower.contains('.gifv') ||
      lower.contains('.png') ||
      lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.webp') ||
      decoded.contains('.gif') ||
      decoded.contains('.gifv') ||
      decoded.contains('.png') ||
      decoded.contains('.jpg') ||
      decoded.contains('.jpeg') ||
      decoded.contains('.webp');
}

class _ImprovedChatScreenState extends State<ImprovedChatScreen>
    with WidgetsBindingObserver {
  static const ResolutionPreset _videoMessageResolution =
      ResolutionPreset.medium;
  static const int _videoMessageFps = 24;
  static const int _videoMessageBitrate = 1200000;
  static const int _videoMessageAudioBitrate = 64000;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  final NotificationService _notificationService = NotificationService();
  final UserCacheService _userCache = UserCacheService();
  final FileDownloadService _downloadService = FileDownloadService();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  static const bool _messagesListReversed = true;
  static const double _autoScrollThreshold = 110;
  static const double _scrollButtonThreshold = 320;

  String? _conversationId;
  Map<String, dynamic>? _recipientData;
  bool _hasMessages = false;
  String? _initError;
  bool _sendPulse = false;
  bool _showScrollToBottomButton = false;
  bool _isRecordingAudio = false;
  bool _isAudioRecordingLocked = false;
  int _audioRecordingSeconds = 0;
  Timer? _audioRecordingTimer;
  double? _recorderPressStartDy;
  CameraController? _videoRecorderController;
  List<CameraDescription> _videoCameras = const [];
  int _videoCameraIndex = 0;
  bool _showVideoRecorderOverlay = false;
  bool _isVideoRecorderInitializing = false;
  bool _isRecordingVideo = false;
  int _videoRecordingSeconds = 0;
  Timer? _videoRecordingTimer;
  String? _videoRecorderError;
  _RecorderMode _recorderMode = _RecorderMode.audio;
  _ReplyDraft? _replyDraft;
  final List<_PendingTextMessage> _pendingTextMessages = [];
  final List<_PendingUpload> _pendingUploads = [];
  final Map<String, String> _optimisticTextByMessageId = {};

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
    final distance = _distanceFromBottom();
    final shouldShow = distance > _scrollButtonThreshold;
    if (!mounted || shouldShow == _showScrollToBottomButton) return;
    setState(() {
      _showScrollToBottomButton = shouldShow;
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final distance = _distanceFromBottom();
    return distance <= _autoScrollThreshold;
  }

  double _distanceFromBottom() {
    if (!_scrollController.hasClients) return 0;
    if (_messagesListReversed) {
      return _scrollController.offset;
    }
    return _scrollController.position.maxScrollExtent -
        _scrollController.offset;
  }

  void _listenToConversationMetadata() {
    _firestore
        .collection('conversations')
        .doc(_conversationId)
        .safeSnapshots()
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
    _audioRecordingTimer?.cancel();
    _videoRecordingTimer?.cancel();
    if (_isRecordingAudio) {
      unawaited(_audioRecorder.stop());
    }
    if (_isRecordingVideo) {
      unawaited(_videoRecorderController?.stopVideoRecording());
    }
    unawaited(_audioRecorder.dispose());
    unawaited(_videoRecorderController?.dispose());
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
    _firestore
        .collection('users')
        .doc(widget.recipientId)
        .safeSnapshots()
        .listen((snapshot) {
          if (snapshot.exists && mounted) {
            setState(() {
              _recipientData = snapshot.data()!;
            });
            _userCache.mergeUserData(widget.recipientId, snapshot.data()!);
          }
        });
  }

  Future<void> _sendMessage({
    String? overrideText,
    String messageType = 'text',
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || _conversationId == null) return;

    final messageText = (overrideText ?? _messageController.text).trim();
    if (messageText.isEmpty) return;
    final replyDraft = _replyDraft;
    final trackPending = messageType == 'text';
    final messageId = _firestore
        .collection('conversations')
        .doc(_conversationId)
        .collection('messages')
        .doc()
        .id;
    final pending = _PendingTextMessage(
      id: messageId,
      text: messageText,
      createdAt: DateTime.now(),
    );

    try {
      if (overrideText == null) {
        _messageController.clear();
        _messageFocusNode.requestFocus();
      }
      if (mounted) {
        setState(() {
          _sendPulse = true;
          _replyDraft = null;
          if (trackPending) {
            _pendingTextMessages.add(pending);
            _optimisticTextByMessageId[messageId] = messageText;
          }
        });
      }
      Timer(const Duration(seconds: 45), () {
        if (!mounted) return;
        if (trackPending) {
          setState(() {
            _optimisticTextByMessageId.remove(messageId);
          });
        }
      });
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
        messageId: messageId,
        replyToMessageId: replyDraft?.messageId,
        replyToText: replyDraft?.previewText,
        replyToSenderId: replyDraft?.senderId,
        messageType: messageType,
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
        debugPrint('Error sending notification: $notificationError');
      }

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        if (overrideText == null && _messageController.text.trim().isEmpty) {
          _messageController.text = messageText;
          _messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: _messageController.text.length),
          );
        }
        setState(() {
          _replyDraft = replyDraft;
          if (trackPending) {
            _pendingTextMessages.removeWhere((item) => item.id == messageId);
            _optimisticTextByMessageId.remove(messageId);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _sendSticker(ChatSticker sticker) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || _conversationId == null) return;
    final fallback = sticker.fallback.trim();
    if (fallback.isEmpty) return;

    try {
      _messageFocusNode.requestFocus();
      await _chatService.sendStickerMessage(
        conversationId: _conversationId!,
        recipientId: widget.recipientId,
        stickerText: fallback,
        stickerId: sticker.id,
        stickerUrl: sticker.imageUrl,
        stickerPack: sticker.pack,
        stickerLabel: sticker.label,
      );
      try {
        final senderName = currentUser.displayName ?? 'Someone';
        await _notificationService.sendMessageNotification(
          recipientId: widget.recipientId,
          senderName: senderName,
          messageText: 'Sent a sticker',
          conversationId: _conversationId,
        );
      } catch (notificationError) {
        debugPrint('Error sending notification: $notificationError');
      }
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send sticker: ${e.toString()}')),
      );
    }
  }

  Future<void> _sendGif(GiphyGif gif) async {
    final sticker = ChatSticker(
      id: 'gif_${gif.id}',
      imageUrl: gif.fullUrl,
      fallback: '[GIF]',
      pack: 'giphy',
      label: 'GIF',
    );
    await _sendSticker(sticker);
  }

  Future<void> _showStickerGifPicker() async {
    if (_conversationId == null) return;
    final result = await StickerGifPicker.show(context);
    if (!mounted || result == null) return;
    if (result is ChatSticker) {
      await _sendSticker(result);
    } else if (result is GiphyGif) {
      await _sendGif(result);
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

      final target = _messagesListReversed
          ? _scrollController.position.minScrollExtent
          : _scrollController.position.maxScrollExtent;
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
                    optimisticTextByMessageId: _optimisticTextByMessageId,
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
                if (_showVideoRecorderOverlay ||
                    _isVideoRecorderInitializing ||
                    _isRecordingVideo)
                  _buildVideoRecorderOverlay(),
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
            errorBuilder: (_, error, stackTrace) => placeholder,
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
          placeholder: (_, url) => placeholder,
          errorWidget: (_, url, error) => placeholder,
          fadeInDuration: const Duration(milliseconds: 150),
          fadeOutDuration: const Duration(milliseconds: 150),
        ),
      ),
    );
  }

  String _formatRecordingDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startAudioRecording() async {
    if (_conversationId == null || _isRecordingAudio || _isRecordingVideo) {
      return;
    }
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
      }
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final path = p.join(
        tempDir.path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _isRecordingAudio = true;
        _isAudioRecordingLocked = false;
        _audioRecordingSeconds = 0;
      });

      _audioRecordingTimer?.cancel();
      _audioRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecordingAudio) return;
        setState(() {
          _audioRecordingSeconds++;
        });
      });

      HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
    }
  }

  void _lockAudioRecording() {
    if (!_isRecordingAudio || _isAudioRecordingLocked) return;
    setState(() {
      _isAudioRecordingLocked = true;
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _stopAudioRecording({required bool send}) async {
    if (!_isRecordingAudio) return;

    _audioRecordingTimer?.cancel();
    final recordedSeconds = _audioRecordingSeconds;
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (_) {
      path = null;
    }

    if (!mounted) return;
    setState(() {
      _isRecordingAudio = false;
      _isAudioRecordingLocked = false;
      _audioRecordingSeconds = 0;
      _recorderPressStartDy = null;
    });

    if (!send || path == null || path.trim().isEmpty) return;

    final file = File(path);
    if (!await file.exists()) return;
    if (recordedSeconds < 1) {
      try {
        await file.delete();
      } catch (_) {}
      return;
    }

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    await _sendLocalFile(
      filePath: path,
      fileName: 'voice_$stamp.m4a',
      mimeType: 'audio/aac',
      notificationText: 'Sent a voice message',
    );
  }

  Future<void> _ensureVideoRecorderReady() async {
    if (_videoRecorderController?.value.isInitialized == true) {
      return;
    }
    if (_isVideoRecorderInitializing) return;

    setState(() {
      _isVideoRecorderInitializing = true;
      _showVideoRecorderOverlay = true;
      _videoRecorderError = null;
    });

    try {
      _videoCameras = await availableCameras();
      if (_videoCameras.isEmpty) {
        throw Exception('No camera available');
      }

      if (_videoCameraIndex >= _videoCameras.length) {
        _videoCameraIndex = 0;
      }

      final nextController = CameraController(
        _videoCameras[_videoCameraIndex],
        _videoMessageResolution,
        enableAudio: true,
        fps: _videoMessageFps,
        videoBitrate: _videoMessageBitrate,
        audioBitrate: _videoMessageAudioBitrate,
      );
      await nextController.initialize();

      final previous = _videoRecorderController;
      if (!mounted) {
        await nextController.dispose();
        return;
      }

      setState(() {
        _videoRecorderController = nextController;
        _isVideoRecorderInitializing = false;
        _videoRecorderError = null;
      });
      await previous?.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVideoRecorderInitializing = false;
        _videoRecorderError = 'Could not open camera: $e';
      });
    }
  }

  Future<void> _switchVideoRecorderCamera() async {
    if (_isVideoRecorderInitializing || _isRecordingVideo) return;
    if (_videoCameras.length < 2) return;

    final nextIndex = (_videoCameraIndex + 1) % _videoCameras.length;
    setState(() {
      _isVideoRecorderInitializing = true;
      _videoRecorderError = null;
    });

    try {
      final nextController = CameraController(
        _videoCameras[nextIndex],
        _videoMessageResolution,
        enableAudio: true,
        fps: _videoMessageFps,
        videoBitrate: _videoMessageBitrate,
        audioBitrate: _videoMessageAudioBitrate,
      );
      await nextController.initialize();

      final previous = _videoRecorderController;
      if (!mounted) {
        await nextController.dispose();
        return;
      }

      setState(() {
        _videoRecorderController = nextController;
        _videoCameraIndex = nextIndex;
        _isVideoRecorderInitializing = false;
      });
      await previous?.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVideoRecorderInitializing = false;
        _videoRecorderError = 'Could not switch camera: $e';
      });
    }
  }

  Future<void> _startInlineVideoRecording() async {
    if (_conversationId == null || _isRecordingVideo || _isRecordingAudio) {
      return;
    }

    await _ensureVideoRecorderReady();
    final controller = _videoRecorderController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording();

      if (!mounted) return;
      setState(() {
        _isRecordingVideo = true;
        _videoRecordingSeconds = 0;
        _showVideoRecorderOverlay = true;
        _videoRecorderError = null;
      });

      _videoRecordingTimer?.cancel();
      _videoRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecordingVideo) return;
        setState(() {
          _videoRecordingSeconds++;
        });
      });

      HapticFeedback.lightImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _videoRecorderError = 'Could not start video recording: $e';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start recording: $e')));
    }
  }

  Future<void> _stopInlineVideoRecording({required bool send}) async {
    if (!_isRecordingVideo) {
      if (!send && mounted) {
        setState(() {
          _showVideoRecorderOverlay = false;
        });
      }
      return;
    }

    _videoRecordingTimer?.cancel();
    final recordedSeconds = _videoRecordingSeconds;
    XFile? file;
    try {
      file = await _videoRecorderController?.stopVideoRecording();
    } catch (_) {
      file = null;
    }

    if (!mounted) return;
    setState(() {
      _isRecordingVideo = false;
      _videoRecordingSeconds = 0;
      _showVideoRecorderOverlay = false;
    });

    if (file == null || file.path.trim().isEmpty) return;

    final recordedFile = File(file.path);
    if (!send || recordedSeconds < 1) {
      try {
        if (await recordedFile.exists()) {
          await recordedFile.delete();
        }
      } catch (_) {}
      return;
    }

    if (!await recordedFile.exists()) return;

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    await _sendLocalFile(
      filePath: file.path,
      fileName: 'video_$stamp.mp4',
      mimeType: lookupMimeType(file.path) ?? 'video/mp4',
      notificationText: 'Sent a video',
    );
  }

  Future<void> _recordVideoAndSend() async {
    await _startInlineVideoRecording();
  }

  Future<void> _closeVideoRecorderOverlay() async {
    if (_isRecordingVideo) {
      await _stopInlineVideoRecording(send: false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _showVideoRecorderOverlay = false;
      _videoRecorderError = null;
    });
  }

  Widget _buildVideoRecorderOverlay() {
    final controller = _videoRecorderController;
    final canSwitch = _videoCameras.length > 1 && !_isRecordingVideo;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => unawaited(_closeVideoRecorderOverlay()),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                    ),
                    if (_isRecordingVideo)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'REC ${_formatRecordingDuration(_videoRecordingSeconds)}',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      onPressed: canSwitch
                          ? () => unawaited(_switchVideoRecorderCamera())
                          : null,
                      icon: const Icon(
                        Icons.cameraswitch_outlined,
                        color: Colors.white,
                      ),
                      tooltip: 'Switch camera',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      color: Colors.black,
                      child: _isVideoRecorderInitializing
                          ? const Center(child: CircularProgressIndicator())
                          : (_videoRecorderError != null
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      child: Text(
                                        _videoRecorderError!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  )
                                : (controller == null ||
                                          !controller.value.isInitialized
                                      ? const Center(
                                          child: Text(
                                            'Camera not ready',
                                            style: TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                        )
                                      : FittedBox(
                                          fit: BoxFit.cover,
                                          child: SizedBox(
                                            width:
                                                controller
                                                    .value
                                                    .previewSize
                                                    ?.height ??
                                                1080,
                                            height:
                                                controller
                                                    .value
                                                    .previewSize
                                                    ?.width ??
                                                1920,
                                            child: CameraPreview(controller),
                                          ),
                                        ))),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Row(
                  children: [
                    if (_isRecordingVideo)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              unawaited(_stopInlineVideoRecording(send: false)),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Discard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white30),
                          ),
                        ),
                      ),
                    if (_isRecordingVideo) const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isRecordingVideo
                            ? () => unawaited(
                                _stopInlineVideoRecording(send: true),
                              )
                            : () => unawaited(_startInlineVideoRecording()),
                        icon: Icon(
                          _isRecordingVideo
                              ? Icons.send_rounded
                              : Icons.fiber_manual_record,
                        ),
                        label: Text(_isRecordingVideo ? 'Send' : 'Record'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isRecordingVideo
                              ? Theme.of(context).colorScheme.primary
                              : Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleRecorderTap() {
    if (_recorderMode == _RecorderMode.audio &&
        _isRecordingAudio &&
        _isAudioRecordingLocked) {
      unawaited(_stopAudioRecording(send: true));
      return;
    }

    if (_recorderMode == _RecorderMode.video && _isRecordingVideo) {
      unawaited(_stopInlineVideoRecording(send: true));
      return;
    }

    _toggleRecorderMode();
  }

  void _handleRecorderLongPressStart(LongPressStartDetails details) {
    _recorderPressStartDy = details.globalPosition.dy;
    if (_recorderMode == _RecorderMode.audio) {
      unawaited(_startAudioRecording());
      return;
    }
    if (_recorderMode == _RecorderMode.video) {
      unawaited(_startInlineVideoRecording());
    }
  }

  void _handleRecorderLongPressMove(LongPressMoveUpdateDetails details) {
    if (_recorderMode != _RecorderMode.audio ||
        !_isRecordingAudio ||
        _isAudioRecordingLocked) {
      return;
    }
    final startDy = _recorderPressStartDy;
    if (startDy == null) return;
    final dragDistance = startDy - details.globalPosition.dy;
    if (dragDistance >= 56) {
      _lockAudioRecording();
    }
  }

  void _handleRecorderLongPressEnd(LongPressEndDetails details) {
    _recorderPressStartDy = null;
    if (_recorderMode == _RecorderMode.audio && !_isAudioRecordingLocked) {
      unawaited(_stopAudioRecording(send: true));
    }
  }

  void _handleRecorderLongPressCancel() {
    _recorderPressStartDy = null;
    if (_recorderMode == _RecorderMode.audio && !_isAudioRecordingLocked) {
      unawaited(_stopAudioRecording(send: false));
    }
  }

  void _toggleRecorderMode() {
    if (_isRecordingAudio ||
        _isRecordingVideo ||
        _isVideoRecorderInitializing) {
      return;
    }
    setState(() {
      _recorderMode = _recorderMode == _RecorderMode.audio
          ? _RecorderMode.video
          : _RecorderMode.audio;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _sendLocalFile({
    required String filePath,
    required String fileName,
    String? mimeType,
    String notificationText = 'Sent a file',
    String? caption,
  }) async {
    if (_conversationId == null) return;

    String? pendingId;
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access selected file')),
          );
        }
        return;
      }

      final detectedMime = (mimeType != null && mimeType.trim().isNotEmpty)
          ? mimeType.trim()
          : (lookupMimeType(filePath) ?? 'application/octet-stream');
      final trimmedCaption = caption?.trim();
      final fileSize = await file.length();

      final upload = _chatService.startFileUpload(
        conversationId: _conversationId!,
        filePath: filePath,
        fileName: fileName,
        mimeType: detectedMime,
      );
      pendingId = upload.messageId;

      final pending = _PendingUpload(
        id: upload.messageId,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: detectedMime,
        progress: 0,
        createdAt: DateTime.now(),
        caption: trimmedCaption,
      );
      pending.task = upload.task;

      if (mounted) {
        setState(() {
          _pendingUploads.add(pending);
        });
      }
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
        fileName: fileName,
        fileSize: fileSize,
        mimeType: upload.contentType,
        caption: trimmedCaption,
      );

      try {
        final currentUser = _auth.currentUser;
        final senderName = currentUser?.displayName ?? 'Someone';
        await _notificationService.sendMessageNotification(
          recipientId: widget.recipientId,
          senderName: senderName,
          messageText: notificationText,
          conversationId: _conversationId,
        );
      } catch (notificationError) {
        debugPrint('Error sending notification: $notificationError');
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

  Widget _buildMessageInput() {
    final colorScheme = Theme.of(context).colorScheme;
    final isAnyRecording = _isRecordingAudio || _isRecordingVideo;

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
            if (_isRecordingAudio)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.fiber_manual_record,
                      size: 14,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isAudioRecordingLocked
                            ? 'Recording ${_formatRecordingDuration(_audioRecordingSeconds)} - locked'
                            : 'Recording ${_formatRecordingDuration(_audioRecordingSeconds)} - slide up to lock',
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_isAudioRecordingLocked) ...[
                      IconButton(
                        onPressed: () =>
                            unawaited(_stopAudioRecording(send: false)),
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: colorScheme.onErrorContainer,
                        ),
                        tooltip: 'Discard',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: () =>
                            unawaited(_stopAudioRecording(send: true)),
                        icon: Icon(
                          Icons.send_rounded,
                          size: 18,
                          color: colorScheme.onErrorContainer,
                        ),
                        tooltip: 'Send',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
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
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      onPressed: _showAttachmentSheet,
                      icon: const Icon(Icons.attach_file),
                      tooltip: 'Attach',
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Material(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                  shape: const CircleBorder(),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      onPressed: _showStickerGifPicker,
                      icon: const Icon(Icons.gif_box_outlined),
                      tooltip: 'Stickers & GIFs',
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      style: _withEmojiFallback(
                        const TextStyle(fontSize: 14.5, height: 1.35),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isCollapsed: true,
                      ),
                      minLines: 1,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _messageController,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    final showRecorder = isAnyRecording || !hasText;
                    if (showRecorder) {
                      return GestureDetector(
                        onTap: _handleRecorderTap,
                        onLongPressStart: _handleRecorderLongPressStart,
                        onLongPressMoveUpdate: _handleRecorderLongPressMove,
                        onLongPressEnd: _handleRecorderLongPressEnd,
                        onLongPressCancel: _handleRecorderLongPressCancel,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: isAnyRecording
                              ? colorScheme.error
                              : colorScheme.surfaceContainerHighest,
                          child: Icon(
                            isAnyRecording
                                ? (_isAudioRecordingLocked || _isRecordingVideo
                                      ? Icons.send_rounded
                                      : Icons.stop)
                                : (_recorderMode == _RecorderMode.audio
                                      ? Icons.mic
                                      : Icons.videocam),
                            size: 20,
                            color: isAnyRecording
                                ? colorScheme.onError
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    final canSend = _conversationId != null;
                    return AnimatedScale(
                      scale: _sendPulse ? 0.86 : 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutBack,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: canSend
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        child: IconButton(
                          icon: Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: canSend
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                          onPressed: canSend ? _sendMessage : null,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
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
    final isMobile = Platform.isAndroid || Platform.isIOS;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (isMobile)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickAndSendFromGallery();
                },
              ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('File'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendFile(type: FileType.any);
              },
            ),
            if (isMobile)
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Location'),
                onTap: () {
                  Navigator.pop(context);
                  _sendLocation();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendFromGallery() async {
    if (_conversationId == null) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      await _pickAndSendFile(explicitPath: picked.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open gallery')),
        );
      }
    }
  }

  Future<void> _sendLocation() async {
    if (_conversationId == null) return;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission denied')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission permanently denied. Enable it in settings.',
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Getting location…')),
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final lat = position.latitude.toStringAsFixed(6);
      final lng = position.longitude.toStringAsFixed(6);
      await _sendMessage(
        overrideText: 'loc:$lat,$lng',
        messageType: 'location',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    }
  }

  Future<_MediaComposerResult?> _showMediaComposer(List<XFile> files) async {
    final captionController = TextEditingController();
    final result = await showModalBottomSheet<_MediaComposerResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final insets = MediaQuery.of(sheetContext).viewInsets;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, insets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${files.length} selected',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final path = files[index].path;
                      final mimeType = lookupMimeType(path) ?? '';
                      final isVideo = mimeType.toLowerCase().startsWith(
                        'video/',
                      );

                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(path),
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 90,
                                    height: 90,
                                    color: Colors.grey[300],
                                    alignment: Alignment.center,
                                    child: Icon(
                                      isVideo ? Icons.videocam : Icons.image,
                                    ),
                                  ),
                            ),
                          ),
                          if (isVideo)
                            const Positioned(
                              right: 6,
                              bottom: 6,
                              child: Icon(
                                Icons.play_circle_fill,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: captionController,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Add caption',
                    hintText: 'Write a message...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        sheetContext,
                        _MediaComposerResult(
                          files: files,
                          caption: captionController.text,
                        ),
                      );
                    },
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      files.length == 1
                          ? 'Send media'
                          : 'Send ${files.length} items',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    captionController.dispose();
    return result;
  }

  Future<void> _pickAndSendFile({
    FileType type = FileType.any,
    String? explicitPath,
  }) async {
    if (_conversationId == null) return;

    String? path;
    String? name;

    if (explicitPath != null) {
      path = explicitPath.trim();
      if (path.isNotEmpty) {
        name = p.basename(path).trim();
      }
    } else {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
        type: type,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final pickedPath = file.path?.trim() ?? '';
      if (pickedPath.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access selected file')),
          );
        }
        return;
      }
      path = pickedPath;
      name = file.name.trim();
    }

    if (path == null || path.isEmpty) return;
    final fileName = (name == null || name.isEmpty)
        ? p.basename(path).trim().isEmpty
              ? 'file_${DateTime.now().millisecondsSinceEpoch}'
              : p.basename(path)
        : name;

    await _sendLocalFile(
      filePath: path,
      fileName: fileName,
      mimeType: lookupMimeType(path) ?? 'application/octet-stream',
      notificationText: 'Sent a file',
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
  final Map<String, String> optimisticTextByMessageId;
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
    required this.optimisticTextByMessageId,
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
  static final Map<String, QuerySnapshot> _sessionMessageCache = {};
  static final Map<String, List<Map<String, dynamic>>>
  _sessionPersistedMessages = {};
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MessageCacheService _messageCache = MessageCacheService();
  final Map<String, String> _decryptedCache = {};
  final Map<String, Future<String>> _decryptFutureCache = {};
  final Map<String, String> _decryptInputSignature = {};
  final Set<String> _animatedMessageIds = {};
  final Map<String, Map<String, dynamic>> _persistedById = {};
  bool _animationCachePrimed = false;
  int _lastTotalItems = 0;
  bool _pendingInitialBottomSnap = true;
  bool _markReadInFlight = false;
  QuerySnapshot? _cachedMessagesSnapshot;
  List<Map<String, dynamic>> _persistedMessages = [];
  Timer? _persistentCacheDebounce;
  bool _cacheHydrated = false;
  bool _persistentCacheHydrated = false;
  String? _cacheConversationId;
  String? _persistentConversationId;
  List<QueryDocumentSnapshot> _latestLiveMessages = const [];
  String? _latestLiveMessagesOwnerId;
  String _lastPersistedPayloadSignature = '';

  @override
  void initState() {
    super.initState();
    _hydrateLocalMessages();
    _hydratePersistentMessages();
  }

  @override
  void didUpdateWidget(covariant _MessagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _resetTransientCaches();
      _hydrateLocalMessages();
      _hydratePersistentMessages();
    }
  }

  void _resetTransientCaches() {
    _decryptedCache.clear();
    _decryptFutureCache.clear();
    _decryptInputSignature.clear();
    _animatedMessageIds.clear();
    _persistedById.clear();
    _latestLiveMessages = const [];
    _latestLiveMessagesOwnerId = null;
    _animationCachePrimed = false;
    _lastTotalItems = 0;
    _pendingInitialBottomSnap = true;
    _markReadInFlight = false;
    _cachedMessagesSnapshot = null;
    _persistedMessages = [];
    _cacheHydrated = widget.conversationId == null;
    _persistentCacheHydrated = widget.conversationId == null;
    _lastPersistedPayloadSignature = '';
  }

  void _hydrateLocalMessages() {
    final conversationId = widget.conversationId;
    _cacheConversationId = conversationId;
    _cachedMessagesSnapshot = conversationId == null
        ? null
        : _sessionMessageCache[conversationId];
    _cacheHydrated = conversationId == null || _cachedMessagesSnapshot != null;
    if (conversationId == null) return;
    unawaited(_loadCachedMessages(conversationId));
  }

  void _hydratePersistentMessages() {
    final conversationId = widget.conversationId;
    _persistentConversationId = conversationId;
    final sessionCached = conversationId == null
        ? null
        : _sessionPersistedMessages[conversationId];
    if (sessionCached != null && sessionCached.isNotEmpty) {
      final seeded = _clonePersistedMessages(sessionCached);
      final byId = _indexPersistedMessages(seeded);
      _persistedMessages = seeded;
      _persistedById
        ..clear()
        ..addAll(byId);
      _persistentCacheHydrated = true;
      _lastPersistedPayloadSignature = _persistedPayloadSignature(seeded);
    } else {
      _persistedMessages = [];
      _persistedById.clear();
      _persistentCacheHydrated = conversationId == null;
      _lastPersistedPayloadSignature = 'empty';
    }
    if (conversationId == null) return;
    unawaited(_loadPersistedMessages(conversationId));
  }

  Future<void> _loadCachedMessages(String conversationId) async {
    final cached = await widget.chatService.getCachedMessages(conversationId);
    if (!mounted || _cacheConversationId != conversationId) return;
    if (cached != null && cached.docs.isNotEmpty) {
      _sessionMessageCache[conversationId] = cached;
    }
    setState(() {
      if (cached != null) {
        _cachedMessagesSnapshot = cached;
      }
      _cacheHydrated = true;
    });
  }

  Future<void> _loadPersistedMessages(String conversationId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      if (!mounted || _persistentConversationId != conversationId) return;
      setState(() {
        _persistentCacheHydrated = true;
      });
      return;
    }
    final cached = await _messageCache.loadConversationMessages(
      uid,
      conversationId,
    );
    if (!mounted || _persistentConversationId != conversationId) return;

    final seeded = _clonePersistedMessages(cached);
    final byId = _indexPersistedMessages(seeded);
    final signature = _persistedPayloadSignature(seeded);

    if (_lastPersistedPayloadSignature == signature &&
        _persistentCacheHydrated) {
      return;
    }

    setState(() {
      _persistedMessages = seeded;
      _persistedById
        ..clear()
        ..addAll(byId);
      _persistentCacheHydrated = true;
      _lastPersistedPayloadSignature = signature;
      _sessionPersistedMessages[conversationId] = seeded;
    });
  }

  @override
  void dispose() {
    _persistentCacheDebounce?.cancel();
    super.dispose();
  }

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

  List<Map<String, dynamic>> _clonePersistedMessages(
    List<Map<String, dynamic>> source,
  ) {
    return source.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Map<String, Map<String, dynamic>> _indexPersistedMessages(
    List<Map<String, dynamic>> items,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final id = item['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      byId[id] = item;
    }
    return byId;
  }

  String _persistedTextForMessage(String messageId) {
    return _persistedById[messageId]?['text']?.toString().trim() ?? '';
  }

  String _persistedPayloadSignature(List<Map<String, dynamic>> payload) {
    var hash = 17;
    for (final item in payload) {
      hash = 37 * hash + (item['id']?.toString().hashCode ?? 0);
      hash = 37 * hash + (item['timestampMs']?.hashCode ?? 0);
      hash = 37 * hash + (item['type']?.toString().hashCode ?? 0);
      hash = 37 * hash + (item['text']?.toString().hashCode ?? 0);
      hash = 37 * hash + (item['read'] == true ? 1 : 0);
    }
    return '${payload.length}:$hash';
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
      _pendingInitialBottomSnap = true;
      return;
    }

    final firstLoad = _pendingInitialBottomSnap || _lastTotalItems == 0;
    final hasNewItems = totalItems > _lastTotalItems;
    final shouldAutoScroll =
        firstLoad || (hasNewItems && widget.shouldAutoScroll());
    _lastTotalItems = totalItems;
    if (firstLoad) {
      _pendingInitialBottomSnap = false;
    }

    if (!shouldAutoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onAutoScrollToBottom();
      if (firstLoad) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onAutoScrollToBottom();
        });
      }
    });
  }

  void _schedulePersistedCacheWriteFromLive() {
    final conversationId = widget.conversationId;
    final uid = _latestLiveMessagesOwnerId;
    if (conversationId == null || uid == null || uid.trim().isEmpty) return;

    final docs = List<QueryDocumentSnapshot>.from(_latestLiveMessages);
    _persistentCacheDebounce?.cancel();
    _persistentCacheDebounce = Timer(
      const Duration(milliseconds: 360),
      () async {
        final payload = <Map<String, dynamic>>[];
        for (final doc in docs) {
          final data = doc.data();
          if (data is! Map) continue;
          final map = Map<String, dynamic>.from(data);
          final cached = _buildPersistableMessage(id: doc.id, message: map);
          if (cached.isEmpty) continue;
          payload.add(cached);
        }

        if (payload.isEmpty) {
          return;
        }
        final signature = _persistedPayloadSignature(payload);
        if (signature == _lastPersistedPayloadSignature) {
          return;
        }

        await _messageCache.saveConversationMessages(
          uid,
          conversationId,
          payload,
        );
        if (!mounted || _persistentConversationId != conversationId) return;

        final seeded = _clonePersistedMessages(payload);
        final byId = _indexPersistedMessages(seeded);

        setState(() {
          _persistedMessages = seeded;
          _persistedById
            ..clear()
            ..addAll(byId);
          _persistentCacheHydrated = true;
          _lastPersistedPayloadSignature = signature;
          _sessionPersistedMessages[conversationId] = seeded;
        });
      },
    );
  }

  void _schedulePersistedCacheClear(String uid) {
    final conversationId = widget.conversationId;
    if (conversationId == null || uid.trim().isEmpty) return;

    _persistentCacheDebounce?.cancel();
    _persistentCacheDebounce = Timer(
      const Duration(milliseconds: 260),
      () async {
        await _messageCache.clearConversation(uid, conversationId);
        if (!mounted || _persistentConversationId != conversationId) return;
        setState(() {
          _persistedMessages = [];
          _persistedById.clear();
          _persistentCacheHydrated = true;
          _lastPersistedPayloadSignature = 'empty';
          _sessionPersistedMessages.remove(conversationId);
        });
      },
    );
  }

  Map<String, dynamic> _buildPersistableMessage({
    required String id,
    required Map<String, dynamic> message,
  }) {
    final senderId = message['senderId']?.toString().trim() ?? '';
    if (senderId.isEmpty) return const {};

    final type = message['type']?.toString().trim() ?? 'text';
    final timestamp =
        (message['timestamp'] as Timestamp?) ??
        (message['clientTimestamp'] as Timestamp?);
    final readAt = message['readAt'] as Timestamp?;
    final reactions = _extractReactions(message);

    final item = <String, dynamic>{
      'id': id,
      'type': type,
      'senderId': senderId,
    };
    if (timestamp != null) {
      item['timestampMs'] = timestamp.millisecondsSinceEpoch;
    }
    item['read'] = message['read'] == true;
    if (readAt != null) {
      item['readAtMs'] = readAt.millisecondsSinceEpoch;
    }
    if (reactions.isNotEmpty) {
      item['reactions'] = reactions.map(
        (uid, emojis) => MapEntry(uid, emojis.toList()),
      );
    }

    final caption = message['caption']?.toString().trim();
    if (caption != null && caption.isNotEmpty) {
      item['caption'] = caption;
    }

    if (type == 'file') {
      item['fileName'] = message['fileName']?.toString().trim() ?? 'File';
      item['fileSize'] = (message['fileSize'] is num)
          ? (message['fileSize'] as num).toInt()
          : int.tryParse(message['fileSize']?.toString() ?? '') ?? 0;
      final fileUrl = message['fileUrl']?.toString().trim() ?? '';
      if (fileUrl.isNotEmpty) {
        item['fileUrl'] = fileUrl;
      }
      final mimeType = message['mimeType']?.toString().trim() ?? '';
      if (mimeType.isNotEmpty) {
        item['mimeType'] = mimeType;
      }
      return item;
    }

    final replyToText = message['replyToText']?.toString().trim() ?? '';
    if (replyToText.isNotEmpty) {
      item['replyToText'] = replyToText;
    }
    final replyToSenderId = message['replyToSenderId']?.toString().trim() ?? '';
    if (replyToSenderId.isNotEmpty) {
      item['replyToSenderId'] = replyToSenderId;
    }
    if (message['edited'] is bool) {
      item['edited'] = message['edited'] as bool;
    }

    if (message['callSummary'] is Map) {
      final callSummary = Map<String, dynamic>.from(
        message['callSummary'] as Map,
      );
      if (callSummary.isNotEmpty) {
        item['callSummary'] = callSummary;
      }
    }

    if (type == 'sticker') {
      final sticker = message['sticker']?.toString().trim() ?? '';
      if (sticker.isNotEmpty) {
        item['text'] = sticker;
      }
    }

    final decrypted = _decryptedCache[id]?.trim() ?? '';
    final persistedText = _persistedById[id]?['text']?.toString().trim() ?? '';
    final displayText = decrypted.isNotEmpty ? decrypted : persistedText;
    if (displayText.isNotEmpty) {
      item['text'] = displayText;
    }

    if (!item.containsKey('text') && !item.containsKey('callSummary')) {
      return const {};
    }

    return item;
  }

  Timestamp? _timestampFromMs(dynamic value) {
    if (value is int) {
      return Timestamp.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return Timestamp.fromMillisecondsSinceEpoch(value.toInt());
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) return null;
    return Timestamp.fromMillisecondsSinceEpoch(parsed);
  }

  Widget _buildPersistedMessagesList(String currentUserId) {
    final orderedMessages = _persistedMessages.reversed.toList();
    _scheduleAutoScrollIfNeeded(orderedMessages.length);

    return ListView.builder(
      controller: widget.scrollController,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: orderedMessages.length,
      itemBuilder: (context, index) {
        final message = orderedMessages[index];
        final messageId = message['id']?.toString().trim() ?? '';
        if (messageId.isEmpty) return const SizedBox.shrink();

        final isMe = message['senderId']?.toString() == currentUserId;
        final timestamp = _timestampFromMs(message['timestampMs']);
        final isRead = message['read'] == true;
        final readAt = _timestampFromMs(message['readAtMs']);
        final type = message['type']?.toString().trim() ?? 'text';

        if (type == 'file') {
          return _buildFileBubble(
            message,
            isMe,
            timestamp,
            isPending: false,
            isRead: isRead,
            readAt: readAt,
            messageId: messageId,
            key: ValueKey('persisted_file_$messageId'),
          );
        }
        if (type == 'location') {
          final text = message['text']?.toString() ?? '';
          return _buildLocationBubble(
            text,
            isMe,
            timestamp,
            messageId: messageId,
            isPending: false,
            isRead: isRead,
            readAt: readAt,
            key: ValueKey('persisted_loc_$messageId'),
          );
        }

        final text = message['text']?.toString() ?? '';
        final hasCallSummary = message['callSummary'] is Map;
        if (text.trim().isEmpty && !hasCallSummary) {
          return const SizedBox.shrink();
        }

        return _buildMessageBubble(
          text,
          isMe,
          timestamp,
          messageId: messageId,
          messageData: message,
          isPending: false,
          isRead: isRead,
          readAt: readAt,
          key: ValueKey('persisted_msg_$messageId'),
        );
      },
    );
  }

  void _markIncomingMessagesAsRead(
    List<QueryDocumentSnapshot> messages,
    String currentUserId,
  ) {
    if (_markReadInFlight || widget.conversationId == null) return;

    final hasUnreadFromPeer = messages.any((doc) {
      final data = doc.data();
      if (data is! Map) return false;
      final map = Map<String, dynamic>.from(data);
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

  Map<String, Set<String>> _extractReactions(Map<String, dynamic> message) {
    final raw = message['reactions'];
    if (raw is! Map) return const <String, Set<String>>{};
    final result = <String, Set<String>>{};
    raw.forEach((key, value) {
      final uid = key.toString().trim();
      if (uid.isEmpty) return;
      final emojis = <String>{};
      if (value is String) {
        final emoji = value.trim();
        if (emoji.isNotEmpty) emojis.add(emoji);
      } else if (value is List) {
        for (final item in value) {
          final emoji = item?.toString().trim() ?? '';
          if (emoji.isNotEmpty) emojis.add(emoji);
        }
      } else {
        final emoji = value?.toString().trim() ?? '';
        if (emoji.isNotEmpty) emojis.add(emoji);
      }
      if (emojis.isEmpty) return;
      result[uid] = emojis;
    });
    return result;
  }

  String _formatDetailsTime(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';
    final date = timestamp.toDate();
    return DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  Future<void> _toggleReaction({
    required String messageId,
    required Map<String, dynamic> message,
    required String emoji,
  }) async {
    final conversationId = widget.conversationId;
    final currentUserId = _auth.currentUser?.uid;
    if (conversationId == null || currentUserId == null) return;
    final normalizedEmoji = emoji.trim();
    if (normalizedEmoji.isEmpty) return;

    final myReactions = Set<String>.from(
      _extractReactions(message)[currentUserId] ?? const <String>{},
    );
    if (myReactions.contains(normalizedEmoji)) {
      myReactions.remove(normalizedEmoji);
    } else {
      myReactions.add(normalizedEmoji);
    }
    try {
      final ref = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId);

      if (myReactions.isEmpty) {
        await ref.update({'reactions.$currentUserId': FieldValue.delete()});
      } else {
        await ref.set({
          'reactions': {currentUserId: myReactions.toList()},
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save reaction: $e')));
    }
  }

  Future<void> _clearMyReactions({
    required String messageId,
    required String currentUserId,
  }) async {
    final conversationId = widget.conversationId;
    if (conversationId == null) return;
    final ref = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);
    await ref.update({'reactions.$currentUserId': FieldValue.delete()});
  }

  void _handleDoubleTapReaction({
    required String messageId,
    required Map<String, dynamic> message,
  }) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    final myReactions = _extractReactions(message)[currentUserId] ?? const {};
    if (myReactions.isNotEmpty) {
      _clearMyReactions(messageId: messageId, currentUserId: currentUserId);
      return;
    }
    _toggleReaction(messageId: messageId, message: message, emoji: '❤️');
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

    const quickEmojis = <String>[
      '\u{1F44D}',
      '\u{2764}\u{FE0F}',
      '\u{1F602}',
      '\u{1F62E}',
      '\u{1F622}',
      '\u{1F621}',
    ];
    final myReactions = _extractReactions(message)[currentUserId] ?? const {};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final maxHeight = MediaQuery.of(context).size.height * 0.62;
        return SafeArea(
          child: SizedBox(
            height: maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (myReactions.isNotEmpty)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: const Icon(Icons.remove_circle_outline),
                    title: const Text('Remove my reactions'),
                    subtitle: Text(
                      myReactions.join(' '),
                      style: _withEmojiFallback(const TextStyle()),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _clearMyReactions(
                        messageId: messageId,
                        currentUserId: currentUserId,
                      );
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final emoji in quickEmojis)
                        ChoiceChip(
                          label: Text(
                            emoji,
                            style: _withEmojiFallback(
                              const TextStyle(fontSize: 22),
                            ),
                          ),
                          selected: myReactions.contains(emoji),
                          onSelected: (_) async {
                            Navigator.pop(context);
                            await _toggleReaction(
                              messageId: messageId,
                              message: message,
                              emoji: emoji,
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: emoji_picker.EmojiPicker(
                    onEmojiSelected: (_, selected) async {
                      Navigator.pop(context);
                      await _toggleReaction(
                        messageId: messageId,
                        message: message,
                        emoji: selected.emoji,
                      );
                    },
                    config: emoji_picker.Config(
                      height: maxHeight,
                      checkPlatformCompatibility: true,
                      viewOrderConfig: const emoji_picker.ViewOrderConfig(
                        top: emoji_picker.EmojiPickerItem.categoryBar,
                        middle: emoji_picker.EmojiPickerItem.emojiView,
                        bottom: emoji_picker.EmojiPickerItem.searchBar,
                      ),
                      emojiViewConfig: emoji_picker.EmojiViewConfig(
                        columns: 8,
                        emojiSizeMax: 28,
                        backgroundColor: colorScheme.surface,
                      ),
                      categoryViewConfig: emoji_picker.CategoryViewConfig(
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        iconColor: colorScheme.onSurfaceVariant,
                        iconColorSelected: colorScheme.primary,
                        indicatorColor: colorScheme.primary,
                        backspaceColor: colorScheme.primary,
                        recentTabBehavior:
                            emoji_picker.RecentTabBehavior.RECENT,
                      ),
                      bottomActionBarConfig:
                          const emoji_picker.BottomActionBarConfig(
                            enabled: false,
                          ),
                      searchViewConfig: emoji_picker.SearchViewConfig(
                        backgroundColor: colorScheme.surface,
                        buttonIconColor: colorScheme.onSurfaceVariant,
                        hintText: 'Search emoji',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDeleteForEveryoneDialog({required String messageId}) async {
    final conversationId = widget.conversationId;
    if (conversationId == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete for everyone'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;
    try {
      await widget.chatService.deleteMessage(
        conversationId: conversationId,
        messageId: messageId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete message: $e')));
    }
  }

  IconData _deliveryStatusIcon({
    required bool isPending,
    required bool isRead,
  }) {
    if (isPending) return Icons.schedule;
    if (isRead) return Icons.done_all;
    return Icons.done;
  }

  Color _deliveryStatusColor({
    required bool isPending,
    required bool isRead,
    required bool isMe,
    required ColorScheme colorScheme,
  }) {
    if (!isMe) {
      return colorScheme.onSurfaceVariant;
    }
    if (isPending) {
      return Colors.amber.shade300;
    }
    if (isRead) {
      return Colors.lightBlueAccent.shade100;
    }
    return Colors.white;
  }

  _CallSummaryData? _extractCallSummaryData(Map<String, dynamic> messageData) {
    final raw = messageData['callSummary'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);

    final kind = map['kind']?.toString().toLowerCase() == 'video'
        ? 'video'
        : 'audio';
    final result = map['result']?.toString().trim().toLowerCase() ?? 'ended';
    final durationSeconds = map['durationSeconds'] is num
        ? (map['durationSeconds'] as num).toInt()
        : 0;
    final startedAtMs = map['startedAtMs'] is num
        ? (map['startedAtMs'] as num).toInt()
        : null;
    final startedAt = startedAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(startedAtMs)
        : null;

    return _CallSummaryData(
      isVideo: kind == 'video',
      result: result,
      durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
      startedAt: startedAt,
    );
  }

  String _formatCompactDuration(int totalSeconds) {
    var seconds = totalSeconds;
    if (seconds < 0) seconds = 0;

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  String _callResultLabel(String result) {
    switch (result) {
      case 'completed':
        return 'Completed';
      case 'declined':
        return 'Declined';
      case 'missed':
        return 'Missed';
      case 'failed':
        return 'Failed';
      default:
        return 'Ended';
    }
  }

  Widget _buildCallSummaryBody({
    required _CallSummaryData data,
    required bool isMe,
    required ColorScheme colorScheme,
    required Color incomingTextColor,
    required Color incomingMetaColor,
  }) {
    final primaryColor = isMe ? colorScheme.onPrimary : incomingTextColor;
    final secondaryColor = isMe
        ? colorScheme.onPrimary.withValues(alpha: 0.76)
        : incomingMetaColor;
    final title = data.isVideo ? 'Video call' : 'Audio call';
    final startedAtText = data.startedAt != null
        ? DateFormat('HH:mm').format(data.startedAt!)
        : null;
    final subtitle = data.result == 'completed' && data.durationSeconds > 0
        ? _formatCompactDuration(data.durationSeconds)
        : (startedAtText == null
              ? _callResultLabel(data.result)
              : '${_callResultLabel(data.result)} • $startedAtText');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          data.isVideo ? Icons.videocam : Icons.call,
          size: 16,
          color: primaryColor,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: secondaryColor, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
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
    final canEdit =
        isMe &&
        (message['type']?.toString() ?? 'text') == 'text' &&
        message['callSummary'] == null;
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
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                  subtitle: const Text(
                    'Choose if you want to delete for everyone',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showDeleteForEveryoneDialog(messageId: messageId);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward'),
                subtitle: const Text('Copies message text'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Clipboard.setData(ClipboardData(text: displayText));
                  if (!rootContext.mounted) return;
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

  Widget _buildReactionsRow({
    required String messageId,
    required Map<String, dynamic> message,
  }) {
    final reactions = _extractReactions(message);
    if (reactions.isEmpty) return const SizedBox.shrink();
    final currentUserId = _auth.currentUser?.uid;
    final myReactions = currentUserId == null
        ? const <String>{}
        : (reactions[currentUserId] ?? const <String>{});

    final counts = <String, int>{};
    for (final emojis in reactions.values) {
      for (final emoji in emojis) {
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final entry in entries)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _toggleReaction(
                  messageId: messageId,
                  message: message,
                  emoji: entry.key,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: myReactions.contains(entry.key)
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.1,
                        )
                      : null,
                ),
                child: Text(
                  '${entry.key} ${entry.value}',
                  style: _withEmojiFallback(const TextStyle(fontSize: 11)),
                ),
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
      initialData: _cachedMessagesSnapshot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final activeConversationId = widget.conversationId;
        final snapshotData = snapshot.data;
        if (activeConversationId != null &&
            snapshotData != null &&
            snapshotData.docs.isNotEmpty) {
          _sessionMessageCache[activeConversationId] = snapshotData;
        }

        final hasPendingItems =
            widget.pendingTextMessages.isNotEmpty ||
            widget.pendingUploads.isNotEmpty;
        final hasPersistedItems = _persistedMessages.isNotEmpty;

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            !hasPendingItems) {
          if (hasPersistedItems) {
            return _buildPersistedMessagesList(currentUser.uid);
          }
          if (!widget.hasMessages &&
              (_cacheHydrated || _persistentCacheHydrated)) {
            return _buildEmptyState();
          }
          return _buildLoadingState();
        }

        final encryptionReady = widget.chatService.isEncryptionReady;
        final messages = snapshot.data?.docs ?? [];
        if (messages.isNotEmpty) {
          _latestLiveMessages = List<QueryDocumentSnapshot>.from(messages);
          _latestLiveMessagesOwnerId = currentUser.uid;
          _schedulePersistedCacheWriteFromLive();
        }
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

        if (messages.isEmpty && !hasPendingItems) {
          final streamSettled =
              snapshot.connectionState == ConnectionState.active ||
              snapshot.connectionState == ConnectionState.done ||
              snapshot.hasData;
          if (!streamSettled && hasPersistedItems) {
            return _buildPersistedMessagesList(currentUser.uid);
          }
          if (streamSettled) {
            _schedulePersistedCacheClear(currentUser.uid);
          }
          if (!widget.hasMessages ||
              streamSettled ||
              _cacheHydrated ||
              _persistentCacheHydrated) {
            return _buildEmptyState();
          }
          return const SizedBox.shrink();
        }

        final pendingItems = <Map<String, dynamic>>[];
        for (final pending in widget.pendingTextMessages) {
          pendingItems.add({
            'type': 'text',
            'createdAt': pending.createdAt,
            'payload': pending,
          });
        }
        for (final pending in widget.pendingUploads) {
          pendingItems.add({
            'type': 'upload',
            'createdAt': pending.createdAt,
            'payload': pending,
          });
        }
        pendingItems.sort(
          (a, b) => (b['createdAt'] as DateTime).compareTo(
            a['createdAt'] as DateTime,
          ),
        );
        final orderedMessages = messages.reversed.toList();
        final totalItems = orderedMessages.length + pendingItems.length;
        _scheduleAutoScrollIfNeeded(totalItems);

        return ListView.builder(
          controller: widget.scrollController,
          reverse: true,
          padding: const EdgeInsets.all(16),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index < pendingItems.length) {
              final item = pendingItems[index];
              final type = item['type'] as String;
              final payload = item['payload'];
              if (type == 'text' && payload is _PendingTextMessage) {
                return _animateOnFirstPaint(
                  id: 'pending_text_${payload.id}',
                  child: _buildPendingTextBubble(
                    payload,
                    key: ValueKey('pending_text_${payload.id}'),
                  ),
                );
              }
              if (type == 'upload' && payload is _PendingUpload) {
                return _animateOnFirstPaint(
                  id: 'pending_upload_${payload.id}',
                  child: _buildPendingUploadBubble(
                    payload,
                    key: ValueKey('pending_upload_${payload.id}'),
                  ),
                );
              }
              return const SizedBox.shrink();
            }

            final messageIndex = index - pendingItems.length;
            if (messageIndex < 0 || messageIndex >= orderedMessages.length) {
              return const SizedBox.shrink();
            }
            final messageDoc = orderedMessages[messageIndex];
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
                  readAt: readAt,
                  messageId: messageId,
                  key: ValueKey(messageId),
                ),
              );
            }

            final signature =
                '${encryptionReady ? 'ready' : 'not_ready'}||${_decryptSignature(message)}';
            if (_decryptInputSignature[messageId] != signature) {
              _decryptInputSignature[messageId] = signature;
              _decryptFutureCache.remove(messageId);
              _decryptedCache.remove(messageId);
            }

            final cachedText = _decryptedCache[messageId]?.trim() ?? '';
            final persistedText = _persistedTextForMessage(messageId);
            final optimisticText =
                widget.optimisticTextByMessageId[messageId]?.trim() ?? '';
            var immediateText = cachedText.isNotEmpty
                ? cachedText
                : (persistedText.isNotEmpty ? persistedText : optimisticText);
            if (immediateText.isEmpty && type == 'sticker') {
              immediateText = message['sticker']?.toString().trim() ?? '';
            }

            if (!encryptionReady) {
              return _animateOnFirstPaint(
                id: 'msg_$messageId',
                child: type == 'location'
                    ? _buildLocationBubble(
                        immediateText,
                        isMe,
                        timestamp,
                        messageId: messageId,
                        isPending: isPending,
                        isRead: isRead,
                        readAt: readAt,
                        key: ValueKey(messageId),
                      )
                    : _buildMessageBubble(
                        immediateText.isNotEmpty
                            ? immediateText
                            : 'Encrypted message',
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

            if (cachedText.isNotEmpty) {
              widget.optimisticTextByMessageId.remove(messageId);
              return _animateOnFirstPaint(
                id: 'msg_$messageId',
                child: type == 'location'
                    ? _buildLocationBubble(
                        cachedText,
                        isMe,
                        timestamp,
                        messageId: messageId,
                        isPending: isPending,
                        isRead: isRead,
                        readAt: readAt,
                        key: ValueKey(messageId),
                      )
                    : _buildMessageBubble(
                        cachedText,
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

            final decryptFuture = _decryptFutureCache.putIfAbsent(
              messageId,
              () {
                final future = encryptionReady
                    ? widget.chatService.decryptMessage(messageData: message)
                    : Future.value('');

                return future.then((decrypted) {
                  if (encryptionReady && decrypted.isNotEmpty) {
                    _decryptedCache[messageId] = decrypted;
                    widget.optimisticTextByMessageId.remove(messageId);
                    if (mounted) {
                      _schedulePersistedCacheWriteFromLive();
                    }
                  }
                  return decrypted;
                });
              },
            );

            return FutureBuilder<String>(
              future: decryptFuture,
              builder: (context, decryptSnapshot) {
                String displayText;

                if (!encryptionReady) {
                  displayText =
                      _decryptedCache[messageId] ??
                      (persistedText.isNotEmpty
                          ? persistedText
                          : optimisticText);
                } else if (decryptSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  displayText =
                      _decryptedCache[messageId] ??
                      (persistedText.isNotEmpty
                          ? persistedText
                          : optimisticText);
                } else if (decryptSnapshot.hasError) {
                  displayText =
                      _decryptedCache[messageId] ??
                      (persistedText.isNotEmpty
                          ? persistedText
                          : optimisticText);
                  if (displayText.isEmpty) {
                    displayText = 'Encrypted message';
                  }
                } else {
                  displayText = decryptSnapshot.data ?? '';
                  if (displayText.isEmpty) {
                    displayText =
                        _decryptedCache[messageId] ??
                        (persistedText.isNotEmpty
                            ? persistedText
                            : optimisticText);
                  }
                  if (displayText.isEmpty && type == 'sticker') {
                    displayText = message['sticker']?.toString().trim() ?? '';
                  }
                  if (displayText.isEmpty) {
                    displayText = 'Encrypted message';
                  }
                }

                return _animateOnFirstPaint(
                  id: 'msg_$messageId',
                  child: type == 'location'
                      ? _buildLocationBubble(
                          displayText,
                          isMe,
                          timestamp,
                          messageId: messageId,
                          isPending: isPending,
                          isRead: isRead,
                          readAt: readAt,
                          key: ValueKey(messageId),
                        )
                      : _buildMessageBubble(
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

  Widget _buildLoadingState() {
    return ListView.builder(
      controller: widget.scrollController,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        final isMe = index.isEven;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.45,
            height: 46,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
            ),
          ),
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

  Widget _buildLocationBubble(
    String rawText,
    bool isMe,
    Timestamp? timestamp, {
    required String messageId,
    required bool isPending,
    required bool isRead,
    required Timestamp? readAt,
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final trimmed = rawText.trim();
    final coords = trimmed.startsWith('loc:') ? trimmed.substring(4) : trimmed;
    final parts = coords.split(',');
    final lat = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
    final lng = parts.length > 1 ? double.tryParse(parts[1]) : null;

    final bubbleColor =
        isMe ? colorScheme.primary : colorScheme.surfaceContainerHigh;
    final textColor = isMe ? colorScheme.onPrimary : colorScheme.onSurface;

    return Align(
      key: key,
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: (lat != null && lng != null)
              ? () async {
                  final uri = Uri.parse(
                    'https://maps.google.com/?q=$lat,$lng',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on, color: textColor, size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shared location',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (lat != null && lng != null)
                        Text(
                          '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.72),
                            fontSize: 11,
                          ),
                        ),
                      Text(
                        'Tap to open in Maps',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.65),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final themeService = context.watch<ThemeService>();
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
    final callSummary = _extractCallSummaryData(messageData);
    final isCallSummary = callSummary != null;
    final isSticker =
        (messageData['type']?.toString().trim().toLowerCase() ?? 'text') ==
        'sticker';
    final sentAtText = timestamp != null
        ? DateFormat('HH:mm').format(timestamp.toDate())
        : '';
    final statusIcon = _deliveryStatusIcon(
      isPending: isPending,
      isRead: isRead,
    );
    final statusColor = _deliveryStatusColor(
      isPending: isPending,
      isRead: isRead,
      isMe: isMe,
      colorScheme: colorScheme,
    );

    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () {
        _handleDoubleTapReaction(messageId: messageId, message: messageData);
      },
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
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCallSummary ? 12 : 16,
            vertical: isCallSummary ? 8 : 10,
          ),
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
              if (!isCallSummary && replyText.isNotEmpty)
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
              if (callSummary != null)
                _buildCallSummaryBody(
                  data: callSummary,
                  isMe: isMe,
                  colorScheme: colorScheme,
                  incomingTextColor: receivedTextColor,
                  incomingMetaColor: receivedMetaColor,
                )
              else if (isSticker)
                _buildStickerBody(text: text, messageData: messageData)
              else
                ChatMessageText(
                  text: text,
                  style: TextStyle(
                    color: isMe ? colorScheme.onPrimary : receivedTextColor,
                    fontSize: 15,
                  ),
                  linkStyle: TextStyle(
                    color: isMe
                        ? colorScheme.onPrimary.withValues(alpha: 0.95)
                        : colorScheme.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                  showPreviews: themeService.showLinkPreviews,
                  previewBackgroundColor: isMe
                      ? colorScheme.onPrimary.withValues(alpha: 0.14)
                      : colorScheme.surfaceContainerHighest,
                  previewBorderColor: isMe
                      ? colorScheme.onPrimary.withValues(alpha: 0.25)
                      : colorScheme.outlineVariant.withValues(alpha: 0.45),
                  previewTitleColor: isMe
                      ? colorScheme.onPrimary
                      : receivedTextColor,
                  previewMetaColor: isMe
                      ? colorScheme.onPrimary.withValues(alpha: 0.82)
                      : receivedMetaColor,
                ),
              if (!isCallSummary && !isSticker && isEdited) ...[
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
              _buildReactionsRow(messageId: messageId, message: messageData),
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
                      Icon(statusIcon, size: 16, color: statusColor),
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

  Widget _buildStickerBody({
    required String text,
    required Map<String, dynamic> messageData,
  }) {
    final stickerUrl = messageData['stickerUrl']?.toString().trim() ?? '';
    final fallbackText =
        (messageData['stickerFallback']?.toString().trim().isNotEmpty == true)
        ? messageData['stickerFallback'].toString().trim()
        : text.trim();

    if (stickerUrl.isEmpty) {
      return Text(
        fallbackText,
        style: _withEmojiFallback(
          TextStyle(
            fontSize: fallbackText.runes.length <= 2 ? 46 : 38,
            height: 1.05,
          ),
        ),
      );
    }

    final isGif = _looksLikeGifUrl(stickerUrl);
    final fileName = _stickerFileName(stickerUrl);
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ImageViewerScreen(imageUrl: stickerUrl, fileName: fileName),
          ),
        );
      },
      onLongPress: () => _copyStickerLink(stickerUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: isGif
            ? Image.network(
                stickerUrl,
                width: 134,
                height: 134,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 134,
                  height: 134,
                  alignment: Alignment.center,
                  color: Colors.black12,
                  child: Text(
                    fallbackText,
                    style: _withEmojiFallback(
                      const TextStyle(fontSize: 42, height: 1.05),
                    ),
                  ),
                ),
              )
            : CachedNetworkImage(
                imageUrl: stickerUrl,
                width: 134,
                height: 134,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  width: 134,
                  height: 134,
                  alignment: Alignment.center,
                  color: Colors.black12,
                  child: Text(
                    fallbackText,
                    style: _withEmojiFallback(
                      const TextStyle(fontSize: 42, height: 1.05),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _stickerFileName(String stickerUrl) {
    final uri = Uri.tryParse(stickerUrl);
    if (uri == null || uri.pathSegments.isEmpty) {
      return 'sticker.png';
    }
    final tail = uri.pathSegments.last.trim();
    if (tail.isEmpty) return 'sticker.png';
    return tail;
  }

  Future<void> _copyStickerLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Sticker link copied')));
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
              style: _withEmojiFallback(
                const TextStyle(color: Colors.white, fontSize: 15),
              ),
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
    final mime = upload.mimeType.toLowerCase();
    final isAudio = mime.startsWith('audio/');
    final isVideo = mime.startsWith('video/');
    final title = isAudio
        ? 'Voice message'
        : (isVideo ? 'Video message' : upload.fileName);

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
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (upload.caption != null && upload.caption!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      upload.caption!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
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
    required Timestamp? readAt,
    required String messageId,
    Key? key,
  }) {
    final fileName = message['fileName']?.toString() ?? 'File';
    final fileSize = message['fileSize'] is int
        ? message['fileSize'] as int
        : 0;
    final fileUrl = message['fileUrl']?.toString() ?? '';
    final mimeType = message['mimeType']?.toString() ?? '';
    final caption = message['caption']?.toString().trim() ?? '';
    final isImage =
        mimeType.toLowerCase().startsWith('image/') ||
        _looksLikeImageUrl(fileUrl);
    final isVideo = mimeType.toLowerCase().startsWith('video/');
    final isAudio = mimeType.toLowerCase().startsWith('audio/');

    // Check download status
    final downloadProgress = widget.downloadService.getProgress(messageId);
    final isDownloading =
        downloadProgress?.status == DownloadStatus.downloading;
    final isDownloaded = downloadProgress?.status == DownloadStatus.completed;
    final localPath = downloadProgress?.localPath;
    final progress = downloadProgress?.progress ?? 0;
    final themeService = context.watch<ThemeService>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final incomingBubbleColor = isDarkTheme
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.92)
        : colorScheme.surfaceContainerHigh;

    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () {
        _handleDoubleTapReaction(messageId: messageId, message: message);
      },
      onLongPress: () {
        _showMessageActions(
          messageId: messageId,
          message: message,
          displayText: 'File: $fileName',
          isMe: isMe,
          sentAt: timestamp,
          readAt: readAt,
        );
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isImage)
                _buildImagePreview(
                  fileUrl: fileUrl,
                  fileName: fileName,
                  fileSize: fileSize,
                  mimeType: mimeType,
                  localPath: localPath,
                  timestamp: timestamp,
                  isMe: isMe,
                )
              else if (isVideo && fileUrl.isNotEmpty) ...[
                if (Platform.isWindows)
                  _buildWindowsVideoPreviewFallback(
                    fileName: fileName,
                    isMe: isMe,
                    onOpenFullscreen: () => _openVideoViewer(
                      messageId: messageId,
                      fileUrl: fileUrl,
                      localPath: localPath,
                      fileName: fileName,
                      fileSize: fileSize,
                    ),
                  )
                else
                  _InlineVideoPlayer(
                    url: fileUrl,
                    messageId: messageId,
                    onInitialized: () {
                      if (!mounted || !widget.shouldAutoScroll()) return;
                      widget.onAutoScrollToBottom();
                    },
                    onOpenFullscreen: () => _openVideoViewer(
                      messageId: messageId,
                      fileUrl: fileUrl,
                      localPath: localPath,
                      fileName: fileName,
                      fileSize: fileSize,
                    ),
                  ),
                if (timestamp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildFileMetaRow(
                      timestamp: timestamp,
                      isMe: isMe,
                      isPending: isPending,
                      isRead: isRead,
                    ),
                  ),
              ] else if (isAudio && fileUrl.isNotEmpty) ...[
                _InlineAudioPlayer(url: fileUrl, isMe: isMe),
                if (timestamp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildFileMetaRow(
                      timestamp: timestamp,
                      isMe: isMe,
                      isPending: isPending,
                      isRead: isRead,
                    ),
                  ),
              ] else
                _buildFileInfo(
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
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                  child: ChatMessageText(
                    text: caption,
                    style: TextStyle(
                      color: isMe
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    linkStyle: TextStyle(
                      color: isMe
                          ? colorScheme.onPrimary.withValues(alpha: 0.95)
                          : colorScheme.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                    showPreviews: themeService.showLinkPreviews,
                    maxPreviewCards: 1,
                    previewBackgroundColor: isMe
                        ? colorScheme.onPrimary.withValues(alpha: 0.14)
                        : colorScheme.surfaceContainerHighest,
                    previewBorderColor: isMe
                        ? colorScheme.onPrimary.withValues(alpha: 0.25)
                        : colorScheme.outlineVariant.withValues(alpha: 0.45),
                    previewTitleColor: isMe
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    previewMetaColor: isMe
                        ? colorScheme.onPrimary.withValues(alpha: 0.82)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              _buildReactionsRow(messageId: messageId, message: message),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview({
    required String fileUrl,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String? localPath,
    required Timestamp? timestamp,
    required bool isMe,
  }) {
    final isGif =
        mimeType.toLowerCase().contains('gif') || _looksLikeGifUrl(fileUrl);
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
              child: isGif
                  ? Image.network(
                      fileUrl,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) => Container(
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
                    )
                  : CachedNetworkImage(
                      imageUrl: fileUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, url) => Container(
                        height: 200,
                        color: Colors.grey[800],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, url, error) => Container(
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

  Widget _buildWindowsVideoPreviewFallback({
    required String fileName,
    required bool isMe,
    required VoidCallback onOpenFullscreen,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final receivedMetaColor = colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(
                Icons.videocam,
                size: 18,
                color: isMe ? colorScheme.onPrimary : receivedMetaColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isMe ? colorScheme.onPrimary : receivedMetaColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Video preview is disabled on Windows. Download and open the file.',
            style: TextStyle(
              color: isMe
                  ? colorScheme.onPrimary.withValues(alpha: 0.75)
                  : receivedMetaColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: onOpenFullscreen,
            icon: const Icon(Icons.fullscreen),
            label: const Text('Open full screen'),
          ),
        ],
      ),
    );
  }

  void _openVideoViewer({
    required String messageId,
    required String fileUrl,
    required String? localPath,
    required String fileName,
    required int fileSize,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoViewerScreen(
          messageId: messageId,
          videoUrl: fileUrl,
          localPath: localPath,
          fileName: fileName,
          fileSize: fileSize,
        ),
      ),
    );
  }

  Widget _buildFileMetaRow({
    required Timestamp timestamp,
    required bool isMe,
    required bool isPending,
    required bool isRead,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final receivedMetaColor = colorScheme.onSurfaceVariant;

    return Row(
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
            _deliveryStatusIcon(isPending: isPending, isRead: isRead),
            size: 16,
            color: _deliveryStatusColor(
              isPending: isPending,
              isRead: isRead,
              isMe: isMe,
              colorScheme: colorScheme,
            ),
          ),
        ],
      ],
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
      mainAxisSize: MainAxisSize.max,
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
                        _deliveryStatusIcon(
                          isPending: isPending,
                          isRead: isRead,
                        ),
                        size: 16,
                        color: _deliveryStatusColor(
                          isPending: isPending,
                          isRead: isRead,
                          isMe: isMe,
                          colorScheme: colorScheme,
                        ),
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

class _InlineVideoPlayer extends StatefulWidget {
  final String url;
  final String messageId;
  final VoidCallback? onInitialized;
  final VoidCallback? onOpenFullscreen;

  const _InlineVideoPlayer({
    required this.url,
    required this.messageId,
    this.onInitialized,
    this.onOpenFullscreen,
  });

  @override
  State<_InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<_InlineVideoPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  String? _error;
  bool _userRequestedPlay = false;
  bool _checkingCache = true; // NEW
  String? _cachedPath; // NEW
  int _setupToken = 0;
  bool _didNotifyInitialized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _error = 'Video preview is unavailable on Windows';
      _checkingCache = false;
      return;
    }
    _checkCache();
  }

  @override
  void didUpdateWidget(covariant _InlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Platform.isWindows) return;
    if (oldWidget.url != widget.url ||
        oldWidget.messageId != widget.messageId) {
      _checkingCache = true;
      _userRequestedPlay = false;
      _didNotifyInitialized = false;
      _checkCache();
    }
  }

  void _videoListener() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _checkCache() async {
    final cached = await VideoCacheService().getCached(widget.messageId);
    if (!mounted) return;
    setState(() {
      _cachedPath = cached;
      _checkingCache = false;
    });
  }

  Future<void> _setupControllerFromPath(String localPath) async {
    final setupToken = ++_setupToken;
    final oldController = _controller;
    oldController?.removeListener(_videoListener);

    final controller = VideoPlayerController.file(File(localPath));
    controller.addListener(_videoListener);

    final future = controller.initialize().then((_) {
      controller.setLooping(false);
    });

    if (!mounted || setupToken != _setupToken) {
      controller.removeListener(_videoListener);
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _initializeFuture = future;
      _error = null;
    });

    try {
      await future;
      if (!_didNotifyInitialized) {
        _didNotifyInitialized = true;
        widget.onInitialized?.call();
      }
    } catch (_) {
      if (!mounted || setupToken != _setupToken) return;
      controller.removeListener(_videoListener);
      await controller.dispose();
      setState(() {
        _controller = null;
        _initializeFuture = null;
        _error = 'Could not load video';
      });
    } finally {
      await oldController?.dispose();
    }
  }

  Future<void> _setupControllerFromNetwork() async {
    final setupToken = ++_setupToken;
    final oldController = _controller;
    oldController?.removeListener(_videoListener);

    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() => _error = 'Invalid video link');
      await oldController?.dispose();
      return;
    }

    // Download to cache dir, then play from file — avoids repeated network hits
    final cachePath = await VideoCacheService().reservePath(widget.messageId);
    final cacheFile = File(cachePath);

    if (!cacheFile.existsSync()) {
      try {
        final client = HttpClient();
        final request = await client.getUrl(uri);
        final response = await request.close();
        final sink = cacheFile.openWrite();
        await response.pipe(sink);
        client.close();
      } catch (e) {
        if (!mounted || setupToken != _setupToken) return;
        setState(() => _error = 'Could not download video');
        await oldController?.dispose();
        return;
      }
    }

    if (!mounted || setupToken != _setupToken) return;
    setState(() {
      _cachedPath = cachePath;
    });
    await _setupControllerFromPath(cachePath);
  }

  void _onTapPlay() {
    if (_controller != null && _controller!.value.isInitialized) {
      _togglePlayback();
      return;
    }
    if (_userRequestedPlay) return;
    setState(() => _userRequestedPlay = true);
    if (_cachedPath != null && _cachedPath!.isNotEmpty) {
      _setupControllerFromPath(_cachedPath!);
      return;
    }
    _setupControllerFromNetwork();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await controller.play();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_videoListener);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingCache) {
      // Tiny non-intrusive placeholder while we check disk (usually <1ms)
      return _buildShell(child: const SizedBox.shrink());
    }

    if (_error != null) {
      return _buildShell(
        child: Center(
          child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }

    final controller = _controller;
    final initFuture = _initializeFuture;

    if (!_userRequestedPlay) {
      return _buildShell(
        child: GestureDetector(
          onTap: _onTapPlay,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  color: Colors.white70,
                  size: 54,
                ),
                if (_cachedPath != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Ready offline',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Requested or cached, but controller not ready yet
    if (controller == null || initFuture == null) {
      return _buildShell(
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildShell(
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final size = controller.value.size;
        final videoWidth = size.width > 0 ? size.width : 16.0;
        final videoHeight = size.height > 0 ? size.height : 9.0;

        return _buildShell(
          child: Stack(
            children: [
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: videoWidth,
                    height: videoHeight,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: _togglePlayback),
                ),
              ),
              if (!controller.value.isPlaying)
                const Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 54,
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.black38,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShell({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        height: 190,
        color: Colors.black87,
        child: Stack(
          children: [
            Positioned.fill(child: child),
            if (widget.onOpenFullscreen != null)
              Positioned(top: 6, right: 6, child: _buildFullscreenButton()),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenButton() {
    return Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onOpenFullscreen,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.fullscreen, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  // ... _videoListener, _togglePlayback, dispose unchanged
}

class _InlineAudioPlayer extends StatefulWidget {
  final String url;
  final bool isMe;

  const _InlineAudioPlayer({required this.url, required this.isMe});

  @override
  State<_InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<_InlineAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double? _dragMillis;
  PlayerState _state = PlayerState.stopped;
  bool _isLoading = false;
  bool _sourcePrepared = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bindPlayerStreams();
    unawaited(_prepareSource());
  }

  @override
  void didUpdateWidget(covariant _InlineAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      unawaited(_resetAndPrepareSource());
    }
  }

  void _bindPlayerStreams() {
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() {
        _duration = duration;
      });
    });

    _positionSub = _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() {
        _position = position;
      });
    });

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _state = state;
        _isLoading = false;
      });
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _state = PlayerState.stopped;
        _position = _duration;
      });
    });
  }

  Future<void> _resetAndPrepareSource() async {
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _duration = Duration.zero;
      _position = Duration.zero;
      _dragMillis = null;
      _state = PlayerState.stopped;
      _isLoading = false;
      _sourcePrepared = false;
      _error = null;
    });
    await _prepareSource();
  }

  Future<void> _prepareSource() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(UrlSource(widget.url));
      if (!mounted) return;
      setState(() {
        _sourcePrepared = true;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sourcePrepared = false;
        _error = 'Could not load audio';
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_isLoading) return;
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
        return;
      }

      setState(() {
        _isLoading = true;
      });

      if (_sourcePrepared &&
          (_state == PlayerState.paused ||
              (_position > Duration.zero && _position < _duration))) {
        await _player.resume();
      } else {
        await _player.play(UrlSource(widget.url));
        _sourcePrepared = true;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not play audio';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _seekToMillis(double millis) async {
    final target = Duration(milliseconds: millis.round());
    try {
      await _player.seek(target);
    } catch (_) {}
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = widget.isMe
        ? colorScheme.onPrimary
        : colorScheme.primary;
    final metaColor = widget.isMe
        ? colorScheme.onPrimary.withValues(alpha: 0.72)
        : colorScheme.onSurfaceVariant;
    final maxMillis = (_duration.inMilliseconds > 0)
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final currentMillis = (_dragMillis ?? _position.inMilliseconds.toDouble())
        .clamp(0.0, maxMillis);
    final playIcon = _state == PlayerState.playing
        ? Icons.pause_circle_filled
        : Icons.play_circle_fill;

    return Container(
      constraints: const BoxConstraints(minWidth: 210),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            splashRadius: 20,
            visualDensity: VisualDensity.compact,
            onPressed: _togglePlayback,
            icon: _isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  )
                : Icon(playIcon, size: 34, color: accentColor),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    activeTrackColor: accentColor,
                    inactiveTrackColor: metaColor.withValues(alpha: 0.35),
                    thumbColor: accentColor,
                  ),
                  child: Slider(
                    value: currentMillis,
                    min: 0,
                    max: maxMillis,
                    onChanged: (value) {
                      setState(() {
                        _dragMillis = value;
                      });
                    },
                    onChangeEnd: (value) async {
                      setState(() {
                        _dragMillis = null;
                      });
                      await _seekToMillis(value);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 8, bottom: 2),
                  child: Text(
                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                    style: TextStyle(fontSize: 11, color: metaColor),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 8,
                      right: 8,
                      bottom: 2,
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 10, color: metaColor),
                    ),
                  ),
              ],
            ),
          ),
        ],
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

class _CallSummaryData {
  final bool isVideo;
  final String result;
  final int durationSeconds;
  final DateTime? startedAt;

  const _CallSummaryData({
    required this.isVideo,
    required this.result,
    required this.durationSeconds,
    required this.startedAt,
  });
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
  final DateTime createdAt;
  final String? caption;
  double progress;
  UploadTask? task;
  StreamSubscription<TaskSnapshot>? sub;

  _PendingUpload({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.createdAt,
    this.caption,
    required this.progress,
  });
}

class _MediaComposerResult {
  final List<XFile> files;
  final String caption;

  const _MediaComposerResult({required this.files, required this.caption});
}
