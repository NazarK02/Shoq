import 'package:cloud_firestore/cloud_firestore.dart';
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

  Future<void> warmUpForUser(String uid) async {
    if (_isRunning && _lastUid == uid) return;
    _isRunning = true;
    _lastUid = uid;

    try {
      final userIds = <String>{};

      final conversations = await _queryWithCacheThenServer(
        _firestore.collection('conversations').where(
              'participants',
              arrayContains: uid,
            ),
      );

      final conversationCache =
          ConversationCacheService().buildCacheItemsFromDocs(conversations.docs);
      if (conversationCache.isNotEmpty) {
        await ConversationCacheService().saveConversations(uid, conversationCache);
      }

      for (final doc in conversations.docs) {
        final data = doc.data();
        final participants = data['participants'];
        if (participants is List) {
          for (final p in participants) {
            if (p is String && p != uid) userIds.add(p);
          }
        }
      }

      final friends = await _queryWithCacheThenServer(
        _firestore.collection('contacts').doc(uid).collection('friends'),
      );

      for (final doc in friends.docs) {
        final data = doc.data();
        final friendId = data['userId'];
        if (friendId is String && friendId.isNotEmpty) {
          userIds.add(friendId);
          // Seed cache with friend list data to avoid blank UI.
          UserCacheService().mergeUserData(friendId, data);
        }
      }

      final requests = await _queryWithCacheThenServer(
        _firestore
            .collection('friendRequests')
            .where('receiverId', isEqualTo: uid)
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
}
