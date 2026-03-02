import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent cache for recent chat messages per user/conversation.
class MessageCacheService {
  static final MessageCacheService _instance = MessageCacheService._internal();
  factory MessageCacheService() => _instance;
  MessageCacheService._internal();

  static const int _maxMessagesPerConversation = 260;

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

    final limited = messages.length <= _maxMessagesPerConversation
        ? List<Map<String, dynamic>>.from(messages)
        : messages
              .sublist(messages.length - _maxMessagesPerConversation)
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

    final reactions = _normalizeStringMap(input['reactions']);
    if (reactions.isNotEmpty) item['reactions'] = reactions;

    final caption = input['caption']?.toString().trim();
    if (caption != null && caption.isNotEmpty) item['caption'] = caption;

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
      return item;
    }

    final text = input['text']?.toString() ?? '';
    if (text.isNotEmpty) {
      item['text'] = text;
    }

    final replyToText = input['replyToText']?.toString();
    if (replyToText != null && replyToText.trim().isNotEmpty) {
      item['replyToText'] = replyToText.trim();
    }

    final replyToSenderId = input['replyToSenderId']?.toString();
    if (replyToSenderId != null && replyToSenderId.trim().isNotEmpty) {
      item['replyToSenderId'] = replyToSenderId.trim();
    }

    if (input['edited'] is bool) {
      item['edited'] = input['edited'] as bool;
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

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Map<String, String> _normalizeStringMap(dynamic raw) {
    if (raw is! Map) return const {};
    final normalized = <String, String>{};
    raw.forEach((key, value) {
      final k = key.toString().trim();
      final v = value?.toString().trim() ?? '';
      if (k.isEmpty || v.isEmpty) return;
      normalized[k] = v;
    });
    return normalized;
  }
}
