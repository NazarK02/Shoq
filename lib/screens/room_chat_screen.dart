import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../models/server_channel.dart';
import '../services/chat_service_e2ee.dart';
import '../services/file_download_service.dart';
import '../services/message_cache_service.dart';
import '../services/theme_service.dart';
import '../services/user_cache_service.dart';
import '../widgets/chat_message_text.dart';
import 'image_viewer_screen.dart';
import 'room_info_screen.dart';
import 'voice_channel_screen.dart';

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
  static final Map<String, QuerySnapshot> _sessionMessageCache = {};
  static final Map<String, List<Map<String, dynamic>>>
  _sessionPersistedMessages = {};
  static const List<String> _stickers = [
    '😀',
    '😎',
    '🥳',
    '🤯',
    '🤖',
    '🫶',
    '💖',
    '🔥',
    '💯',
    '🎉',
    '👑',
    '🚀',
    '🌈',
    '🐱',
    '🐶',
    '🐸',
    '🍕',
    '☕',
    '⚽',
    '🎮',
  ];
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  final UserCacheService _userCache = UserCacheService();
  final MessageCacheService _messageCache = MessageCacheService();
  final FileDownloadService _downloadService = FileDownloadService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _conversationSub;
  final Map<String, String> _decryptedCache = {};
  final Map<String, Future<String>> _decryptFutures = {};
  final Map<String, String> _decryptInputSignatures = {};
  final Map<String, Map<String, dynamic>> _persistedById = {};
  QuerySnapshot? _cachedMessagesSnapshot;
  List<Map<String, dynamic>> _persistedMessages = [];
  List<QueryDocumentSnapshot> _latestLiveMessages = const [];
  Timer? _persistedCacheDebounce;
  bool _cacheHydrated = false;
  bool _persistentCacheHydrated = false;
  String _lastPersistedPayloadSignature = 'empty';

  List<String> _participants = [];
  List<ServerChannel> _channels = const [ServerChannel.general];
  String _activeChannelId = ServerChannel.generalId;
  Map<String, List<_ChannelFolder>> _channelFolders = const {};
  Map<String, List<_ChannelAssignment>> _channelAssignments = const {};
  String? _selectedFolderId;
  Set<String> _adminIds = const <String>{};
  String _title = '';
  String? _avatarUrl;
  String _ownerId = '';
  bool _isInitializing = true;
  bool _isSending = false;
  bool _openingVoiceChannel = false;
  String? _error;

  bool get _isServer => widget.conversationType == 'server';
  String get _currentUid => _auth.currentUser?.uid ?? '';
  bool get _canManage =>
      _currentUid.isNotEmpty &&
      (_ownerId == _currentUid || _adminIds.contains(_currentUid));

  ServerChannel get _activeChannel {
    for (final channel in _channels) {
      if (channel.id == _activeChannelId) return channel;
    }
    return ServerChannel.general;
  }

  @override
  void initState() {
    super.initState();
    _title = widget.roomTitle.trim().isEmpty ? 'Room' : widget.roomTitle.trim();
    _participants = widget.initialParticipants.toSet().toList();
    _downloadService.addListener(_handleDownloadProgressChanged);
    _hydrateMessageCaches();
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

  void _hydrateMessageCaches() {
    _cachedMessagesSnapshot = _sessionMessageCache[widget.conversationId];
    _cacheHydrated = _cachedMessagesSnapshot != null;

    final sessionPersisted = _sessionPersistedMessages[widget.conversationId];
    if (sessionPersisted != null && sessionPersisted.isNotEmpty) {
      final seeded = _clonePersistedMessages(sessionPersisted);
      _persistedMessages = seeded;
      _persistedById
        ..clear()
        ..addAll(_indexPersistedMessages(seeded));
      _persistentCacheHydrated = true;
      _lastPersistedPayloadSignature = _persistedPayloadSignature(seeded);
    } else {
      _persistedMessages = [];
      _persistedById.clear();
      _persistentCacheHydrated = false;
      _lastPersistedPayloadSignature = 'empty';
    }

    unawaited(_loadFirestoreCachedMessages());
    unawaited(_loadPersistedMessages());
  }

  Future<void> _loadFirestoreCachedMessages() async {
    final cached = await _chatService.getCachedMessages(widget.conversationId);
    if (!mounted) return;
    if (cached != null && cached.docs.isNotEmpty) {
      _sessionMessageCache[widget.conversationId] = cached;
    }
    setState(() {
      if (cached != null) {
        _cachedMessagesSnapshot = cached;
      }
      _cacheHydrated = true;
    });
  }

  Future<void> _loadPersistedMessages() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _persistentCacheHydrated = true;
      });
      return;
    }

    final cached = await _messageCache.loadConversationMessages(
      uid,
      widget.conversationId,
    );
    if (!mounted) return;

    final seeded = _clonePersistedMessages(cached);
    final byId = _indexPersistedMessages(seeded);
    final signature = _persistedPayloadSignature(seeded);

    if (_persistentCacheHydrated &&
        signature == _lastPersistedPayloadSignature) {
      return;
    }

    setState(() {
      _persistedMessages = seeded;
      _persistedById
        ..clear()
        ..addAll(byId);
      _persistentCacheHydrated = true;
      _lastPersistedPayloadSignature = signature;
      _sessionPersistedMessages[widget.conversationId] = seeded;
    });
  }

  List<Map<String, dynamic>> _clonePersistedMessages(
    List<Map<String, dynamic>> source,
  ) {
    return source.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Map<String, Map<String, dynamic>> _indexPersistedMessages(
    List<Map<String, dynamic>> source,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final item in source) {
      final id = item['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      byId[id] = item;
    }
    return byId;
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

  String _persistedTextForMessage(String messageId) {
    return _persistedById[messageId]?['text']?.toString().trim() ?? '';
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
    final item = <String, dynamic>{
      'id': id,
      'type': type,
      'senderId': senderId,
      'read': message['read'] == true,
    };

    if (timestamp != null) {
      item['timestampMs'] = timestamp.millisecondsSinceEpoch;
    }

    final channelId = message['channelId']?.toString().trim();
    if (channelId != null && channelId.isNotEmpty) {
      item['channelId'] = channelId;
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
      if (fileUrl.isNotEmpty) item['fileUrl'] = fileUrl;
      final mimeType = message['mimeType']?.toString().trim() ?? '';
      if (mimeType.isNotEmpty) item['mimeType'] = mimeType;
      final fileFolderId = message['fileFolderId']?.toString().trim() ?? '';
      if (fileFolderId.isNotEmpty) item['fileFolderId'] = fileFolderId;
      final fileFolderName = message['fileFolderName']?.toString().trim() ?? '';
      if (fileFolderName.isNotEmpty) item['fileFolderName'] = fileFolderName;
      return item;
    }

    if (message['callSummary'] is Map) {
      final callSummary = Map<String, dynamic>.from(
        message['callSummary'] as Map,
      );
      if (callSummary.isNotEmpty) {
        item['callSummary'] = callSummary;
      }
    }

    final decrypted = _decryptedCache[id]?.trim() ?? '';
    final persistedText = _persistedById[id]?['text']?.toString().trim() ?? '';
    final text = decrypted.isNotEmpty ? decrypted : persistedText;
    if (text.isNotEmpty) {
      item['text'] = text;
    }

    if (!item.containsKey('text') && !item.containsKey('callSummary')) {
      return const {};
    }
    return item;
  }

  void _schedulePersistedCacheWriteFromLive(String uid) {
    if (uid.trim().isEmpty) return;
    final docs = List<QueryDocumentSnapshot>.from(_latestLiveMessages);
    _persistedCacheDebounce?.cancel();
    _persistedCacheDebounce = Timer(
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

        if (payload.isEmpty) return;
        final signature = _persistedPayloadSignature(payload);
        if (signature == _lastPersistedPayloadSignature) return;

        await _messageCache.saveConversationMessages(
          uid,
          widget.conversationId,
          payload,
        );
        if (!mounted) return;

        final seeded = _clonePersistedMessages(payload);
        setState(() {
          _persistedMessages = seeded;
          _persistedById
            ..clear()
            ..addAll(_indexPersistedMessages(seeded));
          _persistentCacheHydrated = true;
          _lastPersistedPayloadSignature = signature;
          _sessionPersistedMessages[widget.conversationId] = seeded;
        });
      },
    );
  }

  void _schedulePersistedCacheClear(String uid) {
    if (uid.trim().isEmpty) return;
    _persistedCacheDebounce?.cancel();
    _persistedCacheDebounce = Timer(
      const Duration(milliseconds: 260),
      () async {
        await _messageCache.clearConversation(uid, widget.conversationId);
        if (!mounted) return;
        setState(() {
          _persistedMessages = [];
          _persistedById.clear();
          _persistentCacheHydrated = true;
          _lastPersistedPayloadSignature = 'empty';
          _sessionPersistedMessages.remove(widget.conversationId);
        });
      },
    );
  }

  Widget _buildPersistedMessagesView() {
    final visibleItems = _persistedMessages.where((message) {
      return _messageMatchesActiveChannel(message);
    }).toList();

    if (visibleItems.isEmpty) {
      return Center(
        child: Text(
          _isServer
              ? 'No messages in #${_activeChannelName()} yet'
              : 'No messages yet',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      itemCount: visibleItems.length,
      itemBuilder: (context, index) {
        final reversedIndex = visibleItems.length - 1 - index;
        final data = Map<String, dynamic>.from(visibleItems[reversedIndex]);
        final messageId = data['id']?.toString().trim() ?? '';
        if (messageId.isEmpty) return const SizedBox.shrink();
        return _buildMessageTile(messageId, data);
      },
    );
  }

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

  void _startConversationListener() {
    _conversationSub?.cancel();
    _conversationSub = _firestore
        .collection('conversations')
        .doc(widget.conversationId)
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          if (data == null || !mounted) return;

          final title = data['title']?.toString().trim() ?? '';
          final avatarUrl = _normalizePhotoUrl(data['avatarUrl']);
          final ownerId = data['createdBy']?.toString().trim() ?? '';
          final admins = _parseAdminIds(data['admins']);
          final participants = _parseParticipants(data['participants']);
          final channels = _parseChannels(data['channels']);
          final channelFolders = _parseChannelFolders(data['channelFolders']);
          final channelAssignments = _parseChannelAssignments(
            data['channelAssignments'],
          );

          _warmParticipants(participants);

          setState(() {
            if (title.isNotEmpty) _title = title;
            _avatarUrl = avatarUrl;
            _ownerId = ownerId;
            _adminIds = admins;
            if (participants.isNotEmpty) _participants = participants;
            _channels = channels;
            if (!_channels.any((channel) => channel.id == _activeChannelId)) {
              _activeChannelId = ServerChannel.generalId;
            }
            _channelFolders = channelFolders;
            _channelAssignments = channelAssignments;
            final activeFolders = _channelFolders[_activeChannelId] ?? const [];
            if (_selectedFolderId != null &&
                !activeFolders.any(
                  (folder) => folder.id == _selectedFolderId,
                )) {
              _selectedFolderId = activeFolders.isEmpty
                  ? null
                  : activeFolders.first.id;
            }
          });
        });
  }

  Set<String> _parseAdminIds(dynamic raw) {
    if (raw is! List) return const <String>{};
    return raw
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  List<String> _parseParticipants(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  List<ServerChannel> _parseChannels(dynamic raw) {
    if (!_isServer) return const [ServerChannel.general];

    final parsed = <ServerChannel>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final channel = ServerChannel.fromMap(map);
        if (channel.id.isEmpty || channel.name.isEmpty) continue;
        parsed.add(channel);
      }
    }

    if (parsed.isEmpty) return const [ServerChannel.general];

    final unique = <String, ServerChannel>{};
    for (final channel in parsed) {
      unique[channel.id] = channel;
    }
    unique.putIfAbsent(ServerChannel.generalId, () => ServerChannel.general);
    return unique.values.toList();
  }

  Map<String, List<_ChannelFolder>> _parseChannelFolders(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, List<_ChannelFolder>>{};
    raw.forEach((key, value) {
      final channelId = key.toString().trim();
      if (channelId.isEmpty || value is! List) return;
      final folders = <_ChannelFolder>[];
      for (final item in value) {
        if (item is! Map) continue;
        final folder = _ChannelFolder.fromMap(Map<String, dynamic>.from(item));
        if (folder.id.isEmpty || folder.name.isEmpty) continue;
        folders.add(folder);
      }
      if (folders.isEmpty) return;
      result[channelId] = folders;
    });
    return result;
  }

  Map<String, List<_ChannelAssignment>> _parseChannelAssignments(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, List<_ChannelAssignment>>{};
    raw.forEach((key, value) {
      final channelId = key.toString().trim();
      if (channelId.isEmpty || value is! List) return;
      final assignments = <_ChannelAssignment>[];
      for (final item in value) {
        if (item is! Map) continue;
        final assignment = _ChannelAssignment.fromMap(
          Map<String, dynamic>.from(item),
        );
        if (assignment.id.isEmpty || assignment.title.isEmpty) continue;
        assignments.add(assignment);
      }
      if (assignments.isEmpty) return;
      assignments.sort((a, b) {
        final aDue = a.dueAt?.millisecondsSinceEpoch ?? 0;
        final bDue = b.dueAt?.millisecondsSinceEpoch ?? 0;
        if (aDue == bDue) {
          return b.createdAt.millisecondsSinceEpoch -
              a.createdAt.millisecondsSinceEpoch;
        }
        if (aDue == 0) return 1;
        if (bDue == 0) return -1;
        return aDue - bDue;
      });
      result[channelId] = assignments;
    });
    return result;
  }

  void _warmParticipants(List<String> ids) {
    final targets = ids.where((id) => id != _currentUid).toSet();
    if (targets.isEmpty) return;
    _userCache.warmUsers(targets, listen: false);
  }

  void _handleDownloadProgressChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openRoomInfo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomInfoScreen(
          conversationId: widget.conversationId,
          conversationType: widget.conversationType,
        ),
      ),
    );
  }

  Future<void> _activateChannel(ServerChannel channel) async {
    final wasActive = _activeChannelId == channel.id;
    if (!wasActive) {
      setState(() {
        _activeChannelId = channel.id;
        final folders = _channelFolders[channel.id] ?? const <_ChannelFolder>[];
        if (folders.isEmpty) {
          _selectedFolderId = null;
        } else if (!folders.any((f) => f.id == _selectedFolderId)) {
          _selectedFolderId = folders.first.id;
        }
      });
    }

    if (ServerChannelType.normalize(channel.type) == ServerChannelType.voice) {
      await _openVoiceChannel(channel: channel);
      return;
    }

    if (!wasActive) {
      _scrollToBottom(force: true);
    }
  }

  Future<void> _openVoiceChannel({ServerChannel? channel}) async {
    if (!_isServer || _openingVoiceChannel) return;
    final target = channel ?? _activeChannel;
    if (ServerChannelType.normalize(target.type) != ServerChannelType.voice) {
      _showSnack('Select a voice channel first.');
      return;
    }

    _openingVoiceChannel = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceChannelScreen(
            conversationId: widget.conversationId,
            conversationTitle: _title,
            channelId: target.id,
            channelName: target.name,
          ),
        ),
      );
    } finally {
      _openingVoiceChannel = false;
    }
  }

  Future<void> _showChannelPicker() async {
    if (!_isServer || _channels.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Channels')),
              ..._channels.map((channel) {
                final isSelected = channel.id == _activeChannelId;
                return ListTile(
                  leading: Icon(_channelIcon(channel.type)),
                  title: Text('${_channelPrefix(channel)}${channel.name}'),
                  subtitle: Text(
                    ServerChannelType.label(channel.type),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: isSelected ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(sheetContext, channel.id),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    ServerChannel? channel;
    for (final item in _channels) {
      if (item.id == selected) {
        channel = item;
        break;
      }
    }
    if (channel == null) return;
    await _activateChannel(channel);
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    if (_isServer && !_channelSupportsTextComposer()) {
      final type = _activeChannelType();
      if (type == ServerChannelType.voice) {
        _showSnack('Voice channels do not support text messages.');
      } else if (type == ServerChannelType.file) {
        _showSnack('Use the upload button to share files in this channel.');
      } else {
        _showSnack('This channel does not support text messages.');
      }
      return;
    }

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
        channelId: _isServer ? _activeChannelId : null,
      );
      _scrollToBottom(force: true, animated: true);
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

  Future<void> _sendSticker(String sticker) async {
    if (_isSending) return;
    if (_isServer && !_channelSupportsTextComposer()) {
      _showSnack('This channel does not support sticker messages.');
      return;
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final value = sticker.trim();
    if (value.isEmpty) return;

    final participants = _participants.toSet().toList();
    if (!participants.contains(currentUser.uid)) {
      participants.add(currentUser.uid);
    }

    setState(() {
      _isSending = true;
    });
    try {
      await _chatService.sendRoomMessage(
        conversationId: widget.conversationId,
        messageText: value,
        participantIds: participants,
        channelId: _isServer ? _activeChannelId : null,
      );
      _scrollToBottom(force: true, animated: true);
    } catch (e) {
      _showSnack('Failed to send sticker: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _showStickerPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: _stickers.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final sticker = _stickers[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _sendSticker(sticker);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(sticker, style: const TextStyle(fontSize: 34)),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<String?> _resolvePickedFilePath(PlatformFile file) async {
    final directPath = file.path?.trim() ?? '';
    if (directPath.isNotEmpty && File(directPath).existsSync()) {
      return directPath;
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final dot = file.name.lastIndexOf('.');
    final extension = (dot > 0 && dot < file.name.length - 1)
        ? file.name.substring(dot)
        : '.bin';
    final tempDir = await Directory.systemTemp.createTemp('shoq_file_channel_');
    final tempPath =
        '${tempDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}$extension';
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempFile.path;
  }

  String? _selectedFolderName() {
    final selectedId = _selectedFolderId;
    if (selectedId == null || selectedId.isEmpty) return null;
    for (final folder in _activeFolders()) {
      if (folder.id == selectedId) return folder.name;
    }
    return null;
  }

  Future<void> _sendFileToActiveChannel() async {
    if (!_isServer || _activeChannelType() != ServerChannelType.file) return;
    if (_isSending) return;

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
      type: FileType.any,
    );
    if (picked == null || picked.files.isEmpty) return;
    final platformFile = picked.files.first;
    final resolvedPath = await _resolvePickedFilePath(platformFile);
    if (resolvedPath == null || resolvedPath.isEmpty) {
      _showSnack('Could not access selected file.');
      return;
    }

    final uploadFile = File(resolvedPath);
    if (!uploadFile.existsSync()) {
      _showSnack('Could not access selected file.');
      return;
    }

    final fileSize = uploadFile.lengthSync();
    final fileName = platformFile.name.trim().isEmpty
        ? 'file_${DateTime.now().millisecondsSinceEpoch}'
        : platformFile.name.trim();
    final mimeType = lookupMimeType(resolvedPath) ?? 'application/octet-stream';
    final caption = _messageController.text.trim();
    if (caption.isNotEmpty) {
      _messageController.clear();
    }

    setState(() {
      _isSending = true;
    });
    try {
      await _chatService.sendFileMessage(
        conversationId: widget.conversationId,
        filePath: resolvedPath,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
        caption: caption.isEmpty ? null : caption,
        channelId: _activeChannelId,
        fileFolderId: _selectedFolderId,
        fileFolderName: _selectedFolderName(),
      );
      _scrollToBottom(force: true, animated: true);
    } catch (e) {
      _showSnack('Could not upload file: $e');
      if (caption.isNotEmpty && _messageController.text.trim().isEmpty) {
        _messageController.text = caption;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Map<String, dynamic> _channelFoldersPayload({
    String? overrideChannelId,
    List<_ChannelFolder>? overrideFolders,
  }) {
    final payload = <String, dynamic>{};
    _channelFolders.forEach((channelId, folders) {
      if (folders.isEmpty) return;
      payload[channelId] = folders.map((folder) => folder.toMap()).toList();
    });
    if (overrideChannelId != null) {
      if (overrideFolders == null || overrideFolders.isEmpty) {
        payload.remove(overrideChannelId);
      } else {
        payload[overrideChannelId] = overrideFolders
            .map((folder) => folder.toMap())
            .toList();
      }
    }
    return payload;
  }

  Map<String, dynamic> _channelAssignmentsPayload({
    String? overrideChannelId,
    List<_ChannelAssignment>? overrideAssignments,
  }) {
    final payload = <String, dynamic>{};
    _channelAssignments.forEach((channelId, assignments) {
      if (assignments.isEmpty) return;
      payload[channelId] = assignments
          .map((assignment) => assignment.toMap())
          .toList();
    });
    if (overrideChannelId != null) {
      if (overrideAssignments == null || overrideAssignments.isEmpty) {
        payload.remove(overrideChannelId);
      } else {
        payload[overrideChannelId] = overrideAssignments
            .map((assignment) => assignment.toMap())
            .toList();
      }
    }
    return payload;
  }

  Future<void> _addFolderToActiveChannel() async {
    if (!_canManage ||
        !_isServer ||
        _activeChannelType() != ServerChannelType.file) {
      return;
    }
    var nameDraft = '';
    final navigator = Navigator.of(context, rootNavigator: true);
    final folderName = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Create folder'),
        content: TextField(
          maxLength: 28,
          decoration: const InputDecoration(hintText: 'Lecture notes'),
          onChanged: (value) {
            nameDraft = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => navigator.pop(nameDraft.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final trimmed = folderName?.trim() ?? '';
    if (trimmed.isEmpty) return;

    final existing = _activeFolders();
    final duplicate = existing.any(
      (folder) => folder.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (duplicate) {
      _showSnack('Folder already exists.');
      return;
    }

    final folder = _ChannelFolder(
      id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
      name: trimmed,
      createdBy: _currentUid,
      createdAt: Timestamp.now(),
    );
    final updated = [...existing, folder];
    final payload = _channelFoldersPayload(
      overrideChannelId: _activeChannelId,
      overrideFolders: updated,
    );
    try {
      await _firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .set({'channelFolders': payload}, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _selectedFolderId = folder.id;
      });
    } catch (e) {
      _showSnack('Could not create folder: $e');
    }
  }

  Future<void> _createForumPost() async {
    if (!_isServer || _activeChannelType() != ServerChannelType.forum) return;
    if (_isSending) return;
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    var titleDraft = '';
    var bodyDraft = '';
    final navigator = Navigator.of(context, rootNavigator: true);
    final result = await showDialog<_ForumPostDraft>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Create forum post'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Title'),
                onChanged: (value) {
                  titleDraft = value;
                },
              ),
              const SizedBox(height: 8),
              TextField(
                minLines: 3,
                maxLines: 6,
                maxLength: 800,
                decoration: const InputDecoration(labelText: 'Body'),
                onChanged: (value) {
                  bodyDraft = value;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => navigator.pop(
              _ForumPostDraft(title: titleDraft.trim(), body: bodyDraft.trim()),
            ),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    final title = result?.title.trim() ?? '';
    final body = result?.body.trim() ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final participants = _participants.toSet().toList();
    if (!participants.contains(currentUser.uid)) {
      participants.add(currentUser.uid);
    }
    final messageText = body.isEmpty ? title : '$title\n\n$body';

    setState(() {
      _isSending = true;
    });
    try {
      await _chatService.sendRoomMessage(
        conversationId: widget.conversationId,
        messageText: messageText,
        participantIds: participants,
        channelId: _activeChannelId,
      );
      _scrollToBottom(force: true, animated: true);
    } catch (e) {
      _showSnack('Failed to post: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _addAssignmentToActiveChannel() async {
    if (!_canManage ||
        !_isServer ||
        _activeChannelType() != ServerChannelType.assignments) {
      return;
    }
    var titleDraft = '';
    var descriptionDraft = '';
    DateTime? dueDate;
    final navigator = Navigator.of(context, rootNavigator: true);
    final draft = await showDialog<_AssignmentDraft>(
      context: context,
      useRootNavigator: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create assignment'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (value) {
                    titleDraft = value;
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 600,
                  decoration: const InputDecoration(labelText: 'Description'),
                  onChanged: (value) {
                    descriptionDraft = value;
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final selected = await showDatePicker(
                        context: context,
                        firstDate: now,
                        lastDate: DateTime(now.year + 5),
                        initialDate: dueDate ?? now,
                      );
                      if (selected == null) return;
                      setDialogState(() {
                        dueDate = DateTime(
                          selected.year,
                          selected.month,
                          selected.day,
                          23,
                          59,
                        );
                      });
                    },
                    icon: const Icon(Icons.event),
                    label: Text(
                      dueDate == null
                          ? 'Set due date'
                          : 'Due ${_formatDate(dueDate!)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => navigator.pop(
                _AssignmentDraft(
                  title: titleDraft.trim(),
                  description: descriptionDraft.trim(),
                  dueDate: dueDate,
                ),
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (draft == null || draft.title.trim().isEmpty) return;

    final assignment = _ChannelAssignment(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      title: draft.title.trim(),
      description: draft.description.trim(),
      dueAt: draft.dueDate == null ? null : Timestamp.fromDate(draft.dueDate!),
      createdBy: _currentUid,
      createdAt: Timestamp.now(),
      completedBy: const [],
    );
    final updated = [..._activeAssignments(), assignment];
    final payload = _channelAssignmentsPayload(
      overrideChannelId: _activeChannelId,
      overrideAssignments: updated,
    );
    try {
      await _firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .set({'channelAssignments': payload}, SetOptions(merge: true));
    } catch (e) {
      _showSnack('Could not create assignment: $e');
    }
  }

  Future<void> _toggleAssignmentCompleted(_ChannelAssignment assignment) async {
    if (_currentUid.isEmpty) return;
    final active = _activeAssignments();
    if (active.isEmpty) return;
    final updated = <_ChannelAssignment>[];
    for (final item in active) {
      if (item.id != assignment.id) {
        updated.add(item);
        continue;
      }
      final completed = item.completedBy.toSet();
      if (completed.contains(_currentUid)) {
        completed.remove(_currentUid);
      } else {
        completed.add(_currentUid);
      }
      updated.add(item.copyWith(completedBy: completed.toList()));
    }

    final payload = _channelAssignmentsPayload(
      overrideChannelId: _activeChannelId,
      overrideAssignments: updated,
    );
    try {
      await _firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .set({'channelAssignments': payload}, SetOptions(merge: true));
    } catch (e) {
      _showSnack('Could not update assignment: $e');
    }
  }

  Future<void> _downloadFileMessage(
    String messageId,
    Map<String, dynamic> data,
  ) async {
    final fileUrl = data['fileUrl']?.toString().trim() ?? '';
    final fileName = data['fileName']?.toString().trim() ?? 'file';
    final mimeType =
        data['mimeType']?.toString().trim() ?? 'application/octet-stream';
    final fileSize = (data['fileSize'] is num)
        ? (data['fileSize'] as num).toInt()
        : int.tryParse(data['fileSize']?.toString() ?? '') ?? 0;
    if (fileUrl.isEmpty) {
      _showSnack('File URL is missing.');
      return;
    }
    try {
      final path = await _downloadService.downloadFile(
        messageId: messageId,
        url: fileUrl,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: fileSize,
      );
      await OpenFilex.open(path);
    } catch (e) {
      _showSnack('Could not download file: $e');
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.offset < 120;
  }

  void _scrollToBottom({bool force = false, bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (!force && !_isNearBottom()) return;

      final target = _scrollController.position.minScrollExtent;
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

  bool _messageMatchesActiveChannel(Map<String, dynamic> data) {
    if (!_isServer) return true;
    final channelId = data['channelId']?.toString().trim() ?? '';
    if (_activeChannelId == ServerChannel.generalId) {
      return channelId.isEmpty || channelId == ServerChannel.generalId;
    }
    if (channelId != _activeChannelId) return false;
    if (_activeChannelType() == ServerChannelType.file &&
        _selectedFolderId != null &&
        _selectedFolderId!.isNotEmpty) {
      final folderId = data['fileFolderId']?.toString().trim() ?? '';
      return folderId == _selectedFolderId;
    }
    return true;
  }

  String _activeChannelName() {
    return _activeChannel.name;
  }

  String _activeChannelType() {
    return ServerChannelType.normalize(_activeChannel.type);
  }

  bool _channelSupportsTextComposer() {
    return !_isServer ||
        ServerChannelType.supportsTextComposer(_activeChannelType());
  }

  List<_ChannelFolder> _activeFolders() {
    return _channelFolders[_activeChannelId] ?? const [];
  }

  List<_ChannelAssignment> _activeAssignments() {
    return _channelAssignments[_activeChannelId] ?? const [];
  }

  IconData _channelIcon(String type) {
    switch (ServerChannelType.normalize(type)) {
      case ServerChannelType.voice:
        return Icons.volume_up_outlined;
      case ServerChannelType.forum:
        return Icons.forum_outlined;
      case ServerChannelType.file:
        return Icons.folder_shared_outlined;
      case ServerChannelType.assignments:
        return Icons.assignment_outlined;
      case ServerChannelType.text:
      default:
        return Icons.tag;
    }
  }

  String _channelPrefix(ServerChannel channel) {
    if (ServerChannelType.normalize(channel.type) == ServerChannelType.voice) {
      return 'V';
    }
    return '#';
  }

  @override
  void dispose() {
    _conversationSub?.cancel();
    _persistedCacheDebounce?.cancel();
    _downloadService.removeListener(_handleDownloadProgressChanged);
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

    final isWideServer = _isServer && MediaQuery.of(context).size.width >= 980;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 6,
        title: Row(
          children: [
            _buildRoomAvatar(_avatarUrl, _isServer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _isServer
                        ? '${ServerChannelType.label(_activeChannelType())} | ${_channelPrefix(_activeChannel)}${_activeChannelName()} | ${_participants.length} members'
                        : 'Group | ${_participants.length} members',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_isServer && !isWideServer)
            IconButton(
              tooltip: 'Channels',
              onPressed: _showChannelPicker,
              icon: const Icon(Icons.tag),
            ),
          IconButton(
            tooltip: 'Room profile',
            onPressed: _openRoomInfo,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: isWideServer ? _buildServerDesktopLayout() : _buildCompactLayout(),
    );
  }

  Widget _buildServerDesktopLayout() {
    return Row(
      children: [
        SizedBox(width: 240, child: _buildChannelPane()),
        VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        Expanded(
          child: Column(
            children: [
              _buildChannelModeHeader(),
              if (_activeChannelType() == ServerChannelType.file)
                _buildFileChannelFoldersBar(),
              if (_activeChannelType() == ServerChannelType.assignments)
                _buildAssignmentsPanel(maxHeight: 210),
              Expanded(child: _buildMessagesView()),
              _buildInputBar(),
            ],
          ),
        ),
        VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        SizedBox(width: 250, child: _buildMembersPane()),
      ],
    );
  }

  Widget _buildCompactLayout() {
    return Column(
      children: [
        if (_isServer) _buildServerChannelBar(),
        if (_isServer) _buildChannelModeHeader(),
        if (_isServer && _activeChannelType() == ServerChannelType.file)
          _buildFileChannelFoldersBar(),
        if (_isServer && _activeChannelType() == ServerChannelType.assignments)
          _buildAssignmentsPanel(maxHeight: 180),
        Expanded(child: _buildMessagesView()),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildChannelPane() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(
              'Channels',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: _openRoomInfo,
              tooltip: 'Server profile',
            ),
          ),
          const SizedBox(height: 4),
          ..._channels.map((channel) {
            final selected = channel.id == _activeChannelId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: selected
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(_channelIcon(channel.type), size: 18),
                  title: Text(
                    '${_channelPrefix(channel)}${channel.name}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    ServerChannelType.label(channel.type),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () => unawaited(_activateChannel(channel)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMembersPane() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        children: [
          Text(
            'Members',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ..._participants.map((uid) => _buildMemberRow(uid)),
        ],
      ),
    );
  }

  Widget _buildMemberRow(String uid) {
    final data = _userCache.getCachedUser(uid);
    final name = uid == _currentUid
        ? 'You'
        : (data?['displayName']?.toString().trim().isNotEmpty == true
              ? data!['displayName'].toString().trim()
              : 'Member');
    final avatar = _normalizePhotoUrl(data?['photoUrl'] ?? data?['photoURL']);
    final isOwner = _ownerId == uid;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: Colors.grey[300],
        backgroundImage: avatar != null
            ? CachedNetworkImageProvider(avatar)
            : null,
        child: avatar == null
            ? Icon(Icons.person, size: 15, color: Colors.grey[700])
            : null,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: isOwner
          ? const Text('Owner', style: TextStyle(fontSize: 11))
          : null,
    );
  }

  Widget _buildChannelModeHeader() {
    if (!_isServer) return const SizedBox.shrink();
    final type = _activeChannelType();
    final colorScheme = Theme.of(context).colorScheme;
    String description;
    switch (type) {
      case ServerChannelType.voice:
        description = 'Voice room for live discussions.';
        break;
      case ServerChannelType.forum:
        description = 'Forum-style posts and threaded discussion.';
        break;
      case ServerChannelType.file:
        description = 'Organize folders and share downloadable files.';
        break;
      case ServerChannelType.assignments:
        description = 'Track assignments similar to team tasks.';
        break;
      case ServerChannelType.text:
      default:
        description = 'Standard text chat channel.';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(_channelIcon(type), size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${ServerChannelType.label(type)} channel',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (type == ServerChannelType.forum)
            TextButton.icon(
              onPressed: _isSending ? null : _createForumPost,
              icon: const Icon(Icons.post_add, size: 18),
              label: const Text('New post'),
            ),
          if (type == ServerChannelType.voice)
            FilledButton.icon(
              onPressed: _openingVoiceChannel
                  ? null
                  : () => unawaited(_openVoiceChannel()),
              icon: const Icon(Icons.call, size: 18),
              label: const Text('Join voice'),
            ),
        ],
      ),
    );
  }

  Widget _buildFileChannelFoldersBar() {
    final folders = _activeFolders();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Folders',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              if (_canManage)
                TextButton.icon(
                  onPressed: _addFolderToActiveChannel,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Add folder'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All files'),
                    selected: _selectedFolderId == null,
                    onSelected: (_) {
                      setState(() {
                        _selectedFolderId = null;
                      });
                    },
                  ),
                ),
                ...folders.map((folder) {
                  final selected = folder.id == _selectedFolderId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(folder.name),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _selectedFolderId = selected ? null : folder.id;
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentsPanel({required double maxHeight}) {
    final assignments = _activeAssignments();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Assignments',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              if (_canManage)
                TextButton.icon(
                  onPressed: _addAssignmentToActiveChannel,
                  icon: const Icon(Icons.assignment_add, size: 18),
                  label: const Text('Add'),
                ),
            ],
          ),
          if (assignments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'No assignments yet.',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            SizedBox(
              height: (maxHeight - 56).clamp(64, 300).toDouble(),
              child: ListView.builder(
                itemCount: assignments.length,
                itemBuilder: (context, index) {
                  final item = assignments[index];
                  final isDone = item.completedBy.contains(_currentUid);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Checkbox(
                      value: isDone,
                      onChanged: (_) => _toggleAssignmentCompleted(item),
                    ),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        decoration: isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.description.isNotEmpty)
                          Text(
                            item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        if (item.dueAt != null)
                          Text(
                            'Due ${_formatDate(item.dueAt!.toDate())}',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    trailing: Text(
                      '${item.completedBy.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildServerChannelBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _channels.map((channel) {
            final selected = channel.id == _activeChannelId;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${_channelPrefix(channel)}${channel.name}'),
                avatar: Icon(_channelIcon(channel.type), size: 15),
                selected: selected,
                onSelected: (_) => unawaited(_activateChannel(channel)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMessagesView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.getMessages(widget.conversationId),
      initialData: _cachedMessagesSnapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          if (_persistedMessages.isNotEmpty) {
            return _buildPersistedMessagesView();
          }
          if (_cacheHydrated || _persistentCacheHydrated) {
            return Center(
              child: Text(
                _isServer
                    ? 'No messages in #${_activeChannelName()} yet'
                    : 'No messages yet',
                style: TextStyle(color: Colors.grey[600]),
              ),
            );
          }
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

        final uid = _auth.currentUser?.uid ?? '';
        final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot>[];
        if (docs.isNotEmpty && snapshot.data != null) {
          _sessionMessageCache[widget.conversationId] = snapshot.data!;
          _latestLiveMessages = List<QueryDocumentSnapshot>.from(docs);
          if (uid.isNotEmpty) {
            _schedulePersistedCacheWriteFromLive(uid);
          }
        } else if (uid.isNotEmpty &&
            (snapshot.connectionState == ConnectionState.active ||
                snapshot.connectionState == ConnectionState.done ||
                snapshot.hasData)) {
          _schedulePersistedCacheClear(uid);
        }

        final visibleDocs = docs.where((doc) {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          return _messageMatchesActiveChannel(data);
        }).toList();
        final visibleIds = docs.map((doc) => doc.id).toSet();
        _decryptedCache.removeWhere((id, _) => !visibleIds.contains(id));
        _decryptFutures.removeWhere((id, _) => !visibleIds.contains(id));
        _decryptInputSignatures.removeWhere(
          (id, _) => !visibleIds.contains(id),
        );

        if (visibleDocs.isEmpty) {
          if (_persistedMessages.isNotEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return _buildPersistedMessagesView();
          }
          return Center(
            child: Text(
              _isServer
                  ? 'No messages in #${_activeChannelName()} yet'
                  : 'No messages yet',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }

        if (_isNearBottom()) {
          _scrollToBottom();
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
          itemCount: visibleDocs.length,
          itemBuilder: (context, index) {
            final reversedIndex = visibleDocs.length - 1 - index;
            final doc = visibleDocs[reversedIndex];
            final data = Map<String, dynamic>.from(doc.data() as Map);
            return _buildMessageTile(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildMessageTile(String messageId, Map<String, dynamic> data) {
    final senderId = data['senderId']?.toString() ?? '';
    final isMe = senderId == _currentUid;
    final type = data['type']?.toString() ?? 'text';
    final timestamp = data['timestamp'] is Timestamp
        ? data['timestamp'] as Timestamp
        : (data['clientTimestamp'] is Timestamp
              ? data['clientTimestamp'] as Timestamp
              : _timestampFromMs(data['timestampMs']));

    final senderData = _userCache.getCachedUser(senderId);
    final senderName = isMe
        ? 'You'
        : (senderData?['displayName']?.toString().trim().isNotEmpty == true
              ? senderData!['displayName'].toString().trim()
              : 'Member');
    final senderAvatar = _normalizePhotoUrl(
      senderData?['photoUrl'] ?? senderData?['photoURL'],
    );

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
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              CircleAvatar(
                radius: 13,
                backgroundColor: Colors.grey[300],
                backgroundImage: senderAvatar != null
                    ? CachedNetworkImageProvider(senderAvatar)
                    : null,
                child: senderAvatar == null
                    ? Icon(Icons.person, size: 14, color: Colors.grey[700])
                    : null,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
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
                    _buildMessageBody(
                      messageId: messageId,
                      type: type,
                      data: data,
                      textColor: textColor,
                    ),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBody({
    required String messageId,
    required String type,
    required Map<String, dynamic> data,
    required Color textColor,
  }) {
    final themeService = context.watch<ThemeService>();
    Widget buildTextBody(String text) {
      final trimmedText = text.trim();
      final looksLikeSticker =
          trimmedText.isNotEmpty &&
          trimmedText.runes.length <= 3 &&
          !trimmedText.contains(RegExp(r'[A-Za-z0-9]')) &&
          !trimmedText.contains(' ');
      if (looksLikeSticker) {
        return Text(
          trimmedText,
          style: const TextStyle(fontSize: 44, height: 1.05),
        );
      }

      if (_isServer && _activeChannelType() == ServerChannelType.forum) {
        final lines = trimmedText.split('\n');
        final title = lines.first.trim();
        final body = lines.skip(1).join('\n').trim();
        if (body.isNotEmpty && title.isNotEmpty && title.length <= 120) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              ChatMessageText(
                text: body,
                style: TextStyle(color: textColor, fontSize: 14),
                linkStyle: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
                showPreviews: themeService.showLinkPreviews,
                previewBackgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh,
                previewBorderColor: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                previewTitleColor: textColor,
                previewMetaColor: textColor.withValues(alpha: 0.78),
              ),
            ],
          );
        }
      }
      return ChatMessageText(
        text: text,
        style: TextStyle(color: textColor, fontSize: 15),
        linkStyle: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
        showPreviews: themeService.showLinkPreviews,
        previewBackgroundColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHigh,
        previewBorderColor: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        previewTitleColor: textColor,
        previewMetaColor: textColor.withValues(alpha: 0.78),
      );
    }

    if (type == 'file') {
      final fileName = data['fileName']?.toString().trim();
      final caption = data['caption']?.toString().trim() ?? '';
      final folderName = data['fileFolderName']?.toString().trim() ?? '';
      final fileUrl = data['fileUrl']?.toString().trim() ?? '';
      final mimeType = data['mimeType']?.toString().trim().toLowerCase() ?? '';
      final isImage = mimeType.startsWith('image/');
      final isGif =
          mimeType.contains('gif') || fileUrl.toLowerCase().endsWith('.gif');
      final fileSize = data['fileSize'] is int
          ? data['fileSize'] as int
          : int.tryParse(data['fileSize']?.toString() ?? '') ?? 0;
      final progress = _downloadService.getProgress(messageId);
      final isDownloading = progress?.status == DownloadStatus.downloading;
      final isDownloaded = progress?.status == DownloadStatus.completed;
      final localPath = progress?.localPath;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isImage && fileUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImageViewerScreen(
                        imageUrl: fileUrl,
                        localPath: localPath,
                        fileName: fileName ?? 'Image',
                        fileSize: fileSize,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 280,
                      minWidth: 120,
                    ),
                    child: isGif
                        ? Image.network(
                            fileUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.black12,
                              height: 160,
                              width: double.infinity,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: fileUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.black12,
                              height: 160,
                              width: double.infinity,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          Text(
            (fileName != null && fileName.isNotEmpty)
                ? 'Shared file: $fileName'
                : 'Shared a file',
            style: TextStyle(color: textColor),
          ),
          if (folderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Folder: $folderName',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
            ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ChatMessageText(
                text: caption,
                style: TextStyle(color: textColor),
                linkStyle: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
                showPreviews: themeService.showLinkPreviews,
                maxPreviewCards: 1,
                previewBackgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh,
                previewBorderColor: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                previewTitleColor: textColor,
                previewMetaColor: textColor.withValues(alpha: 0.78),
              ),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: textColor,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: fileUrl.isEmpty || isDownloading
                ? null
                : () => _downloadFileMessage(messageId, data),
            icon: isDownloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isDownloaded ? Icons.open_in_new : Icons.download,
                    size: 16,
                  ),
            label: Text(
              isDownloading
                  ? 'Downloading...'
                  : (isDownloaded ? 'Open file' : 'Download file'),
            ),
          ),
        ],
      );
    }

    final signature = _decryptSignature(data);
    if (_decryptInputSignatures[messageId] != signature) {
      _decryptInputSignatures[messageId] = signature;
      _decryptFutures.remove(messageId);
      _decryptedCache.remove(messageId);
    }

    final persistedText = _persistedTextForMessage(messageId);
    final cachedText = _decryptedCache[messageId]?.trim() ?? '';

    if (cachedText.isNotEmpty) {
      return buildTextBody(cachedText);
    }

    final hasCipherPayload =
        (data['ciphertext'] is String &&
            (data['ciphertext'] as String).trim().isNotEmpty) ||
        (data['senderCiphertext'] is String &&
            (data['senderCiphertext'] as String).trim().isNotEmpty) ||
        data['ciphertexts'] is Map ||
        data['senderCiphertexts'] is Map ||
        data['ciphertextsByKey'] is Map ||
        data['senderCiphertextsByKey'] is Map;
    if (persistedText.isNotEmpty && !hasCipherPayload) {
      return buildTextBody(persistedText);
    }

    final future = _decryptFutures.putIfAbsent(
      messageId,
      () => _chatService.decryptMessage(messageData: data).then((value) {
        final text = value.trim();
        if (text.isNotEmpty) {
          _decryptedCache[messageId] = text;
          final uid = _auth.currentUser?.uid ?? '';
          if (uid.isNotEmpty) {
            _schedulePersistedCacheWriteFromLive(uid);
          }
        }
        return text;
      }),
    );

    return FutureBuilder<String>(
      future: future,
      builder: (context, snapshot) {
        final text =
            snapshot.data?.trim() ??
            _decryptedCache[messageId]?.trim() ??
            persistedText;
        return buildTextBody(text.isNotEmpty ? text : 'Encrypted message');
      },
    );
  }

  Widget _buildInputBar() {
    final channelType = _activeChannelType();
    if (_isServer && channelType == ServerChannelType.voice) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.volume_up_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Join voice to talk with members in this channel.'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _openingVoiceChannel
                    ? null
                    : () => unawaited(_openVoiceChannel()),
                icon: const Icon(Icons.call, size: 18),
                label: const Text('Join'),
              ),
            ],
          ),
        ),
      );
    }

    final channelHint = _isServer
        ? '${_channelPrefix(_activeChannel)}${_activeChannelName()}'
        : _title;
    final canSendText = !_isServer || _channelSupportsTextComposer();
    final isFileChannel = _isServer && channelType == ServerChannelType.file;
    final isForumChannel = _isServer && channelType == ServerChannelType.forum;
    final isAssignmentsChannel =
        _isServer && channelType == ServerChannelType.assignments;
    final hint = isFileChannel
        ? 'Add optional file note'
        : (isAssignmentsChannel
              ? 'Discuss assignments'
              : 'Message $channelHint');

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Row(
          children: [
            if (isForumChannel)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  tooltip: 'New post',
                  onPressed: _isSending ? null : _createForumPost,
                  icon: const Icon(Icons.post_add),
                ),
              ),
            if (isAssignmentsChannel && _canManage)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  tooltip: 'Create assignment',
                  onPressed: _isSending ? null : _addAssignmentToActiveChannel,
                  icon: const Icon(Icons.assignment_add),
                ),
              ),
            if (!isFileChannel && canSendText)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  tooltip: 'Stickers',
                  onPressed: _isSending ? null : _showStickerPicker,
                  icon: const Icon(Icons.emoji_emotions_outlined),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                enabled: canSendText || isFileChannel,
                textInputAction: isFileChannel
                    ? TextInputAction.done
                    : TextInputAction.send,
                onSubmitted: (_) {
                  if (isFileChannel) {
                    _sendFileToActiveChannel();
                    return;
                  }
                  if (canSendText) {
                    _sendMessage();
                  }
                },
                decoration: InputDecoration(
                  hintText: hint,
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
              onPressed: _isSending
                  ? null
                  : (isFileChannel
                        ? _sendFileToActiveChannel
                        : (canSendText ? _sendMessage : null)),
              icon: _isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(isFileChannel ? Icons.upload_file : Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomAvatar(String? photoUrl, bool isServer) {
    if (photoUrl == null || photoUrl.isEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.grey[300],
        child: Icon(
          isServer ? Icons.hub : Icons.group,
          color: Colors.grey[700],
          size: 19,
        ),
      );
    }
    return ClipOval(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          fit: BoxFit.cover,
          memCacheWidth: 180,
          memCacheHeight: 180,
          placeholder: (context, url) => Container(color: Colors.grey[300]),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey[300],
            alignment: Alignment.center,
            child: Icon(
              isServer ? Icons.hub : Icons.group,
              color: Colors.grey[700],
              size: 19,
            ),
          ),
        ),
      ),
    );
  }

  String? _normalizePhotoUrl(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
      return null;
    }
    return text;
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
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

class _ChannelFolder {
  final String id;
  final String name;
  final String createdBy;
  final Timestamp createdAt;

  const _ChannelFolder({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
  });

  factory _ChannelFolder.fromMap(Map<String, dynamic> map) {
    final createdAt = map['createdAt'];
    return _ChannelFolder(
      id: map['id']?.toString().trim() ?? '',
      name: map['name']?.toString().trim() ?? '',
      createdBy: map['createdBy']?.toString().trim() ?? '',
      createdAt: createdAt is Timestamp ? createdAt : Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'createdBy': createdBy,
      'createdAt': createdAt,
    };
  }
}

class _ChannelAssignment {
  final String id;
  final String title;
  final String description;
  final Timestamp? dueAt;
  final String createdBy;
  final Timestamp createdAt;
  final List<String> completedBy;

  const _ChannelAssignment({
    required this.id,
    required this.title,
    required this.description,
    required this.dueAt,
    required this.createdBy,
    required this.createdAt,
    required this.completedBy,
  });

  factory _ChannelAssignment.fromMap(Map<String, dynamic> map) {
    final dueAtRaw = map['dueAt'];
    final createdAtRaw = map['createdAt'];
    final completedRaw = map['completedBy'];
    final completedBy = completedRaw is List
        ? completedRaw
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toList()
        : <String>[];
    return _ChannelAssignment(
      id: map['id']?.toString().trim() ?? '',
      title: map['title']?.toString().trim() ?? '',
      description: map['description']?.toString().trim() ?? '',
      dueAt: dueAtRaw is Timestamp ? dueAtRaw : null,
      createdBy: map['createdBy']?.toString().trim() ?? '',
      createdAt: createdAtRaw is Timestamp ? createdAtRaw : Timestamp.now(),
      completedBy: completedBy,
    );
  }

  _ChannelAssignment copyWith({List<String>? completedBy}) {
    return _ChannelAssignment(
      id: id,
      title: title,
      description: description,
      dueAt: dueAt,
      createdBy: createdBy,
      createdAt: createdAt,
      completedBy: completedBy ?? this.completedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'dueAt': dueAt,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'completedBy': completedBy,
    };
  }
}

class _ForumPostDraft {
  final String title;
  final String body;

  const _ForumPostDraft({required this.title, required this.body});
}

class _AssignmentDraft {
  final String title;
  final String description;
  final DateTime? dueDate;

  const _AssignmentDraft({
    required this.title,
    required this.description,
    required this.dueDate,
  });
}
