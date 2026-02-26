import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'friends_list_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'room_chat_screen.dart';
import '../services/notification_service.dart';
import '../services/presence_service.dart';
import '../services/user_service_e2ee.dart';
import '../services/user_cache_service.dart';
import '../services/conversation_cache_service.dart';
import '../services/chat_folder_service.dart';
import 'chat_screen_e2ee.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<Color> _folderPalette = [
    Color(0xFF4E79A7),
    Color(0xFF59A14F),
    Color(0xFFF28E2B),
    Color(0xFFE15759),
    Color(0xFF76B7B2),
    Color(0xFFEDC948),
    Color(0xFFB07AA1),
  ];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserCacheService _userCache = UserCacheService();
  final ConversationCacheService _conversationCache =
      ConversationCacheService();
  final ChatFolderService _folderService = ChatFolderService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _rebuildTimer;
  Timer? _cacheDebounce;
  final Set<String> _warmedUserIds = {};
  final Set<String> _prefetchedImageUrls = {};
  List<Map<String, dynamic>> _cachedConversations = [];
  bool _cacheLoaded = false;
  List<ChatFolder> _folders = [];
  Map<String, String> _folderAssignments = {};
  String? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    _userCache.addListener(_onUserCacheUpdated);
    _loadCachedConversations();
    _loadFolderState();
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

  void _clearSearch() {
    if (_searchController.text.isEmpty && _searchQuery.isEmpty) return;
    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });
  }

  Future<void> _openScreen(Widget screen) async {
    FocusScope.of(context).unfocus();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    _clearSearch();
  }

  Future<void> _handleLogout() async {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }

    try {
      await NotificationService().clearToken();
      await PresenceService().stopPresenceTracking();
      await UserService().signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      }
    }
  }

  Future<void> _loadCachedConversations() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final cached = await _conversationCache.loadConversations(user.uid);
    if (!mounted) return;
    setState(() {
      _cachedConversations = cached;
      _cacheLoaded = true;
    });
    _warmUsersFromConversations(cached, user.uid);
  }

  Future<void> _loadFolderState() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final state = await _folderService.loadForUser(user.uid);
    if (!mounted) return;
    setState(() {
      _folders = state.folders;
      _folderAssignments = state.assignments;
      if (_selectedFolderId != null &&
          !_folders.any((folder) => folder.id == _selectedFolderId)) {
        _selectedFolderId = null;
      }
    });
  }

  Future<void> _saveFolderState() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _folderService.saveForUser(
      user.uid,
      folders: _folders,
      assignments: _folderAssignments,
    );
  }

  Future<void> _showCreateSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Create folder'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateFolderDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('Create group chat'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateRoomDialog(type: 'group');
                },
              ),
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('Create server'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateRoomDialog(type: 'server');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create folder'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              hintText: 'Work, Family, Gaming...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;

                final exists = _folders.any(
                  (folder) => folder.name.toLowerCase() == name.toLowerCase(),
                );
                if (exists) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Folder already exists')),
                    );
                  }
                  return;
                }

                final folder = ChatFolder(
                  id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  colorValue:
                      _folderPalette[_folders.length % _folderPalette.length]
                          .toARGB32(),
                );
                if (!mounted) return;
                setState(() {
                  _folders = [..._folders, folder];
                  _selectedFolderId = folder.id;
                });
                await _saveFolderState();
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<List<_FriendSeed>> _loadFriendsForRoomCreation() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snapshot = await _firestore
        .collection('contacts')
        .doc(user.uid)
        .collection('friends')
        .get();

    final friends = <_FriendSeed>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final uid = data['userId']?.toString().trim() ?? '';
      if (uid.isEmpty) continue;
      final displayName = data['displayName']?.toString().trim();
      final photoUrl = _normalizePhotoUrl(data['photoURL'] ?? data['photoUrl']);
      friends.add(
        _FriendSeed(
          userId: uid,
          displayName: (displayName == null || displayName.isEmpty)
              ? 'User'
              : displayName,
          photoUrl: photoUrl,
        ),
      );
    }
    friends.sort((a, b) => a.displayName.compareTo(b.displayName));
    return friends;
  }

  Future<void> _showCreateRoomDialog({required String type}) async {
    final friends = await _loadFriendsForRoomCreation();
    if (!mounted) return;

    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add friends first to create a room')),
      );
      return;
    }

    final titleController = TextEditingController();
    final selectedFriendIds = <String>{};
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(type == 'server' ? 'Create server' : 'Create group'),
              content: SizedBox(
                width: 430,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 40,
                      decoration: InputDecoration(
                        labelText: type == 'server'
                            ? 'Server name'
                            : 'Group name',
                        hintText: type == 'server'
                            ? 'My server'
                            : 'Weekend project',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select members',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 280,
                      child: ListView.builder(
                        itemCount: friends.length,
                        itemBuilder: (context, index) {
                          final friend = friends[index];
                          final isSelected = selectedFriendIds.contains(
                            friend.userId,
                          );
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedFriendIds.add(friend.userId);
                                } else {
                                  selectedFriendIds.remove(friend.userId);
                                }
                              });
                            },
                            title: Text(friend.displayName),
                            secondary: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.grey[300],
                              backgroundImage: friend.photoUrl != null
                                  ? CachedNetworkImageProvider(friend.photoUrl!)
                                  : null,
                              child: friend.photoUrl == null
                                  ? Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.grey[600],
                                    )
                                  : null,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final title = titleController.text.trim();
                          if (title.isEmpty) return;
                          if (selectedFriendIds.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Select at least one member'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          final conversationId = await _createRoomConversation(
                            type: type,
                            title: title,
                            memberIds: selectedFriendIds.toList(),
                          );
                          if (!mounted) return;
                          if (conversationId == null) {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                            return;
                          }

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }

                          final allParticipants = <String>[
                            ...selectedFriendIds,
                            _auth.currentUser?.uid ?? '',
                          ]..removeWhere((id) => id.trim().isEmpty);

                          await _openScreen(
                            RoomChatScreen(
                              conversationId: conversationId,
                              roomTitle: title,
                              conversationType: type,
                              initialParticipants: allParticipants,
                            ),
                          );
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
  }

  Future<String?> _createRoomConversation({
    required String type,
    required String title,
    required List<String> memberIds,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final participants = {user.uid, ...memberIds.map((id) => id.trim())}
      ..removeWhere((id) => id.isEmpty);

    if (participants.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('At least 2 members are required')),
        );
      }
      return null;
    }

    try {
      final ref = _firestore.collection('conversations').doc();
      await ref.set({
        'type': type,
        'title': title,
        'participants': participants.toList(),
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageTime': null,
        'lastSenderId': null,
        'hasMessages': false,
        'encrypted': true,
      });
      return ref.id;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create room: $e')));
      }
      return null;
    }
  }

  bool _isConversationInSelectedFolder(String conversationId) {
    if (_selectedFolderId == null) return true;
    return _folderAssignments[conversationId] == _selectedFolderId;
  }

  Future<void> _assignConversationToFolder(
    String conversationId,
    String? folderId,
  ) async {
    setState(() {
      if (folderId == null || folderId.isEmpty) {
        _folderAssignments.remove(conversationId);
      } else {
        _folderAssignments[conversationId] = folderId;
      }
    });
    await _saveFolderState();
  }

  Future<void> _showMoveConversationSheet({
    required String conversationId,
    required String conversationName,
  }) async {
    final currentFolderId = _folderAssignments[conversationId];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Move "$conversationName"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.all_inbox_outlined),
                title: const Text('All chats'),
                trailing: currentFolderId == null
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _assignConversationToFolder(conversationId, null);
                },
              ),
              ..._folders.map((folder) {
                final isSelected = folder.id == currentFolderId;
                final folderColor = Color(folder.colorValue);
                return ListTile(
                  leading: Icon(Icons.folder, color: folderColor),
                  title: Text(folder.name),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _assignConversationToFolder(conversationId, folder.id);
                  },
                );
              }),
              if (_folders.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Text(
                    'Create a folder first',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Create folder'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateFolderDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _folderName(String folderId) {
    for (final folder in _folders) {
      if (folder.id == folderId) return folder.name;
    }
    return 'folder';
  }

  String _conversationType(Map<String, dynamic> chatData) {
    final raw = chatData['type']?.toString().trim().toLowerCase() ?? '';
    if (raw == 'group' || raw == 'server' || raw == 'direct') return raw;
    return 'direct';
  }

  String? _conversationTypeLabel(String type) {
    if (type == 'group') return 'Group';
    if (type == 'server') return 'Server';
    return null;
  }

  List<String> _participantsFromConversation(Map<String, dynamic> chatData) {
    final participantsRaw = chatData['participants'];
    if (participantsRaw is! List) return const [];
    return participantsRaw
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  String? _resolveDirectOtherUserId(
    Map<String, dynamic> chatData,
    String currentUserId,
  ) {
    final participants = _participantsFromConversation(chatData);
    if (participants.isEmpty) return null;
    for (final id in participants) {
      if (id != currentUserId) return id;
    }
    return null;
  }

  String _resolveConversationTitle(
    Map<String, dynamic> chatData, {
    required String currentUserId,
  }) {
    final type = _conversationType(chatData);
    if (type == 'direct') {
      final otherUserId = _resolveDirectOtherUserId(chatData, currentUserId);
      if (otherUserId == null || otherUserId.isEmpty) return 'User';
      final userData = _userCache.getCachedUser(otherUserId);
      return userData?['displayName']?.toString().trim().isNotEmpty == true
          ? userData!['displayName'].toString().trim()
          : 'User';
    }

    final title = chatData['title']?.toString().trim() ?? '';
    if (title.isNotEmpty) return title;

    final participants = _participantsFromConversation(
      chatData,
    ).where((id) => id != currentUserId).toList();
    if (participants.isEmpty) {
      return type == 'server' ? 'Server' : 'Group chat';
    }

    final names = <String>[];
    for (final uid in participants.take(3)) {
      final data = _userCache.getCachedUser(uid);
      final name = data?['displayName']?.toString().trim();
      names.add((name == null || name.isEmpty) ? 'User' : name);
    }
    if (participants.length > 3) {
      names.add('+${participants.length - 3}');
    }
    return names.join(', ');
  }

  String _resolveLastMessagePreview(Map<String, dynamic> chatData) {
    final raw = chatData['lastMessage']?.toString().trim() ?? '';
    if (raw.isNotEmpty) return raw;
    if (chatData['lastMessageTime'] != null) return 'Sent a message';
    return 'Start chatting';
  }

  Widget _buildRoomAvatar({required String type, required String? avatarUrl}) {
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return _buildAvatar(avatarUrl, 20, null);
    }
    final isServer = type == 'server';
    return CircleAvatar(
      radius: 20,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(
        isServer ? Icons.forum : Icons.groups,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }

  Future<void> _openConversation({
    required Map<String, dynamic> chatData,
    required String currentUserId,
    required String title,
  }) async {
    final type = _conversationType(chatData);
    if (type == 'direct') {
      final otherUserId = _resolveDirectOtherUserId(chatData, currentUserId);
      if (otherUserId == null || otherUserId.isEmpty) return;
      await _openScreen(
        ImprovedChatScreen(recipientId: otherUserId, recipientName: title),
      );
      return;
    }

    final conversationId = chatData['id']?.toString().trim() ?? '';
    if (conversationId.isEmpty) return;
    final participants = _participantsFromConversation(chatData);
    await _openScreen(
      RoomChatScreen(
        conversationId: conversationId,
        roomTitle: title,
        conversationType: type,
        initialParticipants: participants,
      ),
    );
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
          IconButton(
            tooltip: 'Create',
            onPressed: _showCreateSheet,
            icon: const Icon(Icons.add_circle_outline),
          ),
          _buildFriendRequestsBadge(),
        ],
      ),
      drawer: _buildDrawer(context, user),
      body: Column(
        children: [
          _buildFolderSlider(),
          Expanded(child: _buildChatsList()),
        ],
      ),
    );
  }

  Widget _buildFolderSlider() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: _selectedFolderId == null,
            onSelected: (_) {
              setState(() {
                _selectedFolderId = null;
              });
            },
          ),
          const SizedBox(width: 8),
          ..._folders.map((folder) {
            final selected = folder.id == _selectedFolderId;
            final folderColor = Color(folder.colorValue);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(Icons.folder, size: 16, color: folderColor),
                label: Text(folder.name),
                selected: selected,
                selectedColor: folderColor.withValues(alpha: 0.16),
                side: BorderSide(
                  color: selected
                      ? folderColor
                      : colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
                onSelected: (_) {
                  setState(() {
                    _selectedFolderId = folder.id;
                  });
                },
              ),
            );
          }),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Folder'),
            onPressed: _showCreateFolderDialog,
          ),
        ],
      ),
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
                  MaterialPageRoute(
                    builder: (_) => const ImprovedFriendsListScreen(),
                  ),
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
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
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
                MaterialPageRoute(
                  builder: (_) => const ImprovedFriendsListScreen(),
                ),
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
                  const Text(
                    'Secure messaging app with end-to-end encryption.',
                  ),
                ],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: _handleLogout,
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
        final canUseCache =
            (!hasSnapshot ||
                snapshot.connectionState == ConnectionState.waiting) &&
            _cachedConversations.isNotEmpty;
        final waitingForLive =
            (!hasSnapshot ||
            snapshot.connectionState == ConnectionState.waiting);

        if (waitingForLive && !_cacheLoaded) {
          return _buildChatSkeleton();
        }

        if (hasLiveData) {
          _scheduleConversationCacheWrite(user.uid, snapshot.data!.docs);
        } else if (hasSnapshot && snapshot.data!.docs.isEmpty) {
          _scheduleConversationCacheClear(user.uid);
        }

        if (!hasLiveData && !canUseCache) {
          return _buildEmptyChatsState();
        }

        final items = hasLiveData
            ? _conversationCache.buildCacheItemsFromDocs(snapshot.data!.docs)
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

        final visibleItems = sortedDocs.where((chatData) {
          final conversationId = chatData['id']?.toString().trim() ?? '';
          if (conversationId.isEmpty) return false;
          if (!_isConversationInSelectedFolder(conversationId)) return false;

          final title = _resolveConversationTitle(
            chatData,
            currentUserId: user.uid,
          );
          if (title.isEmpty) return false;

          final query = _searchQuery.trim();
          if (query.isNotEmpty && !title.toLowerCase().contains(query)) {
            return false;
          }

          return true;
        }).toList();

        if (visibleItems.isEmpty) {
          return _buildFilteredEmptyState();
        }

        return ListView.builder(
          itemCount: visibleItems.length,
          itemBuilder: (context, index) {
            final chatData = visibleItems[index];
            final conversationId = chatData['id']?.toString().trim() ?? '';
            if (conversationId.isEmpty) {
              return const SizedBox.shrink();
            }

            final type = _conversationType(chatData);
            final title = _resolveConversationTitle(
              chatData,
              currentUserId: user.uid,
            );
            final isDirect = type == 'direct';
            final otherUserId = isDirect
                ? _resolveDirectOtherUserId(chatData, user.uid)
                : null;
            final userData = (otherUserId != null && otherUserId.isNotEmpty)
                ? _userCache.getCachedUser(otherUserId)
                : null;
            final photoURL = isDirect
                ? _normalizePhotoUrl(
                    userData?['photoUrl'] ?? userData?['photoURL'],
                  )
                : _normalizePhotoUrl(chatData['avatarUrl']);
            _prefetchAvatar(photoURL);

            final isOnline = isDirect && userData != null
                ? PresenceService.isUserOnline(userData)
                : false;
            final lastMessageText = _resolveLastMessagePreview(chatData);
            final assignedFolderId = _folderAssignments[conversationId];
            final typeLabel = _conversationTypeLabel(type);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    _openConversation(
                      chatData: chatData,
                      currentUserId: user.uid,
                      title: title,
                    );
                  },
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    leading: isDirect
                        ? Stack(
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
                                        color: Theme.of(
                                          context,
                                        ).scaffoldBackgroundColor,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : _buildRoomAvatar(type: type, avatarUrl: photoURL),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (typeLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      lastMessageText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    trailing: SizedBox(
                      width: 72,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (chatData['lastMessageTime'] is Timestamp)
                            Text(
                              _formatTime(
                                chatData['lastMessageTime'] as Timestamp,
                              ),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          PopupMenuButton<String>(
                            tooltip: 'Chat options',
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.more_vert, size: 20),
                            onSelected: (value) {
                              if (value == 'move') {
                                _showMoveConversationSheet(
                                  conversationId: conversationId,
                                  conversationName: title,
                                );
                                return;
                              }
                              if (value == 'remove_folder') {
                                _assignConversationToFolder(
                                  conversationId,
                                  null,
                                );
                              }
                            },
                            itemBuilder: (menuContext) => [
                              const PopupMenuItem(
                                value: 'move',
                                child: Text('Move to folder'),
                              ),
                              if (assignedFolderId != null)
                                PopupMenuItem(
                                  value: 'remove_folder',
                                  child: Text(
                                    'Remove from ${_folderName(assignedFolderId)}',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyChatsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No chats yet',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Add friends to start chatting',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              _openScreen(const ImprovedFriendsListScreen());
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Add Friends'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyState() {
    final folderName = _selectedFolderId == null
        ? 'All chats'
        : _folderName(_selectedFolderId!);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 66, color: Colors.grey[400]),
            const SizedBox(height: 14),
            Text(
              'No chats in $folderName',
              style: TextStyle(fontSize: 17, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            Text(
              'Move a chat here from the menu on any conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
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

  void _prefetchAvatar(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return;
    if (_prefetchedImageUrls.contains(photoUrl)) return;
    _prefetchedImageUrls.add(photoUrl);
    try {
      precacheImage(CachedNetworkImageProvider(photoUrl), context);
    } catch (_) {
      // Best-effort prefetch only.
    }
  }

  Widget _buildChatSkeleton() {
    return ListView.builder(
      itemCount: 8,
      itemBuilder: (context, index) {
        return ListTile(
          leading: CircleAvatar(radius: 20, backgroundColor: Colors.grey[300]),
          title: _buildSkeletonLine(width: 140, height: 12),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildSkeletonLine(width: 200, height: 10),
          ),
          trailing: _buildSkeletonLine(width: 32, height: 10),
        );
      },
    );
  }

  Widget _buildSkeletonLine({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(6),
      ),
    );
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
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (radius * 2 * dpr).round().clamp(32, 256);
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

class _FriendSeed {
  final String userId;
  final String displayName;
  final String? photoUrl;

  const _FriendSeed({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
  });
}
