import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UserProfileViewScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic>? userData;

  const UserProfileViewScreen({
    super.key,
    required this.userId,
    this.userData,
  });

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _realtimeDb = FirebaseDatabase.instance;

  bool _isLoading = false;
  Map<String, dynamic>? _userData;
  bool _isOnline = false;
  DateTime? _lastSeen;
  bool _isFriend = false;
  bool _isBlocked = false;
  bool _friendStatusLoading = true;
  String _friendRequestStatus = 'none'; // none, pending_sent, pending_received

  @override
  void initState() {
    super.initState();
    _userData = widget.userData;
    if (_userData == null) {
      _loadUserData();
    }
    _listenToOnlineStatus();
    _checkFriendshipStatus();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      final doc = await _firestore.collection('users').doc(widget.userId).get();
      if (doc.exists) {
        setState(() {
          _userData = doc.data();
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _listenToOnlineStatus() {
    _realtimeDb.ref('status/${widget.userId}').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final state = data['state'] as String?;
        final lastSeenTimestamp = data['lastSeen'] as int?;

        if (mounted) {
          setState(() {
            _isOnline = state == 'online';
            if (lastSeenTimestamp != null) {
              _lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenTimestamp);
            }
          });
        }
      }
    });
  }

  Future<void> _checkFriendshipStatus() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Check if friends
      final friendDoc = await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('friends')
          .doc(widget.userId)
          .get();

      // Check if blocked
      final blockedDoc = await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('blocked')
          .doc(widget.userId)
          .get();

      // Check friend request status
      final sentRequest = await _firestore
          .collection('friendRequests')
          .where('senderId', isEqualTo: currentUser.uid)
          .where('receiverId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'pending')
          .get();

      final receivedRequest = await _firestore
          .collection('friendRequests')
          .where('senderId', isEqualTo: widget.userId)
          .where('receiverId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (mounted) {
        setState(() {
          _isFriend = friendDoc.exists;
          _isBlocked = blockedDoc.exists;
          
          if (sentRequest.docs.isNotEmpty) {
            _friendRequestStatus = 'pending_sent';
          } else if (receivedRequest.docs.isNotEmpty) {
            _friendRequestStatus = 'pending_received';
          } else {
            _friendRequestStatus = 'none';
          }
          _friendStatusLoading = false;
        });
      }
    } catch (e) {
      print('Error checking friendship status: $e');
      if (mounted) setState(() => _friendStatusLoading = false);
    }
  }

  String _getStatusText() {
    if (_isOnline) {
      return 'Online';
    } else if (_lastSeen != null) {
      final now = DateTime.now();
      final diff = now.difference(_lastSeen!);

      if (diff.inMinutes < 1) {
        return 'Last seen just now';
      } else if (diff.inMinutes < 60) {
        return 'Last seen ${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return 'Last seen ${diff.inHours}h ago';
      } else if (diff.inDays == 1) {
        return 'Last seen yesterday';
      } else if (diff.inDays < 7) {
        return 'Last seen ${diff.inDays}d ago';
      } else {
        return 'Last seen ${DateFormat('MMM d').format(_lastSeen!)}';
      }
    }
    return 'Offline';
  }

  Future<void> _sendFriendRequest() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await _firestore.collection('friendRequests').add({
        'senderId': currentUser.uid,
        'receiverId': widget.userId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _friendRequestStatus = 'pending_sent';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent!')),
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

  Future<void> _removeFriend() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Remove from both users' friends lists
      await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('friends')
          .doc(widget.userId)
          .delete();

      await _firestore
          .collection('contacts')
          .doc(widget.userId)
          .collection('friends')
          .doc(currentUser.uid)
          .delete();

      setState(() {
        _isFriend = false;
      });

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

  Future<void> _blockUser() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Add to blocked list
      await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('blocked')
          .doc(widget.userId)
          .set({
        'userId': widget.userId,
        'displayName': _userData?['displayName'] ?? 'User',
        'email': _userData?['email'] ?? '',
        'photoUrl': _userData?['photoUrl'],
        'blockedAt': FieldValue.serverTimestamp(),
      });

      // Remove from friends if they are friends
      if (_isFriend) {
        await _removeFriend();
      }

      setState(() {
        _isBlocked = true;
        _isFriend = false;
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

  Future<void> _unblockUser() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await _firestore
          .collection('contacts')
          .doc(currentUser.uid)
          .collection('blocked')
          .doc(widget.userId)
          .delete();

      setState(() {
        _isBlocked = false;
      });

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _userData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final photoUrl = _userData?['photoUrl'];
    final displayName = _userData?['displayName'] ?? 'User';
    final email = _userData?['email'] ?? '';
    final status = _userData?['status'] ?? '';
    final joinDate = _userData?['createdAt'] as Timestamp?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'block') {
                _showBlockDialog();
              } else if (value == 'unblock') {
                _unblockUser();
              } else if (value == 'remove') {
                _showRemoveFriendDialog();
              }
            },
            itemBuilder: (context) => [
              if (_isFriend)
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
              if (!_isBlocked)
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Block User', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                )
              else
                const PopupMenuItem(
                  value: 'unblock',
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 20, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Unblock User'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Picture Section
          Center(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isOnline ? Colors.green : Colors.grey,
                      width: 3,
                    ),
                  ),
                  child: CircleAvatar(
                      radius: 70,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
                      child: photoUrl == null
                          ? Icon(
                              Icons.person,
                              size: 70,
                              color: Colors.grey[600],
                            )
                          : null,
                    ),
                ),
                if (_isOnline)
                  Positioned(
                    bottom: 5,
                    right: 5,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Name
          Center(
            child: Text(
              displayName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Status
          if (status.isNotEmpty)
            Center(
              child: Text(
                status,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),

          // Online Status
          Center(
            child: Text(
              _getStatusText(),
              style: TextStyle(
                fontSize: 14,
                color: _isOnline ? Colors.green : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Action Button
          if (_isBlocked)
            ElevatedButton.icon(
              onPressed: _unblockUser,
              icon: const Icon(Icons.check_circle),
              label: const Text('Unblock User'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )
          else if (_isFriend)
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.check_circle, color: Colors.green),
              label: const Text('Friends', style: TextStyle(color: Colors.green)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Colors.green),
              ),
            )
          else if (_friendStatusLoading)
            OutlinedButton.icon(
              onPressed: null,
              icon: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              label: const Text('Checking...'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )
          else if (_friendRequestStatus == 'pending_sent')
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.schedule),
              label: const Text('Request Sent'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )
          else if (_friendRequestStatus == 'pending_received')
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                // Navigate to friend requests screen
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Accept Friend Request'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _sendFriendRequest,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Friend'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          const SizedBox(height: 24),

          // Profile Info Card
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Email'),
                  subtitle: Text(email),
                ),
                if (joinDate != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Joined'),
                    subtitle: Text(
                      DateFormat('MMMM yyyy').format(joinDate.toDate()),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Media Section (placeholder)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              'Shared Media',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos & Videos'),
              subtitle: const Text('Coming soon'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Shared media feature coming soon')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showRemoveFriendDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text(
          'Are you sure you want to remove ${_userData?['displayName'] ?? 'this user'} from your friends?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeFriend();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Are you sure you want to block ${_userData?['displayName'] ?? 'this user'}? '
          'You will no longer receive messages from them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _blockUser();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }
}