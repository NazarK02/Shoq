import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'registration_screen.dart';
import 'friends_list_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import '../services/notification_service.dart';
import '../services/presence_service.dart';
import '../services/user_cache_service.dart';
import '../services/conversation_cache_service.dart';
import 'chat_screen_e2ee.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserCacheService _userCache = UserCacheService();
  final ConversationCacheService _conversationCache = ConversationCacheService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _rebuildTimer;
  Timer? _cacheDebounce;
  final Set<String> _warmedUserIds = {};
  List<Map<String, dynamic>> _cachedConversations = [];

  @override
  void initState() {
    super.initState();
    _userCache.addListener(_onUserCacheUpdated);
    _loadCachedConversations();
    _rebuildTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _rebuildTimer?.cancel();
    _cacheDebounce?.cancel();
    _searchController.dispose();
    _userCache.removeListener(_onUserCacheUpdated);
    super.dispose();
  }

  void _onUserCacheUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCachedConversations() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final cached = await _conversationCache.loadConversations(user.uid);
    if (!mounted) return;
    setState(() {
      _cachedConversations = cached;
    });
    _warmUsersFromConversations(cached, user.uid);
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search chats...',
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: (value) {
            setState(() {
              _searchQuery = value.toLowerCase();
            });
          },
        ),
        elevation: 1,
        actions: [
          _buildFriendRequestsBadge(),
        ],
      ),
      drawer: _buildDrawer(context, user),
      body: _buildChatsList(),
    );
  }

  Widget _buildFriendRequestsBadge() {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('friendRequests')
          .where('receiverId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () {
                Navigator.push(
                  context,
                    MaterialPageRoute(builder: (_) => const ImprovedFriendsListScreen()),
                );
              },
            ),
            if (count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context, User? user) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            currentAccountPicture: _buildAvatar(
              _normalizePhotoUrl(user?.photoURL),
              40,
              Theme.of(context).primaryColor,
            ),
            accountName: Text(
              user?.displayName ?? 'User',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(user?.email ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('My Profile'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('My Friends'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                  MaterialPageRoute(builder: (_) => const ImprovedFriendsListScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              showAboutDialog(
                context: context,
                applicationName: 'Shoq',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.shopping_bag, size: 48),
                children: [
                  const Text('Secure messaging app with end-to-end encryption.'),
                ],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await NotificationService().clearToken();
              await PresenceService().setOffline();
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const RegistrationScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChatsList() {
    final user = _auth.currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('conversations')
          .where('participants', arrayContains: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final hasSnapshot = snapshot.hasData;
        final hasLiveData = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        final canUseCache = (!hasSnapshot ||
                snapshot.connectionState == ConnectionState.waiting) &&
            _cachedConversations.isNotEmpty;

        if (hasLiveData) {
          _scheduleConversationCacheWrite(
            user.uid,
            snapshot.data!.docs,
          );
        } else if (hasSnapshot && snapshot.data!.docs.isEmpty) {
          _scheduleConversationCacheClear(user.uid);
        }

        if (!hasLiveData && !canUseCache) {
          // Don't show spinner - show empty state immediately
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No chats yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add friends to start chatting',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ImprovedFriendsListScreen()),
                    );
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Friends'),
                ),
              ],
            ),
          );
        }

        final items = hasLiveData
            ? _conversationCache
                .buildCacheItemsFromDocs(snapshot.data!.docs)
            : _cachedConversations;
        
        final sortedDocs = items.toList()
          ..sort((a, b) {
            final aTime = a['lastMessageTime'] as Timestamp?;
            final bTime = b['lastMessageTime'] as Timestamp?;
            
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            
            return bTime.compareTo(aTime);
          });

        _warmUsersFromConversations(sortedDocs, user.uid);

        return ListView.builder(
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final chatData = sortedDocs[index];
            final participants = List<String>.from(chatData['participants']);
            final otherUserId = participants.firstWhere(
              (id) => id != user.uid,
              orElse: () => '',
            );
            if (otherUserId.isEmpty) {
              return const SizedBox.shrink();
            }

            final userData = _userCache.getCachedUser(otherUserId);
            final displayName = userData?['displayName'] ?? 'User';
            final photoURL = _normalizePhotoUrl(
              userData?['photoUrl'] ?? userData?['photoURL'],
            );

            if (_searchQuery.isNotEmpty &&
                !displayName.toLowerCase().contains(_searchQuery)) {
              return const SizedBox.shrink();
            }

            final isOnline = userData != null
                ? PresenceService.isUserOnline(userData)
                : false;

            // Get last message - now shows actual preview instead of "encrypted"
            String lastMessageText = 'Start chatting';
            if (chatData['lastMessage'] != null &&
                chatData['lastMessage'].toString().isNotEmpty) {
              lastMessageText = chatData['lastMessage'];
            } else if (chatData['lastMessageTime'] != null) {
              lastMessageText = 'Sent a message';
            }

            return ListTile(
              leading: Stack(
                children: [
                  _buildAvatar(photoURL, 20, null),
                  if (isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                displayName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                lastMessageText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey),
              ),
              trailing: chatData['lastMessageTime'] != null
                  ? Text(
                      _formatTime(chatData['lastMessageTime'] as Timestamp),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    )
                  : null,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImprovedChatScreen(
                      recipientId: otherUserId,
                      recipientName: displayName,
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

  void _scheduleConversationCacheWrite(
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final cacheItems = _conversationCache.buildCacheItemsFromDocs(docs);
    if (cacheItems.isEmpty) return;

    _cacheDebounce?.cancel();
    _cacheDebounce = Timer(const Duration(milliseconds: 350), () async {
      await _conversationCache.saveConversations(uid, cacheItems);
      if (!mounted) return;
      setState(() {
        _cachedConversations = cacheItems;
      });
    });
  }

  void _scheduleConversationCacheClear(String uid) {
    _cacheDebounce?.cancel();
    _cacheDebounce = Timer(const Duration(milliseconds: 350), () async {
      await _conversationCache.clearForUser(uid);
      if (!mounted) return;
      setState(() {
        _cachedConversations = [];
      });
    });
  }

  void _warmUsersFromConversations(
    List<Map<String, dynamic>> conversations,
    String currentUserId,
  ) {
    if (conversations.isEmpty) return;

    final otherUserIds = <String>{};
    for (final data in conversations) {
      final participants = data['participants'];
      if (participants is! List) continue;
      for (final p in participants) {
        if (p is String && p.isNotEmpty && p != currentUserId) {
          otherUserIds.add(p);
        }
      }
    }

    final newIds = otherUserIds.difference(_warmedUserIds);
    if (newIds.isNotEmpty) {
      _warmedUserIds.addAll(newIds);
      _userCache.warmUsers(newIds, listen: false);
    }
  }

  String _formatTime(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String? _normalizePhotoUrl(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return null;
    return text;
  }

  Widget _buildAvatar(String? photoUrl, double radius, Color? iconColor) {
    final placeholder = Container(
      width: radius * 2,
      height: radius * 2,
      color: Colors.grey[300],
      child: Icon(
        Icons.person,
        size: radius,
        color: iconColor ?? Colors.grey[600],
      ),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey[300],
        child: Icon(
          Icons.person,
          size: radius,
          color: iconColor ?? Colors.grey[600],
        ),
      );
    }
    // Windows-specific handling to prevent crashes
    if (Platform.isWindows) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: frame == null ? placeholder : child,
            );
          },
          errorBuilder: (_, __, ___) => placeholder,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return placeholder;
          },
        ),
      );
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (radius * 2 * dpr).round().clamp(32, 256);

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        memCacheWidth: cacheSize,
        memCacheHeight: cacheSize,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: const Duration(milliseconds: 150),
      ),
    );
  }
}
