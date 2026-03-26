import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent cache for recent chat messages per user/conversation.
class MessageCacheService {
  static final MessageCacheService _instance = MessageCacheService._internal();
  factory MessageCacheService() => _instance;
  MessageCacheService._internal();

  static const int maxMessagesPerConversation = 260;

  Future<List<Map<String, dynamic>>> buildCacheItemsFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    Future<String?> Function(Map<String, dynamic> message)? resolveText,
  }) async {
    final items = <Map<String, dynamic>>[];

    for (final doc in docs) {
      final data = doc.data();
      final message = Map<String, dynamic>.from(data);
      final resolvedText = resolveText == null
          ? null
          : await resolveText(message);
      final item = buildCacheItemFromMessage(
        id: doc.id,
        message: message,
        resolvedText: resolvedText,
      );
      if (item.isNotEmpty) {
        items.add(item);
      }
    }

    return items;
  }

  Map<String, dynamic> buildCacheItemFromMessage({
    required String id,
    required Map<String, dynamic> message,
    String? resolvedText,
  }) {
    final normalizedId = id.trim();
    final senderId = message['senderId']?.toString().trim() ?? '';
    if (normalizedId.isEmpty || senderId.isEmpty) return const {};

    final type = message['type']?.toString().trim() ?? 'text';
    final item = <String, dynamic>{
      'id': normalizedId,
      'type': type,
      'senderId': senderId,
    };

    final timestamp = _timestampFrom(message['timestamp']) ??
        _timestampFrom(message['clientTimestamp']);
    if (timestamp != null) {
      item['timestampMs'] = timestamp.millisecondsSinceEpoch;
    }

    if (message['read'] is bool) {
      item['read'] = message['read'] as bool;
    }

    final readAt = _timestampFrom(message['readAt']);
    if (readAt != null) {
      item['readAtMs'] = readAt.millisecondsSinceEpoch;
    }

    final reactions = _normalizeReactionsMap(message['reactions']);
    if (reactions.isNotEmpty) {
      item['reactions'] = reactions;
    }

    _copyStringField(message, item, 'channelId');
    _copyStringField(message, item, 'caption');
    _copyStringField(message, item, 'replyToText');
    _copyStringField(message, item, 'replyToSenderId');

    if (message['edited'] is bool) {
      item['edited'] = message['edited'] as bool;
    }

    final callSummary = message['callSummary'];
    if (callSummary is Map) {
      final normalizedCallSummary = Map<String, dynamic>.from(callSummary);
      if (normalizedCallSummary.isNotEmpty) {
        item['callSummary'] = normalizedCallSummary;
      }
    }

    if (type == 'file') {
      final merged = _buildFilePayload(message, resolvedText);
      if (merged.isNotEmpty) {
        item.addAll(merged);
      }
      return item;
    }

    if (type == 'sticker') {
      final merged = _buildStickerPayload(message, resolvedText);
      if (merged.isNotEmpty) {
        item.addAll(merged);
      }
      return item;
    }

    final text = _firstNonEmptyString([
      resolvedText,
      message['text'],
      message['message'],
    ]);
    if (text.isNotEmpty) {
      item['text'] = text;
    }

    if (!item.containsKey('text') && !item.containsKey('callSummary')) {
      return const {};
    }

    return item;
  }

  Future<List<Map<String, dynamic>>> loadConversationMessages(
    String uid,
    String conversationId,
  ) async {
    if (uid.trim().isEmpty || conversationId.trim().isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(uid, conversationId));
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final result = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final normalized = _normalizeCacheItem(map);
        if (normalized.isNotEmpty) result.add(normalized);
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveConversationMessages(
    String uid,
    String conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    if (uid.trim().isEmpty || conversationId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (messages.isEmpty) {
      await clearConversation(uid, conversationId);
      return;
    }

    final limited = messages.length <= maxMessagesPerConversation
        ? List<Map<String, dynamic>>.from(messages)
        : messages
              .sublist(messages.length - maxMessagesPerConversation)
              .toList();
    final payload = <Map<String, dynamic>>[];
    for (final message in limited) {
      final normalized = _normalizeCacheItem(message);
      if (normalized.isEmpty) continue;
      payload.add(normalized);
    }
    if (payload.isEmpty) {
      await clearConversation(uid, conversationId);
      return;
    }

    await prefs.setString(_cacheKey(uid, conversationId), jsonEncode(payload));
    await _touchConversationIndex(prefs, uid, conversationId);
  }

  Future<void> clearConversation(String uid, String conversationId) async {
    if (uid.trim().isEmpty || conversationId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey(uid, conversationId));

    final index = prefs.getStringList(_indexKey(uid)) ?? <String>[];
    if (index.remove(conversationId)) {
      await prefs.setStringList(_indexKey(uid), index);
    }
  }

  Future<void> clearForUser(String uid) async {
    if (uid.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey(uid)) ?? <String>[];
    for (final conversationId in index) {
      await prefs.remove(_cacheKey(uid, conversationId));
    }
    await prefs.remove(_indexKey(uid));
  }

  String _cacheKey(String uid, String conversationId) {
    return 'message_cache_${uid}_$conversationId';
  }

  String _indexKey(String uid) {
    return 'message_cache_index_$uid';
  }

  Future<void> _touchConversationIndex(
    SharedPreferences prefs,
    String uid,
    String conversationId,
  ) async {
    final index = prefs.getStringList(_indexKey(uid)) ?? <String>[];
    if (!index.contains(conversationId)) {
      index.add(conversationId);
      await prefs.setStringList(_indexKey(uid), index);
    }
  }

  Map<String, dynamic> _normalizeCacheItem(Map<String, dynamic> input) {
    final id = input['id']?.toString().trim() ?? '';
    if (id.isEmpty) return const {};

    final type = input['type']?.toString().trim();
    if (type == null || type.isEmpty) return const {};

    final senderId = input['senderId']?.toString().trim() ?? '';
    if (senderId.isEmpty) return const {};

    final item = <String, dynamic>{
      'id': id,
      'type': type,
      'senderId': senderId,
    };

    final timestampMs = _asInt(input['timestampMs']);
    if (timestampMs != null) item['timestampMs'] = timestampMs;

    final read = input['read'];
    if (read is bool) item['read'] = read;

    final readAtMs = _asInt(input['readAtMs']);
    if (readAtMs != null) item['readAtMs'] = readAtMs;

    final reactions = _normalizeReactionsMap(input['reactions']);
    if (reactions.isNotEmpty) item['reactions'] = reactions;

    final caption = input['caption']?.toString().trim();
    if (caption != null && caption.isNotEmpty) item['caption'] = caption;

    final channelId = input['channelId']?.toString().trim();
    if (channelId != null && channelId.isNotEmpty) item['channelId'] = channelId;
    final replyToText = input['replyToText']?.toString().trim();
    if (replyToText != null && replyToText.isNotEmpty) {
      item['replyToText'] = replyToText;
    }
    final replyToSenderId = input['replyToSenderId']?.toString().trim();
    if (replyToSenderId != null && replyToSenderId.isNotEmpty) {
      item['replyToSenderId'] = replyToSenderId;
    }
    if (input['edited'] is bool) {
      item['edited'] = input['edited'] as bool;
    }

    if (type == 'file') {
      final fileName = input['fileName']?.toString().trim() ?? 'File';
      item['fileName'] = fileName;

      final fileSize = _asInt(input['fileSize']) ?? 0;
      item['fileSize'] = fileSize;

      final fileUrl = input['fileUrl']?.toString().trim();
      if (fileUrl != null && fileUrl.isNotEmpty) item['fileUrl'] = fileUrl;

      final mimeType = input['mimeType']?.toString().trim();
      if (mimeType != null && mimeType.isNotEmpty) {
        item['mimeType'] = mimeType;
      }
      final path = input['path']?.toString().trim();
      if (path != null && path.isNotEmpty) item['path'] = path;
      final storagePath = input['storagePath']?.toString().trim();
      if (storagePath != null && storagePath.isNotEmpty) {
        item['storagePath'] = storagePath;
      }
      final fileFolderId = input['fileFolderId']?.toString().trim();
      if (fileFolderId != null && fileFolderId.isNotEmpty) {
        item['fileFolderId'] = fileFolderId;
      }
      final fileFolderName = input['fileFolderName']?.toString().trim();
      if (fileFolderName != null && fileFolderName.isNotEmpty) {
        item['fileFolderName'] = fileFolderName;
      }
      return item;
    }

    final stickerUrl = input['stickerUrl']?.toString().trim();
    if (stickerUrl != null && stickerUrl.isNotEmpty) {
      item['stickerUrl'] = stickerUrl;
    }
    final stickerFallback = input['stickerFallback']?.toString().trim();
    if (stickerFallback != null && stickerFallback.isNotEmpty) {
      item['stickerFallback'] = stickerFallback;
    }
    final stickerId = input['stickerId']?.toString().trim();
    if (stickerId != null && stickerId.isNotEmpty) {
      item['stickerId'] = stickerId;
    }
    final stickerPack = input['stickerPack']?.toString().trim();
    if (stickerPack != null && stickerPack.isNotEmpty) {
      item['stickerPack'] = stickerPack;
    }
    final stickerLabel = input['stickerLabel']?.toString().trim();
    if (stickerLabel != null && stickerLabel.isNotEmpty) {
      item['stickerLabel'] = stickerLabel;
    }

    final text = input['text']?.toString() ?? '';
    if (text.isNotEmpty) {
      item['text'] = text;
    }

    final callSummary = input['callSummary'];
    if (callSummary is Map) {
      final normalizedCallSummary = Map<String, dynamic>.from(callSummary);
      if (normalizedCallSummary.isNotEmpty) {
        item['callSummary'] = normalizedCallSummary;
      }
    }

    if (!item.containsKey('text') && !item.containsKey('callSummary')) {
      return const {};
    }

    return item;
  }

  Map<String, dynamic> _buildFilePayload(
    Map<String, dynamic> message,
    String? resolvedText,
  ) {
    final item = <String, dynamic>{};
    _copyStringField(message, item, 'fileName');
    _copyIntField(message, item, 'fileSize');
    _copyStringField(message, item, 'fileUrl');
    _copyStringField(message, item, 'mimeType', aliases: ['mime']);
    _copyStringField(message, item, 'path');
    _copyStringField(message, item, 'storagePath');
    _copyStringField(message, item, 'fileFolderId');
    _copyStringField(message, item, 'fileFolderName');
    _copyStringField(message, item, 'caption');

    final parsed = _parseJsonMap(resolvedText);
    if (parsed != null) {
      _copyFromParsed(item, parsed, 'fileName', aliases: ['name']);
      _copyFromParsed(item, parsed, 'fileSize', asInt: true, aliases: ['size']);
      _copyFromParsed(item, parsed, 'fileUrl', aliases: ['url']);
      _copyFromParsed(item, parsed, 'mimeType', aliases: ['mime', 'contentType']);
      _copyFromParsed(item, parsed, 'path');
      _copyFromParsed(item, parsed, 'storagePath');
      _copyFromParsed(
        item,
        parsed,
        'fileFolderId',
        aliases: ['folderId', 'folder'],
      );
      _copyFromParsed(
        item,
        parsed,
        'fileFolderName',
        aliases: ['folderName'],
      );
      _copyFromParsed(item, parsed, 'caption');
    }

    if (item.containsKey('fileName')) {
      return item;
    }

    return const {};
  }

  Map<String, dynamic> _buildStickerPayload(
    Map<String, dynamic> message,
    String? resolvedText,
  ) {
    final item = <String, dynamic>{};
    _copyStringField(message, item, 'stickerUrl');
    _copyStringField(message, item, 'stickerFallback');
    _copyStringField(message, item, 'stickerId');
    _copyStringField(message, item, 'stickerPack');
    _copyStringField(message, item, 'stickerLabel');

    final parsed = _parseJsonMap(resolvedText);
    if (parsed != null) {
      _copyFromParsed(item, parsed, 'stickerUrl', aliases: ['url']);
      _copyFromParsed(item, parsed, 'stickerFallback', aliases: ['fallback']);
      _copyFromParsed(item, parsed, 'stickerId', aliases: ['id']);
      _copyFromParsed(item, parsed, 'stickerPack', aliases: ['pack']);
      _copyFromParsed(item, parsed, 'stickerLabel', aliases: ['label']);
    }

    final fallback = _firstNonEmptyString([
      item['stickerFallback'],
      message['stickerFallback'],
      message['sticker'],
      parsed?['fallback'],
      resolvedText,
    ]);
    if (fallback.isNotEmpty) {
      item['text'] = fallback;
    }

    if (item.containsKey('stickerUrl') || item.containsKey('text')) {
      return item;
    }
    return const {};
  }

  Map<String, dynamic>? _parseJsonMap(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return null;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  void _copyStringField(
    Map<String, dynamic> source,
    Map<String, dynamic> target,
    String key, {
    List<String> aliases = const [],
  }) {
    final value = _firstNonEmptyString([
      source[key],
      for (final alias in aliases) source[alias],
    ]);
    if (value.isNotEmpty) {
      target[key] = value;
    }
  }

  void _copyIntField(
    Map<String, dynamic> source,
    Map<String, dynamic> target,
    String key, {
    List<String> aliases = const [],
  }) {
    final value = _intFrom(source[key]) ?? _intFromAliases(source, aliases);
    if (value != null) {
      target[key] = value;
    }
  }

  void _copyFromParsed(
    Map<String, dynamic> target,
    Map<String, dynamic> parsed,
    String key, {
    List<String> aliases = const [],
    bool asInt = false,
  }) {
    if (asInt) {
      final value = _intFrom(parsed[key]) ?? _intFromAliases(parsed, aliases);
      if (value != null) {
        target[key] = value;
      }
      return;
    }

    final value = _firstNonEmptyString([
      parsed[key],
      for (final alias in aliases) parsed[alias],
    ]);
    if (value.isNotEmpty) {
      target[key] = value;
    }
  }

  int? _intFrom(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value == null ? '' : value.toString());
  }

  int? _intFromAliases(Map<String, dynamic> source, List<String> aliases) {
    for (final alias in aliases) {
      final value = _intFrom(source[alias]);
      if (value != null) return value;
    }
    return null;
  }

  Timestamp? _timestampFrom(dynamic value) {
    if (value is Timestamp) return value;
    if (value is int) {
      return Timestamp.fromMillisecondsSinceEpoch(value);
    }
    if (value is num) {
      return Timestamp.fromMillisecondsSinceEpoch(value.toInt());
    }
    final parsed = int.tryParse(value == null ? '' : value.toString());
    if (parsed == null) return null;
    return Timestamp.fromMillisecondsSinceEpoch(parsed);
  }

  String _firstNonEmptyString(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value == null ? '' : value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value == null ? '' : value.toString());
  }

  Map<String, List<String>> _normalizeReactionsMap(dynamic raw) {
    if (raw is! Map) return const {};
    final normalized = <String, List<String>>{};
    raw.forEach((key, value) {
      final k = key.toString().trim();
      if (k.isEmpty) return;
      final emojis = <String>{};
      if (value is String) {
        final v = value.trim();
        if (v.isNotEmpty) emojis.add(v);
      } else if (value is List) {
        for (final item in value) {
          final v = item?.toString().trim() ?? '';
          if (v.isNotEmpty) emojis.add(v);
        }
      } else {
        final v = value?.toString().trim() ?? '';
        if (v.isNotEmpty) emojis.add(v);
      }
      if (emojis.isEmpty) return;
      normalized[k] = emojis.toList();
    });
    return normalized;
  }
}
