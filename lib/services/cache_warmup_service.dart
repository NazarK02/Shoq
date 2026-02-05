import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Preloads and caches user data and images so navigation feels instant.
/// Call warmUp() once after login.
/// Access cached data with getUserData() - returns immediately, no async.
class CacheWarmupService {
  static final CacheWarmupService _instance = CacheWarmupService._internal();
  factory CacheWarmupService() => _instance;
  CacheWarmupService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // In-memory cache: userId -> user data
  final Map<String, Map<String, dynamic>> _userCache = {};
  
  bool _hasWarmedUp = false;

  /// Get cached user data (synchronous - no loading delay)
  /// Returns null if not cached yet - caller should fall back to stream
  Map<String, dynamic>? getUserData(String userId) {
    return _userCache[userId];
  }

  /// Store user data in cache (called by streams when they update)
  void cacheUserData(String userId, Map<String, dynamic> data) {
    _userCache[userId] = data;
  }

  /// Preload:
  /// - Current user's profile data and image
  /// - All friends' profile data and images
  /// This makes profile navigation instant.
  Future<void> warmUp(BuildContext context) async {
    if (_hasWarmedUp) return;

    final user = _auth.currentUser;
    if (user == null) return;

    print('🔥 Warming up cache...');

    try {
      // Preload current user
      final currentUserDoc = await _firestore.collection('users').doc(user.uid).get();
      if (currentUserDoc.exists) {
        final data = currentUserDoc.data()!;
        _userCache[user.uid] = data;
        
        final photoUrl = data['photoUrl'] as String?;
        if (photoUrl != null && context.mounted) {
          await precacheImage(NetworkImage(photoUrl), context);
          print('✅ Cached current user');
        }
      }

      // Preload all friends
      final friendsSnapshot = await _firestore
          .collection('contacts')
          .doc(user.uid)
          .collection('friends')
          .get();

      for (var friendDoc in friendsSnapshot.docs) {
        final friendData = friendDoc.data();
        final friendUserId = friendData['userId'] as String;
        
        // Fetch and cache friend's full user doc
        final friendUserDoc = await _firestore.collection('users').doc(friendUserId).get();
        if (friendUserDoc.exists) {
          final userData = friendUserDoc.data()!;
          _userCache[friendUserId] = userData;
          
          final photoUrl = userData['photoUrl'] as String?;
          if (photoUrl != null && context.mounted) {
            await precacheImage(NetworkImage(photoUrl), context);
            print('✅ Cached friend: ${userData['displayName']}');
          }
        }
      }

      _hasWarmedUp = true;
      print('🔥 Cache warmup complete - ${_userCache.length} users cached');
    } catch (e) {
      print('❌ Cache warmup error: $e');
    }
  }

  /// Clear the cache (e.g. on logout)
  void reset() {
    _userCache.clear();
    _hasWarmedUp = false;
  }
}