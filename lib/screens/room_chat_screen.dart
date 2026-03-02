import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service_e2ee.dart';
import '../services/message_cache_service.dart';
import '../services/user_cache_service.dart';
import 'room_info_screen.dart';

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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  final UserCacheService _userCache = UserCacheService();
  final MessageCacheService _messageCache = MessageCacheService();
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
  List<_ServerChannel> _channels = const [_ServerChannel.general];
  String _activeChannelId = _ServerChannel.generalId;
  String _title = '';
  String? _avatarUrl;
  String _ownerId = '';
  bool _isInitializing = true;
  bool _isSending = false;
  String? _error;

  bool get _isServer => widget.conversationType == 'server';
  String get _currentUid => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _title = widget.roomTitle.trim().isEmpty ? 'Room' : widget.roomTitle.trim();
    _participants = widget.initialParticipants.toSet().toList();
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
          final participants = _parseParticipants(data['participants']);
          final channels = _parseChannels(data['channels']);

          _warmParticipants(participants);

          setState(() {
            if (title.isNotEmpty) _title = title;
            _avatarUrl = avatarUrl;
            _ownerId = ownerId;
            if (participants.isNotEmpty) _participants = participants;
            _channels = channels;
            if (!_channels.any((channel) => channel.id == _activeChannelId)) {
              _activeChannelId = _ServerChannel.generalId;
            }
          });
        });
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

  List<_ServerChannel> _parseChannels(dynamic raw) {
    if (!_isServer) return const [_ServerChannel.general];

    final parsed = <_ServerChannel>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id']?.toString().trim() ?? '';
        final name = map['name']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty) continue;
        parsed.add(_ServerChannel(id: id, name: name));
      }
    }

    if (parsed.isEmpty) return const [_ServerChannel.general];

    final unique = <String, _ServerChannel>{};
    for (final channel in parsed) {
      unique[channel.id] = channel;
    }
    unique.putIfAbsent(_ServerChannel.generalId, () => _ServerChannel.general);
    return unique.values.toList();
  }

  void _warmParticipants(List<String> ids) {
    final targets = ids.where((id) => id != _currentUid).toSet();
    if (targets.isEmpty) return;
    _userCache.warmUsers(targets, listen: false);
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
                  leading: const Icon(Icons.tag),
                  title: Text(channel.name),
                  trailing: isSelected ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(sheetContext, channel.id),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == _activeChannelId) return;
    setState(() {
      _activeChannelId = selected;
    });
    _scrollToBottom(force: true);
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
    if (_activeChannelId == _ServerChannel.generalId) {
      return channelId.isEmpty || channelId == _ServerChannel.generalId;
    }
    return channelId == _activeChannelId;
  }

  String _activeChannelName() {
    for (final channel in _channels) {
      if (channel.id == _activeChannelId) {
        return channel.name;
      }
    }
    return _ServerChannel.general.name;
  }

  @override
  void dispose() {
    _conversationSub?.cancel();
    _persistedCacheDebounce?.cancel();
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
                        ? '#${_activeChannelName()} • ${_participants.length} members'
                        : 'Group • ${_participants.length} members',
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
              'Text channels',
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
                  leading: const Icon(Icons.tag, size: 18),
                  title: Text(
                    channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  onTap: () {
                    if (_activeChannelId == channel.id) return;
                    setState(() {
                      _activeChannelId = channel.id;
                    });
                    _scrollToBottom(force: true);
                  },
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
                label: Text('#${channel.name}'),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _activeChannelId = channel.id;
                  });
                  _scrollToBottom(force: true);
                },
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
    if (type == 'file') {
      final fileName = data['fileName']?.toString().trim();
      final caption = data['caption']?.toString().trim() ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (fileName != null && fileName.isNotEmpty)
                ? 'Shared file: $fileName'
                : 'Shared a file',
            style: TextStyle(color: textColor),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(caption, style: TextStyle(color: textColor)),
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
      return Text(cachedText, style: TextStyle(color: textColor, fontSize: 15));
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
      return Text(
        persistedText,
        style: TextStyle(color: textColor, fontSize: 15),
      );
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
        return Text(
          text.isNotEmpty ? text : 'Encrypted message',
          style: TextStyle(color: textColor, fontSize: 15),
        );
      },
    );
  }

  Widget _buildInputBar() {
    final channelHint = _isServer ? '#${_activeChannelName()}' : _title;
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
                  hintText: 'Message $channelHint',
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
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.grey[300],
      backgroundImage: CachedNetworkImageProvider(photoUrl),
    );
  }

  String? _normalizePhotoUrl(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return null;
    return text;
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

class _ServerChannel {
  final String id;
  final String name;

  const _ServerChannel({required this.id, required this.name});

  static const String generalId = 'general';
  static const _ServerChannel general = _ServerChannel(
    id: generalId,
    name: 'general',
  );
}
