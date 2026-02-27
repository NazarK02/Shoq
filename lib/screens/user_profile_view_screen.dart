import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/presence_service.dart';
import '../services/user_cache_service.dart';

class UserProfileViewScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic>? userData;

  const UserProfileViewScreen({super.key, required this.userId, this.userData});

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserCacheService _userCache = UserCacheService();
  Map<String, dynamic>? _userData;
  bool _isOnline = false;
  DateTime? _lastSeen;
  bool _isFriend = false;
  bool _isBlocked = false;
  bool _friendStatusLoading = true;
  String _friendRequestStatus = 'none'; // none, pending_sent, pending_received
  StreamSubscription? _friendSub;
  StreamSubscription? _blockedSub;
  StreamSubscription? _sentReqSub;
  StreamSubscription? _receivedReqSub;
  StreamSubscription? _presenceSub;
  bool _friendChecked = false;
  bool _blockedChecked = false;
  bool _sentChecked = false;
  bool _receivedChecked = false;
  bool _friendDocExists = false;
  bool _blockedDocExists = false;
  bool _sentReqExists = false;
  bool _receivedReqExists = false;
  late final VoidCallback _userCacheListener;

  @override
  void initState() {
    super.initState();
    if (widget.userData != null) {
      _userCache.mergeUserData(widget.userId, widget.userData!);
    }
    _userData = _userCache.getCachedUser(widget.userId) ?? widget.userData;
    _userCacheListener = _syncUserDataFromCache;
    _userCache.addListener(_userCacheListener);
    _warmUserData();
    _listenToOnlineStatus();
    _listenToFriendshipStatus();
  }

  Future<void> _warmUserData() async {
    await _userCache.warmUsers([widget.userId], listen: true);
    _syncUserDataFromCache();
  }

  void _syncUserDataFromCache() {
    final cached = _userCache.getCachedUser(widget.userId);
    if (cached == null || !mounted) return;
    if (_userData != null && mapEquals(_userData, cached)) return;
    setState(() {
      _userData = cached;
    });
  }

  void _listenToOnlineStatus() {
    _presenceSub?.cancel();
    _presenceSub = PresenceService().getUserStatusStream(widget.userId).listen((
      data,
    ) {
      if (!mounted || data == null) return;
      setState(() {
        _isOnline = PresenceService.isUserOnline(data);
        final lastSeen = data['lastSeen'] as Timestamp?;
        _lastSeen = lastSeen?.toDate();
      });
    });
  }

  void _listenToFriendshipStatus() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _friendStatusLoading = true;

    _friendSub?.cancel();
    _blockedSub?.cancel();
    _sentReqSub?.cancel();
    _receivedReqSub?.cancel();

    _friendSub = _firestore
        .collection('contacts')
        .doc(currentUser.uid)
        .collection('friends')
        .doc(widget.userId)
        .snapshots()
        .listen((doc) {
          _friendChecked = true;
          _friendDocExists = doc.exists;
          _updateFriendState();
        });

    _blockedSub = _firestore
        .collection('contacts')
        .doc(currentUser.uid)
        .collection('blocked')
        .doc(widget.userId)
        .snapshots()
        .listen((doc) {
          _blockedChecked = true;
          _blockedDocExists = doc.exists;
          _updateFriendState();
        });

    _sentReqSub = _firestore
        .collection('friendRequests')
        .where('senderId', isEqualTo: currentUser.uid)
        .where('receiverId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((query) {
          _sentChecked = true;
          _sentReqExists = query.docs.isNotEmpty;
          _updateFriendState();
        });

    _receivedReqSub = _firestore
        .collection('friendRequests')
        .where('senderId', isEqualTo: widget.userId)
        .where('receiverId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((query) {
          _receivedChecked = true;
          _receivedReqExists = query.docs.isNotEmpty;
          _updateFriendState();
        });
  }

  void _updateFriendState() {
    final decisive = _friendDocExists || _blockedDocExists;
    final baseReady = _friendChecked && _blockedChecked;
    final requestsReady = _sentChecked && _receivedChecked;
    final ready = decisive || (baseReady && requestsReady);

    if (!ready) {
      if (mounted) setState(() => _friendStatusLoading = true);
      return;
    }

    if (mounted) {
      setState(() {
        _isFriend = _friendDocExists;
        _isBlocked = _blockedDocExists;

        if (_isFriend || _isBlocked) {
          _friendRequestStatus = 'none';
        } else if (_sentReqExists) {
          _friendRequestStatus = 'pending_sent';
        } else if (_receivedReqExists) {
          _friendRequestStatus = 'pending_received';
        } else {
          _friendRequestStatus = 'none';
        }

        _friendStatusLoading = false;
      });
    }
  }

  String _getBio() {
    final bio = _userData?['bio'] as String?;
    if (bio != null && bio.trim().isNotEmpty) return bio.trim();
    final legacy = _userData?['status'] as String?;
    if (legacy != null) {
      final trimmed = legacy.trim();
      if (trimmed.isNotEmpty && trimmed != 'online' && trimmed != 'offline') {
        return trimmed;
      }
    }
    return '';
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Friend request sent!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Friend removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User blocked')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User unblocked')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  @override
  void dispose() {
    _userCache.removeListener(_userCacheListener);
    _friendSub?.cancel();
    _blockedSub?.cancel();
    _sentReqSub?.cancel();
    _receivedReqSub?.cancel();
    _presenceSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _pickPhotoUrl();
    final displayName = _userData?['displayName'] ?? 'User';
    final email = _userData?['email'] ?? '';
    final friendId = _userData?['friendId']?.toString().trim() ?? '';
    final bio = _getBio();
    final location = _userData?['location'] ?? '';
    final joinDate = _userData?['createdAt'] as Timestamp?;
    final socialLinks = _getSocialLinks();

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
                  child: _buildAvatar(photoUrl, 70),
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
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),

          // Status
          if (bio.isNotEmpty)
            Center(
              child: Text(
                bio,
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
              label: const Text(
                'Friends',
                style: TextStyle(color: Colors.green),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Colors.green),
              ),
            )
          else if (_friendStatusLoading)
            const SizedBox(height: 48)
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
                if (friendId.isNotEmpty) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.alternate_email),
                    title: const Text('Friend ID'),
                    subtitle: Text('@$friendId'),
                  ),
                ],
                if (location.isNotEmpty) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: const Text('Location'),
                    subtitle: Text(location),
                  ),
                ],
                if (socialLinks.isNotEmpty) ...[
                  const Divider(height: 1),
                  ..._buildSocialLinksSection(socialLinks),
                ],
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
                  const SnackBar(
                    content: Text('Shared media feature coming soon'),
                  ),
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

  List<Map<String, String>> _getSocialLinks() {
    final raw = _userData?['socialLinks'];
    final result = <Map<String, String>>[];

    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final platform = map['platform']?.toString() ?? '';
        final url = map['url']?.toString() ?? '';
        if (platform.trim().isEmpty && url.trim().isEmpty) continue;
        result.add({'platform': platform.trim(), 'url': url.trim()});
      }
    }

    if (result.isEmpty) {
      final legacyWebsite = _userData?['website']?.toString() ?? '';
      if (legacyWebsite.trim().isNotEmpty) {
        result.add({'platform': 'Website', 'url': legacyWebsite.trim()});
      }
    }

    return result;
  }

  IconData _iconForPlatform(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('youtube')) return Icons.play_circle_fill;
    if (p.contains('steam')) return Icons.sports_esports;
    if (p.contains('facebook')) return Icons.facebook;
    if (p.contains('instagram')) return Icons.camera_alt;
    if (p == 'x' || p.contains('twitter')) return Icons.alternate_email;
    if (p.contains('tiktok')) return Icons.music_note;
    if (p.contains('github')) return Icons.code;
    if (p.contains('twitch')) return Icons.videogame_asset;
    if (p.contains('discord')) return Icons.forum;
    if (p.contains('linkedin')) return Icons.business;
    return Icons.link;
  }

  String? _faviconUrlForLink(String platform, String input) {
    final resolved = _resolveSocialUrl(platform, input) ?? input;
    final uri = Uri.tryParse(resolved);
    var host = uri?.host ?? '';

    if (host.isEmpty) {
      final p = platform.toLowerCase();
      if (p.contains('youtube')) host = 'www.youtube.com';
      if (p.contains('steam')) host = 'steamcommunity.com';
      if (p.contains('facebook')) host = 'www.facebook.com';
      if (p.contains('instagram')) host = 'www.instagram.com';
      if (p.contains('tiktok')) host = 'www.tiktok.com';
      if (p == 'x' || p.contains('twitter')) host = 'x.com';
      if (p.contains('twitch')) host = 'www.twitch.tv';
      if (p.contains('github')) host = 'github.com';
      if (p.contains('linkedin')) host = 'www.linkedin.com';
    }

    if (host.isEmpty) return null;
    return 'https://www.google.com/s2/favicons?domain=$host&sz=64';
  }

  String? _resolveSocialUrl(String platform, String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final handle = raw.startsWith('@') ? raw.substring(1) : raw;
    final p = platform.toLowerCase();

    if (p.contains('youtube')) return 'https://www.youtube.com/@$handle';
    if (p.contains('steam')) return 'https://steamcommunity.com/id/$handle';
    if (p.contains('facebook')) return 'https://www.facebook.com/$handle';
    if (p.contains('instagram')) return 'https://www.instagram.com/$handle';
    if (p.contains('tiktok')) return 'https://www.tiktok.com/@$handle';
    if (p == 'x' || p.contains('twitter')) return 'https://x.com/$handle';
    if (p.contains('twitch')) return 'https://www.twitch.tv/$handle';
    if (p.contains('github')) return 'https://github.com/$handle';
    if (p.contains('linkedin')) return 'https://www.linkedin.com/in/$handle';

    if (raw.contains('.')) return 'https://$raw';
    return null;
  }

  Widget _buildSocialIcon(Map<String, String> link) {
    final platform = link['platform']?.trim() ?? '';
    final url = link['url']?.trim() ?? '';
    final faviconUrl = _faviconUrlForLink(platform, url);

    if (faviconUrl == null) {
      return Icon(_iconForPlatform(platform));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: faviconUrl,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        memCacheWidth: 48,
        memCacheHeight: 48,
        placeholder: (_, url) => Icon(_iconForPlatform(platform)),
        errorWidget: (_, url, error) => Icon(_iconForPlatform(platform)),
        fadeInDuration: const Duration(milliseconds: 100),
        fadeOutDuration: const Duration(milliseconds: 100),
      ),
    );
  }

  Future<void> _openSocialLink(Map<String, String> link) async {
    final platform = link['platform'] ?? '';
    final url = link['url'] ?? '';
    final resolved = _resolveSocialUrl(platform, url) ?? url;
    if (resolved.trim().isEmpty) return;

    final uri = Uri.tryParse(resolved);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid link')));
      }
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  Widget _buildSocialLinkTile(Map<String, String> link) {
    final platform = link['platform']?.trim() ?? '';
    final url = link['url']?.trim() ?? '';
    final title = platform.isEmpty ? 'Link' : platform;

    return ListTile(
      leading: _buildSocialIcon(link),
      title: Text(title),
      subtitle: Text(url.isEmpty ? 'No link' : url),
      trailing: url.isEmpty ? null : const Icon(Icons.open_in_new, size: 16),
      onTap: url.isEmpty ? null : () => _openSocialLink(link),
    );
  }

  List<Widget> _buildSocialLinksSection(List<Map<String, String>> links) {
    final tiles = <Widget>[
      const ListTile(
        leading: Icon(Icons.link),
        title: Text('Other Social Media'),
        subtitle: Text('Tap a link to open'),
      ),
    ];

    for (final link in links) {
      tiles.add(const Divider(height: 1));
      tiles.add(_buildSocialLinkTile(link));
    }

    return tiles;
  }

  Widget _buildAvatar(String? photoUrl, double radius) {
    final placeholder = Container(
      width: radius * 2,
      height: radius * 2,
      color: Colors.grey[300],
      child: Icon(Icons.person, size: radius, color: Colors.grey[600]),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey[300],
        child: Icon(Icons.person, size: radius, color: Colors.grey[600]),
      );
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (radius * 2 * dpr).round().clamp(64, 512);
    // Windows-specific handling to prevent crashes
    if (Platform.isWindows) {
      return ClipOval(
        child: Image(
          image: CachedNetworkImageProvider(photoUrl),
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
          errorBuilder: (_, error, stackTrace) => placeholder,
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
        placeholder: (_, url) => placeholder,
        errorWidget: (_, url, error) => placeholder,
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: const Duration(milliseconds: 150),
      ),
    );
  }

  String? _pickPhotoUrl() {
    final candidates = [_userData?['photoUrl'], _userData?['photoURL']];

    for (final value in candidates) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
