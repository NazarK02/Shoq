import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache for conversation list data shown on the Home screen.
class ConversationCacheService {
  static final ConversationCacheService _instance =
      ConversationCacheService._internal();
  factory ConversationCacheService() => _instance;
  ConversationCacheService._internal();

  static const String _indexKey = 'conversation_cache_index';
  static const int _maxConversations = 200;

  Future<List<Map<String, dynamic>>> loadConversations(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('conversation_cache_$uid');
    if (raw == null) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      final result = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final normalized = _fromCacheItem(map);
        if (normalized.isNotEmpty) result.add(normalized);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConversations(
    String uid,
    List<Map<String, dynamic>> conversations,
  ) async {
    if (conversations.isEmpty) {
      await clearForUser(uid);
      return;
    }

    final limited = conversations.take(_maxConversations).toList();
    final payload = <Map<String, dynamic>>[];

    for (final c in limited) {
      final cacheItem = _toCacheItem(c);
      if (cacheItem.isNotEmpty) payload.add(cacheItem);
    }

    if (payload.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conversation_cache_$uid', jsonEncode(payload));
    await _touchIndex(prefs, uid);
  }

  List<Map<String, dynamic>> buildCacheItemsFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final items = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final data = doc.data();
      items.add({...data, 'id': doc.id});
    }
    return items;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey) ?? <String>[];
    for (final uid in index) {
      await prefs.remove('conversation_cache_$uid');
    }
    await prefs.remove(_indexKey);
  }

  Future<void> clearForUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('conversation_cache_$uid');
    final list = prefs.getStringList(_indexKey) ?? <String>[];
    if (list.remove(uid)) {
      await prefs.setStringList(_indexKey, list);
    }
  }

  Map<String, dynamic> _toCacheItem(Map<String, dynamic> data) {
    final id = data['id'];
    if (id is! String || id.isEmpty) return {};

    final participants = data['participants'];
    final participantsList = participants is List
        ? participants.whereType<String>().toList()
        : <String>[];
    if (participantsList.isEmpty) return {};

    final item = <String, dynamic>{'id': id, 'participants': participantsList};

    final type = data['type']?.toString().trim() ?? '';
    if (type.isNotEmpty) {
      item['type'] = type;
    }
    final title = data['title']?.toString().trim() ?? '';
    if (title.isNotEmpty) {
      item['title'] = title;
    }
    final avatarUrl = data['avatarUrl']?.toString().trim() ?? '';
    if (avatarUrl.isNotEmpty) {
      item['avatarUrl'] = avatarUrl;
    }

    if (data['lastMessage'] != null) {
      item['lastMessage'] = data['lastMessage'];
    }
    if (data['lastSenderId'] != null) {
      item['lastSenderId'] = data['lastSenderId'];
    }
    if (data['hasMessages'] != null) {
      item['hasMessages'] = data['hasMessages'];
    }

    final lastMessageTime = data['lastMessageTime'];
    if (lastMessageTime is Timestamp) {
      item['lastMessageTime'] = lastMessageTime.millisecondsSinceEpoch;
    } else if (lastMessageTime is int) {
      item['lastMessageTime'] = lastMessageTime;
    }

    return item;
  }

  Map<String, dynamic> _fromCacheItem(Map<String, dynamic> data) {
    final id = data['id'];
    if (id is! String || id.isEmpty) return {};

    final participants = data['participants'];
    final participantsList = participants is List
        ? participants.whereType<String>().toList()
        : <String>[];
    if (participantsList.isEmpty) return {};

    final item = <String, dynamic>{'id': id, 'participants': participantsList};

    final type = data['type']?.toString().trim() ?? '';
    if (type.isNotEmpty) item['type'] = type;

    final title = data['title']?.toString().trim() ?? '';
    if (title.isNotEmpty) item['title'] = title;

    final avatarUrl = data['avatarUrl']?.toString().trim() ?? '';
    if (avatarUrl.isNotEmpty) item['avatarUrl'] = avatarUrl;

    if (data['lastMessage'] != null) item['lastMessage'] = data['lastMessage'];
    if (data['lastSenderId'] != null) {
      item['lastSenderId'] = data['lastSenderId'];
    }
    if (data['hasMessages'] != null) item['hasMessages'] = data['hasMessages'];

    final lastMessageTime = data['lastMessageTime'];
    if (lastMessageTime is int) {
      item['lastMessageTime'] = Timestamp.fromMillisecondsSinceEpoch(
        lastMessageTime,
      );
    } else if (lastMessageTime is Timestamp) {
      item['lastMessageTime'] = lastMessageTime;
    }

    return item;
  }

  Future<void> _touchIndex(SharedPreferences prefs, String uid) async {
    final list = prefs.getStringList(_indexKey) ?? <String>[];
    if (!list.contains(uid)) {
      list.add(uid);
      await prefs.setStringList(_indexKey, list);
    }
  }
}
