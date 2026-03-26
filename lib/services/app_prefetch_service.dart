import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_service_e2ee.dart';
import 'message_cache_service.dart';
import 'user_cache_service.dart';
import 'conversation_cache_service.dart';

/// Warms Firestore caches and user profiles right after login.
class AppPrefetchService {
  static final AppPrefetchService _instance = AppPrefetchService._internal();
  factory AppPrefetchService() => _instance;
  AppPrefetchService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isRunning = false;
  String? _lastUid;
  static const int _recentConversationWarmupLimit = 6;
  static const int _recentMessageWarmupLimit = 80;
  static const String _dailyWarmupPrefix = 'app_prefetch_last_run_';

  Future<void> warmUpForUser(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return;

    if (_isRunning && _lastUid == normalizedUid) return;

    // Always prime encryption so chat screens can decrypt immediately, even if
    // the heavier cache warm-up is skipped by the daily gate.
    try {
      await ChatService().initializeEncryption();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final todayKey = _dayKey(DateTime.now());
    if (prefs.getString(_dailyWarmupKey(normalizedUid)) == todayKey) {
      return;
    }

    _isRunning = true;
    _lastUid = normalizedUid;

    try {
      final userIds = <String>{};

      final conversations = await _queryWithCacheThenServer(
        _firestore.collection('conversations').where(
              'participants',
              arrayContains: normalizedUid,
            ),
      );

      final conversationDocs = conversations.docs.toList()
        ..sort((a, b) {
          final aTime =
              (a.data()['lastMessageTime'] as Timestamp?)?.millisecondsSinceEpoch ??
              0;
          final bTime =
              (b.data()['lastMessageTime'] as Timestamp?)?.millisecondsSinceEpoch ??
              0;
          return bTime.compareTo(aTime);
        });

      final conversationCache = ConversationCacheService().buildCacheItemsFromDocs(
        conversationDocs,
      );
      if (conversationCache.isNotEmpty) {
        await ConversationCacheService().saveConversations(uid, conversationCache);
      }

      for (final doc in conversationDocs) {
        final data = doc.data();
        final participants = data['participants'];
        if (participants is List) {
          for (final p in participants) {
            if (p is String && p != normalizedUid) userIds.add(p);
          }
        }
      }

      final friends = await _queryWithCacheThenServer(
        _firestore.collection('contacts').doc(normalizedUid).collection('friends'),
      );

      for (final doc in friends.docs) {
        final data = doc.data();
        final friendId = data['userId'];
        if (friendId is String && friendId.isNotEmpty) {
          userIds.add(friendId);
          // Seed cache with friend list data to avoid blank UI.
          // Ignore empty avatar/display values so valid cached profile data
          // does not get overwritten by sparse contact docs.
          final seed = Map<String, dynamic>.from(data);
          final photo = (seed['photoUrl'] ?? seed['photoURL'])
              ?.toString()
              .trim()
              .toLowerCase();
          if (photo == null || photo.isEmpty || photo == 'null') {
            seed.remove('photoUrl');
            seed.remove('photoURL');
          }
          final displayName = seed['displayName']?.toString().trim() ?? '';
          if (displayName.isEmpty) {
            seed.remove('displayName');
          }
          UserCacheService().mergeUserData(friendId, seed);
        }
      }

      final requests = await _queryWithCacheThenServer(
        _firestore
            .collection('friendRequests')
            .where('receiverId', isEqualTo: normalizedUid)
            .where('status', isEqualTo: 'pending'),
      );

      for (final doc in requests.docs) {
        final data = doc.data();
        final senderId = data['senderId'];
        if (senderId is String && senderId.isNotEmpty) {
          userIds.add(senderId);
        }
      }

      await UserCacheService().warmUsers(userIds, listen: false);
      await _warmRecentConversationMessages(
        normalizedUid,
        conversationDocs.take(_recentConversationWarmupLimit),
      );
      await prefs.setString(_dailyWarmupKey(normalizedUid), todayKey);
    } catch (_) {
      // Best-effort prefetch; ignore failures.
    } finally {
      _isRunning = false;
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _queryWithCacheThenServer(
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      final cached = await query.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) return cached;
    } catch (_) {}

    return query.get();
  }

  Future<void> _warmRecentConversationMessages(
    String uid,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> conversations,
  ) async {
    final chatService = ChatService();
    final messageCache = MessageCacheService();

    try {
      await chatService.initializeEncryption();
    } catch (_) {
      // If E2EE is not ready yet, skip message warm-up and keep the rest.
      return;
    }

    for (final conversation in conversations) {
      final conversationId = conversation.id.trim();
      if (conversationId.isEmpty) continue;

      try {
        final messages = await _queryWithCacheThenServer(
          _firestore
              .collection('conversations')
              .doc(conversationId)
              .collection('messages')
              .orderBy('clientTimestamp', descending: false)
              .limitToLast(_recentMessageWarmupLimit),
        );

        if (messages.docs.isEmpty) continue;

        final cacheItems = await messageCache.buildCacheItemsFromDocs(
          messages.docs,
          resolveText: (message) async {
            if (message['encrypted'] == true) {
              return chatService.decryptMessage(messageData: message);
            }
            return _extractPlainText(message);
          },
        );

        if (cacheItems.isNotEmpty) {
          await messageCache.saveConversationMessages(
            uid,
            conversationId,
            cacheItems,
          );
        }
      } catch (_) {
        // Keep warming other conversations even if one fails.
      }
    }
  }

  String _extractPlainText(Map<String, dynamic> message) {
    final type = message['type']?.toString().trim().toLowerCase() ?? 'text';

    if (type == 'file') {
      final caption = message['caption']?.toString().trim() ?? '';
      if (caption.isNotEmpty) return caption;
      final fileName = message['fileName']?.toString().trim() ?? '';
      if (fileName.isNotEmpty) return 'File: $fileName';
    }

    if (type == 'sticker') {
      final stickerFallback = message['stickerFallback']?.toString().trim() ?? '';
      if (stickerFallback.isNotEmpty) return stickerFallback;
      final sticker = message['sticker']?.toString().trim() ?? '';
      if (sticker.isNotEmpty) return sticker;
    }

    return message['text']?.toString().trim() ?? message['message']?.toString().trim() ?? '';
  }

  String _dailyWarmupKey(String uid) => '$_dailyWarmupPrefix$uid';

  String _dayKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}${local.month.toString().padLeft(2, '0')}${local.day.toString().padLeft(2, '0')}';
  }
}
