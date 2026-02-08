import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen_e2ee.dart';
import 'user_profile_view_screen.dart';
import '../services/notification_service.dart';
import '../services/user_cache_service.dart';

class ImprovedFriendsListScreen extends StatefulWidget {
  const ImprovedFriendsListScreen({super.key});

  @override
  State<ImprovedFriendsListScreen> createState() => _ImprovedFriendsListScreenState();
}

class _ImprovedFriendsListScreenState extends State<ImprovedFriendsListScreen> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final bool _isPreloading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  // Preload removed — data loads live from Firestore

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddFriendDialog(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Friend'),
      ),
    );
  }

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

  Widget _buildFriendsList(String userId) {
    // Show spinner during initial preload (kept for parity)
    if (_isPreloading) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('contacts')
          .doc(userId)
          .collection('friends')
          .snapshots(),
      builder: (context, snapshot) {
        // Don't show loading spinner after initial preload
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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
            final friendData = friends[index].data() as Map<String, dynamic>;
            final friendId = friendData['userId'] as String;
            
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _FriendListTile(
                key: ValueKey(friendId),
                friendId: friendId,
                initialData: friendData,
                onRemove: () => _showRemoveFriendDialog(friendId, friendData['displayName']),
                onBlock: () => _blockUser(friendId, friendData),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRequestsList(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('friendRequests')
          .where('receiverId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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

            return _FriendRequestTile(
              key: ValueKey(request.id),
              requestId: request.id,
              senderId: senderId,
              onAccept: () => _acceptFriendRequest(request.id, senderId),
              onDeny: () => _denyFriendRequest(request.id),
              onBlock: () => _blockFromRequest(request.id, senderId),
            );
          },
        );
      },
    );
  }

  Widget _buildBlockedList(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('contacts')
          .doc(userId)
          .collection('blocked')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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
                radius: 20,
                backgroundImage: (blocked['photoURL'] != null && blocked['photoURL'].toString().isNotEmpty)
                    ? CachedNetworkImageProvider(blocked['photoURL'])
                    : null,
                child: (blocked['photoURL'] == null || blocked['photoURL'].toString().isEmpty)
                    ? const Icon(Icons.person)
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

  // ... (keeping all the existing methods for friend operations)
  // I'll include the essential ones below with optimizations

  void _showAddFriendDialog(BuildContext context) {
    final emailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Friend Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your friend\'s email address:'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'friend@example.com',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter an email')),
                );
                return;
              }
              
              Navigator.pop(context);
              await _sendFriendRequest(email);
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFriendRequest(String email) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not found')),
          );
        }
        return;
      }

      final friendUser = userQuery.docs.first;
      final friendId = friendUser.id;
      
      if (friendId == currentUser.uid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You cannot add yourself')),
          );
        }
        return;
      }

      // Check if already friends
      final existingFriend = await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('friends')
          .doc(friendId)
          .get();

      if (existingFriend.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Already friends')),
          );
        }
        return;
      }

      // Check for existing request
      final existingRequest = await _firestore
          .collection('friendRequests')
          .where('senderId', isEqualTo: currentUser.uid)
          .where('receiverId', isEqualTo: friendId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingRequest.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Friend request already sent')),
          );
        }
        return;
      }

      // Create friend request
      await _firestore.collection('friendRequests').add({
        'senderId': currentUser.uid,
        'receiverId': friendId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Send notification
      try {
        final currentUserData = await _firestore.collection('users').doc(currentUser.uid).get();
        final senderName = currentUserData.data()?['displayName'] ?? 'Someone';
        
        await NotificationService().sendFriendRequestNotification(
          recipientId: friendId,
          senderName: senderName,
        );
      } catch (notificationError) {
        print('Error sending notification: $notificationError');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent!')),
        );
      }
    } catch (e) {
      print('Error sending friend request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _acceptFriendRequest(String requestId, String friendId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Get friend data directly from Firestore
      final friendDoc = await _firestore.collection('users').doc(friendId).get();
      final friendData = friendDoc.data();

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

      // Add to friends
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

      // (No cache subscription) Updates will come from Firestore streams when viewing lists

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

  Future<void> _blockFromRequest(String requestId, String userId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data();

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

  Future<void> _blockUser(String friendId, Map<String, dynamic> friendData) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
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

      // (No cache subscription to remove)

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

/// Individual friend list tile with optimized rendering
class _FriendListTile extends StatelessWidget {
  final String friendId;
  final Map<String, dynamic> initialData;
  final VoidCallback onRemove;
  final VoidCallback onBlock;

  const _FriendListTile({
    super.key,
    required this.friendId,
    required this.initialData,
    required this.onRemove,
    required this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = initialData['displayName'] ?? 'User';
    final email = initialData['email'] ?? '';
    final photoURL = initialData['photoURL'];

    return ListTile(
      onTap: () {
        final seedData = Map<String, dynamic>.from(initialData);
        if (seedData['photoUrl'] == null && seedData['photoURL'] != null) {
          seedData['photoUrl'] = seedData['photoURL'];
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileViewScreen(
              userId: friendId,
              userData: seedData,
            ),
          ),
        );
      },
      leading: CircleAvatar(
        radius: 20,
        backgroundImage: (photoURL != null && photoURL.isNotEmpty)
            ? CachedNetworkImageProvider(photoURL)
            : null,
        child: (photoURL == null || photoURL.isEmpty)
            ? const Icon(Icons.person)
            : null,
      ),
      title: Text(displayName),
      subtitle: Text(email),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreenE2EE(
                    recipientId: friendId,
                    recipientName: displayName,
                  ),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'remove') {
                onRemove();
              } else if (value == 'block') {
                onBlock();
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
  }
}

/// Friend request tile with optimized loading
class _FriendRequestTile extends StatefulWidget {
  final String requestId;
  final String senderId;
  final VoidCallback onAccept;
  final VoidCallback onDeny;
  final VoidCallback onBlock;

  const _FriendRequestTile({
    super.key,
    required this.requestId,
    required this.senderId,
    required this.onAccept,
    required this.onDeny,
    required this.onBlock,
  });

  @override
  State<_FriendRequestTile> createState() => _FriendRequestTileState();
}

class _FriendRequestTileState extends State<_FriendRequestTile> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  final UserCacheService _userCache = UserCacheService();

  @override
  void initState() {
    super.initState();
    _userData = _userCache.getCachedUser(widget.senderId);
    if (_userData != null) {
      _isLoading = false;
    }
    _userCache.warmUsers([widget.senderId], listen: false);
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.senderId).get();
      final data = doc.data();
      if (mounted) {
        setState(() {
          _userData = data;
          _isLoading = false;
        });
      }
      if (data != null) {
        _userCache.mergeUserData(widget.senderId, data);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userData = null;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final displayName = _userData?['displayName'] ?? 'User';
    final email = _userData?['email'] ?? '';
    final photoURL = _userData?['photoURL'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundImage: (photoURL != null && photoURL.isNotEmpty)
              ? CachedNetworkImageProvider(photoURL)
              : null,
          child: (photoURL == null || photoURL.isEmpty)
              ? const Icon(Icons.person)
              : null,
        ),
        title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(email),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: widget.onAccept,
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: widget.onDeny,
            ),
            IconButton(
              icon: const Icon(Icons.block, color: Colors.orange),
              onPressed: widget.onBlock,
            ),
          ],
        ),
      ),
    );
  }
}
