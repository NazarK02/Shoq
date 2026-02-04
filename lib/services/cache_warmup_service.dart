import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Preloads user data and images so navigation feels instant.
/// Call warmUp() once after login.
class CacheWarmupService {
  static final CacheWarmupService _instance = CacheWarmupService._internal();
  factory CacheWarmupService() => _instance;
  CacheWarmupService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _hasWarmedUp = false;

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
      // Preload current user's image
      final currentUserDoc = await _firestore.collection('users').doc(user.uid).get();
      if (currentUserDoc.exists) {
        final photoUrl = currentUserDoc.data()?['photoUrl'] as String?;
        if (photoUrl != null && context.mounted) {
          await precacheImage(NetworkImage(photoUrl), context);
          print('✅ Cached current user photo');
        }
      }

      // Preload all friends' data and images
      final friendsSnapshot = await _firestore
          .collection('contacts')
          .doc(user.uid)
          .collection('friends')
          .get();

      for (var friendDoc in friendsSnapshot.docs) {
        final friendData = friendDoc.data();
        final photoUrl = friendData['photoUrl'] as String?;
        
        if (photoUrl != null && context.mounted) {
          await precacheImage(NetworkImage(photoUrl), context);
          print('✅ Cached friend photo: ${friendData['displayName']}');
        }
      }

      _hasWarmedUp = true;
      print('🔥 Cache warmup complete');
    } catch (e) {
      print('❌ Cache warmup error: $e');
    }
  }

  /// Clear the cache flag (e.g. on logout)
  void reset() {
    _hasWarmedUp = false;
  }
}