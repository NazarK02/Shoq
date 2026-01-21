import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart';

class FriendsListScreen extends StatefulWidget {
  const FriendsListScreen({super.key});

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Friends'),
                  const SizedBox(width: 8),
                  _buildFriendsCountBadge(user.uid),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Requests'),
                  const SizedBox(width: 8),
                  _buildRequestsBadge(user.uid),
                ],
              ),
            ),
            const Tab(text: 'Blocked'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsList(user.uid),
          _buildRequestsList(user.uid),
          _buildBlockedList(user.uid),
        ],
      ),
    );
  }

  // Friends count badge
  Widget _buildFriendsCountBadge(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('contacts')
          .doc(userId)
          .collection('friends')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${snapshot.data!.docs.length}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        );
      },
    );
  }

  // Requests badge
  Widget _buildRequestsBadge(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('friendRequests')
          .where('receiverId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${snapshot.data!.docs.length}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        );
      },
    );
  }

  // Friends List Tab
  Widget _buildFriendsList(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('contacts')
          .doc(userId)
          .collection('friends')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No friends yet', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text('Send friend requests to connect', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
              ],
            ),
          );
        }

        final friends = snapshot.data!.docs.toList();
        friends.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['addedAt'] as Timestamp?;
          final bTime = bData['addedAt'] as Timestamp?;
          
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          
          return bTime.compareTo(aTime);
        });

        return ListView.builder(
          itemCount: friends.length,
          itemBuilder: (context, index) {
            final friend = friends[index].data() as Map<String, dynamic>;
            
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: friend['photoURL'] != null 
                    ? NetworkImage(friend['photoURL']) 
                    : null,
                child: friend['photoURL'] == null 
                    ? Text(friend['displayName'][0].toUpperCase()) 
                    : null,
              ),
              title: Text(friend['displayName']),
              subtitle: Text(friend['email']),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chat),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            recipientId: friend['userId'],
                            recipientName: friend['displayName'],
                          ),
                        ),
                      );
                    },
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'remove') {
                        _showRemoveFriendDialog(friend['userId'], friend['displayName']);
                      } else if (value == 'block') {
                        _blockUser(friend['userId'], friend);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.person_remove, size: 20),
                            SizedBox(width: 8),
                            Text('Remove Friend'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            Icon(Icons.block, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Block', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Friend Requests Tab
  Widget _buildRequestsList(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('friendRequests')
          .where('receiverId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No friend requests', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final request = snapshot.data!.docs[index];
            final requestData = request.data() as Map<String, dynamic>;
            final senderId = requestData['senderId'];

            return FutureBuilder<DocumentSnapshot>(
              future: _firestore.collection('users').doc(senderId).get(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return const ListTile(
                    leading: CircleAvatar(child: Icon(Icons.person)),
                    title: Text('Loading...'),
                  );
                }

                final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                final displayName = userData?['displayName'] ?? 'User';
                final email = userData?['email'] ?? '';
                final photoURL = userData?['photoURL'];

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: photoURL != null ? NetworkImage(photoURL) : null,
                      child: photoURL == null ? Text(displayName[0].toUpperCase()) : null,
                    ),
                    title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(email),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () => _acceptFriendRequest(request.id, senderId, userData),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () => _denyFriendRequest(request.id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.block, color: Colors.orange),
                          onPressed: () => _blockFromRequest(request.id, senderId, userData),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Blocked Users Tab
  Widget _buildBlockedList(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('contacts')
          .doc(userId)
          .collection('blocked')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No blocked users', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final blocked = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: blocked['photoURL'] != null 
                    ? NetworkImage(blocked['photoURL']) 
                    : null,
                child: blocked['photoURL'] == null 
                    ? Text(blocked['displayName'][0].toUpperCase()) 
                    : null,
              ),
              title: Text(blocked['displayName']),
              subtitle: Text(blocked['email']),
              trailing: ElevatedButton(
                onPressed: () => _unblockUser(blocked['userId']),
                child: const Text('Unblock'),
              ),
            );
          },
        );
      },
    );
  }

  // Accept Friend Request
  Future<void> _acceptFriendRequest(String requestId, String friendId, Map<String, dynamic>? friendData) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final conversationId = _getDirectConversationId(currentUser.uid, friendId);

      // Create conversation
      await _firestore.collection('conversations').doc(conversationId).set({
        'type': 'direct',
        'participants': [currentUser.uid, friendId],
        'createdBy': currentUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageTime': null,
      });

      // Add to current user's friends
      await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('friends')
          .doc(friendId)
          .set({
        'userId': friendId,
        'displayName': friendData?['displayName'] ?? 'User',
        'email': friendData?['email'] ?? '',
        'photoURL': friendData?['photoURL'],
        'addedAt': FieldValue.serverTimestamp(),
        'conversationId': conversationId,
      });

      // Add to friend's friends
      final currentUserData = await _firestore.collection('users').doc(currentUser.uid).get();
      await _firestore
          .collection('contacts')
          .doc(friendId)
          .collection('friends')
          .doc(currentUser.uid)
          .set({
        'userId': currentUser.uid,
        'displayName': currentUserData.data()?['displayName'] ?? 'User',
        'email': currentUserData.data()?['email'] ?? '',
        'photoURL': currentUserData.data()?['photoURL'],
        'addedAt': FieldValue.serverTimestamp(),
        'conversationId': conversationId,
      });

      // Update request status
      await _firestore.collection('friendRequests').doc(requestId).update({
        'status': 'accepted',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request accepted!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  // Deny Friend Request
  Future<void> _denyFriendRequest(String requestId) async {
    try {
      await _firestore.collection('friendRequests').doc(requestId).update({
        'status': 'denied',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request denied')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  // Block from request
  Future<void> _blockFromRequest(String requestId, String userId, Map<String, dynamic>? userData) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Add to blocked list
      await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('blocked')
          .doc(userId)
          .set({
        'userId': userId,
        'displayName': userData?['displayName'] ?? 'User',
        'email': userData?['email'] ?? '',
        'photoURL': userData?['photoURL'],
        'blockedAt': FieldValue.serverTimestamp(),
      });

      // Update request
      await _firestore.collection('friendRequests').doc(requestId).update({
        'status': 'blocked',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  // Block user (from friends list)
  Future<void> _blockUser(String friendId, Map<String, dynamic> friendData) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Add to blocked list
      await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('blocked')
          .doc(friendId)
          .set({
        'userId': friendId,
        'displayName': friendData['displayName'] ?? 'User',
        'email': friendData['email'] ?? '',
        'photoURL': friendData['photoURL'],
        'blockedAt': FieldValue.serverTimestamp(),
      });

      // Remove from friends
      await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('friends')
          .doc(friendId)
          .delete();

      await _firestore
          .collection('contacts')
          .doc(friendId)
          .collection('friends')
          .doc(currentUser.uid)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  // Unblock user
  Future<void> _unblockUser(String userId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('blocked')
          .doc(userId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User unblocked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  // Remove friend dialog
  void _showRemoveFriendDialog(String friendId, String friendName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text('Are you sure you want to remove $friendName from your friends?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _removeFriend(friendId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // Remove friend
  Future<void> _removeFriend(String friendId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('friends')
          .doc(friendId)
          .delete();

      await _firestore
          .collection('contacts')
          .doc(friendId)
          .collection('friends')
          .doc(currentUser.uid)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  String _getDirectConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return 'direct_${sortedIds.join('_')}';
  }
}