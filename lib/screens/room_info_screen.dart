import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/user_cache_service.dart';
import 'image_viewer_screen.dart';
import 'video_viewer_screen.dart';

class RoomInfoScreen extends StatefulWidget {
  final String conversationId;
  final String conversationType;

  const RoomInfoScreen({
    super.key,
    required this.conversationId,
    required this.conversationType,
  });

  @override
  State<RoomInfoScreen> createState() => _RoomInfoScreenState();
}

class _RoomInfoScreenState extends State<RoomInfoScreen> {
  static const String _inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final UserCacheService _userCache = UserCacheService();
  final Random _random = Random.secure();

  Map<String, dynamic>? _conversation;
  List<String> _participants = [];
  List<_ServerChannel> _channels = const [_ServerChannel.general];
  bool _isUploadingIcon = false;
  bool _isSaving = false;
  bool _isInviteBusy = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _conversationSub;

  bool get _isServer => widget.conversationType == 'server';
  String get _currentUid => _auth.currentUser?.uid ?? '';
  bool get _canManage {
    final data = _conversation;
    if (data == null) return false;

    final adminsRaw = data['admins'];
    if (adminsRaw is List) {
      final admins = adminsRaw
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      if (admins.contains(_currentUid)) return true;
    }

    return data['createdBy']?.toString().trim() == _currentUid;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _listenConversation();
  }

  void _listenConversation() {
    _conversationSub?.cancel();
    _conversationSub = _firestore
        .collection('conversations')
        .doc(widget.conversationId)
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            if (data == null || !mounted) return;

            final participants = _parseParticipants(data['participants']);
            _userCache.warmUsers(participants.toSet(), listen: false);

            setState(() {
              _conversation = data;
              _participants = participants;
              _channels = _parseChannels(data['channels']);
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              _showSnack(
                'Permission denied while loading room info. Check Firestore conversation rules.',
              );
              return;
            }
            _showSnack('Could not load room info: $error');
          },
        );
  }

  List<String> _parseParticipants(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  List<_ServerChannel> _parseChannels(dynamic raw) {
    final parsed = <_ServerChannel>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id']?.toString().trim() ?? '';
        final name = map['name']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty) continue;
        parsed.add(_ServerChannel(id: id, name: name));
      }
    }
    if (parsed.isEmpty) return const [_ServerChannel.general];

    final byId = <String, _ServerChannel>{};
    for (final channel in parsed) {
      byId[channel.id] = channel;
    }
    if (!byId.containsKey(_ServerChannel.general.id)) {
      byId[_ServerChannel.general.id] = _ServerChannel.general;
    }
    return byId.values.toList();
  }

  String _activeInviteCode() {
    final code = _conversation?['activeInviteCode']?.toString().trim() ?? '';
    if (code.isEmpty) return '';
    return code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  String _inviteLinkForCode(String code) {
    return 'shoq://join-server?code=$code';
  }

  String _randomInviteCode() {
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      final index = _random.nextInt(_inviteAlphabet.length);
      buffer.write(_inviteAlphabet[index]);
    }
    return buffer.toString();
  }

  Future<String> _allocateInviteCode() async {
    for (var i = 0; i < 12; i++) {
      final code = _randomInviteCode();
      final doc = await _firestore
          .collection('serverInvites')
          .doc(code)
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return code;
    }
    throw Exception('Could not generate a unique invite code');
  }

  Future<void> _createInviteLink() async {
    if (!_isServer || !_canManage || _isInviteBusy) return;
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _isInviteBusy = true;
    });
    try {
      final newCode = await _allocateInviteCode();
      final previousCode = _activeInviteCode();
      final batch = _firestore.batch();
      final inviteRef = _firestore.collection('serverInvites').doc(newCode);

      batch.set(inviteRef, {
        'code': newCode,
        'serverId': widget.conversationId,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'revokedAt': null,
        'useCount': 0,
      });

      if (previousCode.isNotEmpty && previousCode != newCode) {
        final previousRef = _firestore
            .collection('serverInvites')
            .doc(previousCode);
        batch.set(previousRef, {
          'revokedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      batch.set(
        _firestore.collection('conversations').doc(widget.conversationId),
        {
          'activeInviteCode': newCode,
          'admins': FieldValue.arrayUnion([user.uid]),
          'inviteUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();

      final link = _inviteLinkForCode(newCode);
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      _showSnack('Invite link copied');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _showSnack(
          'Permission denied while creating invite. Update Firestore rules for server invites.',
        );
        return;
      }
      final detail = e.message?.trim();
      _showSnack(
        detail == null || detail.isEmpty
            ? 'Could not create invite (${e.code})'
            : 'Could not create invite: $detail',
      );
    } catch (e) {
      _showSnack('Could not create invite: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isInviteBusy = false;
        });
      }
    }
  }

  Future<void> _copyInviteLink() async {
    final code = _activeInviteCode();
    if (code.isEmpty) return;
    final link = _inviteLinkForCode(code);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    _showSnack('Invite link copied');
  }

  Future<void> _revokeInviteLink() async {
    if (!_isServer || !_canManage || _isInviteBusy) return;
    final code = _activeInviteCode();
    if (code.isEmpty) return;

    setState(() {
      _isInviteBusy = true;
    });
    try {
      final batch = _firestore.batch();
      batch.set(_firestore.collection('serverInvites').doc(code), {
        'revokedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(
        _firestore.collection('conversations').doc(widget.conversationId),
        {'activeInviteCode': null},
        SetOptions(merge: true),
      );
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _showSnack(
          'Permission denied while revoking invite. Update Firestore rules for server invites.',
        );
        return;
      }
      final detail = e.message?.trim();
      _showSnack(
        detail == null || detail.isEmpty
            ? 'Could not revoke invite (${e.code})'
            : 'Could not revoke invite: $detail',
      );
    } catch (e) {
      _showSnack('Could not revoke invite: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isInviteBusy = false;
        });
      }
    }
  }

  Future<void> _updateConversation(Map<String, dynamic> payload) async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });
    try {
      await _firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .set(payload, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _showSnack(
          'Permission denied while updating room. Check Firestore conversation rules.',
        );
        return;
      }
      final detail = e.message?.trim();
      _showSnack(
        detail == null || detail.isEmpty
            ? 'Failed to update (${e.code})'
            : 'Failed to update: $detail',
      );
    } catch (e) {
      _showSnack('Failed to update: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _editName() async {
    var nameDraft = _conversation?['title']?.toString() ?? '';
    final navigator = Navigator.of(context, rootNavigator: true);
    final name = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(_isServer ? 'Edit server name' : 'Edit group name'),
        content: TextFormField(
          initialValue: nameDraft,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Name'),
          onChanged: (value) {
            nameDraft = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => navigator.pop(nameDraft.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await _updateConversation({'title': name.trim()});
  }

  Future<void> _editDescription() async {
    var descriptionDraft = _conversation?['description']?.toString() ?? '';
    final navigator = Navigator.of(context, rootNavigator: true);
    final description = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Edit description'),
        content: TextFormField(
          initialValue: descriptionDraft,
          minLines: 3,
          maxLines: 6,
          maxLength: 260,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Write a description...'),
          onChanged: (value) {
            descriptionDraft = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => navigator.pop(descriptionDraft.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (description == null) return;
    await _updateConversation({'description': description});
  }

  Future<void> _pickAndUploadIcon() async {
    if (_isUploadingIcon) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    setState(() {
      _isUploadingIcon = true;
    });

    try {
      final ref = _storage.ref().child(
        'chat_files/${widget.conversationId}/room_icon_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      UploadTask uploadTask;
      if (file.path != null && file.path!.trim().isNotEmpty) {
        uploadTask = ref.putFile(
          File(file.path!),
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else if (file.bytes != null) {
        uploadTask = ref.putData(
          file.bytes!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else {
        throw Exception('Selected image has no data');
      }

      final uploadResult = await uploadTask;
      final downloadUrl = await uploadResult.ref.getDownloadURL();
      await _updateConversation({'avatarUrl': downloadUrl});
    } catch (e) {
      _showSnack('Could not upload icon: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingIcon = false;
        });
      }
    }
  }

  Future<List<_FriendSeed>> _loadFriendsNotInRoom() async {
    if (_currentUid.isEmpty) return const [];
    final snapshot = await _firestore
        .collection('contacts')
        .doc(_currentUid)
        .collection('friends')
        .get();

    final existing = _participants.toSet();
    final result = <_FriendSeed>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final uid = data['userId']?.toString().trim() ?? '';
      if (uid.isEmpty || existing.contains(uid)) continue;
      final displayName = data['displayName']?.toString().trim();
      final photo = _normalizePhotoUrl(data['photoURL'] ?? data['photoUrl']);
      result.add(
        _FriendSeed(
          userId: uid,
          displayName: (displayName == null || displayName.isEmpty)
              ? 'User'
              : displayName,
          photoUrl: photo,
        ),
      );
    }
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  Future<void> _addMembers() async {
    final candidates = await _loadFriendsNotInRoom();
    if (!mounted) return;
    if (candidates.isEmpty) {
      _showSnack('No additional friends to add');
      return;
    }

    final selected = <String>{};
    final navigator = Navigator.of(context, rootNavigator: true);
    final shouldAdd = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add members'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView.builder(
              itemCount: candidates.length,
              itemBuilder: (context, index) {
                final friend = candidates[index];
                final isSelected = selected.contains(friend.userId);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        selected.add(friend.userId);
                      } else {
                        selected.remove(friend.userId);
                      }
                    });
                  },
                  secondary: CircleAvatar(
                    backgroundColor: Colors.grey[300],
                    backgroundImage: friend.photoUrl != null
                        ? CachedNetworkImageProvider(friend.photoUrl!)
                        : null,
                    child: friend.photoUrl == null
                        ? Icon(Icons.person, color: Colors.grey[700], size: 18)
                        : null,
                  ),
                  title: Text(friend.displayName),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty ? null : () => navigator.pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (shouldAdd != true || selected.isEmpty) return;
    final updated = {..._participants, ...selected}.toList();
    await _updateConversation({'participants': updated});
  }

  Future<void> _showAddChannelDialog() async {
    if (!_canManage) return;
    var channelDraft = '';
    final navigator = Navigator.of(context, rootNavigator: true);
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Create text channel'),
        content: TextField(
          maxLength: 24,
          decoration: const InputDecoration(hintText: 'news, clips, memes'),
          onChanged: (value) {
            channelDraft = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => navigator.pop(channelDraft.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    final raw = result?.trim() ?? '';
    if (raw.isEmpty) return;
    final normalizedId = raw.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '-',
    );
    final name = raw.replaceAll(RegExp(r'\s+'), '-').toLowerCase();
    if (normalizedId.isEmpty) return;

    final exists = _channels.any((c) => c.id == normalizedId);
    if (exists) {
      if (!mounted) return;
      _showSnack('Channel already exists');
      return;
    }

    final updated = [
      ..._channels,
      _ServerChannel(id: normalizedId, name: name),
    ];
    await _updateConversation({
      'channels': updated
          .map((channel) => {'id': channel.id, 'name': channel.name})
          .toList(),
    });
  }

  Future<void> _removeChannel(_ServerChannel channel) async {
    if (!_canManage) return;
    if (channel.id == _ServerChannel.general.id) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Delete channel'),
        content: Text(
          'Delete #${channel.name}? Existing messages stay in history.',
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => navigator.pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final updated = _channels.where((c) => c.id != channel.id).toList();
    await _updateConversation({
      'channels': updated.map((c) => {'id': c.id, 'name': c.name}).toList(),
    });
  }

  String _memberName(String uid) {
    final data = _userCache.getCachedUser(uid);
    final value = data?['displayName']?.toString().trim() ?? '';
    if (uid == _currentUid) return 'You';
    if (value.isNotEmpty) return value;
    return 'Member';
  }

  String? _memberPhoto(String uid) {
    final data = _userCache.getCachedUser(uid);
    return _normalizePhotoUrl(data?['photoUrl'] ?? data?['photoURL']);
  }

  String? _normalizePhotoUrl(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return null;
    return text;
  }

  @override
  void dispose() {
    _conversationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _conversation;
    final title = data?['title']?.toString().trim();
    final displayTitle = (title == null || title.isEmpty)
        ? (_isServer ? 'Server' : 'Group')
        : title;
    final description = data?['description']?.toString().trim() ?? '';
    final avatarUrl = _normalizePhotoUrl(data?['avatarUrl']);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isServer ? 'Server profile' : 'Group profile'),
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                _buildHeaderCard(
                  title: displayTitle,
                  description: description,
                  avatarUrl: avatarUrl,
                ),
                const SizedBox(height: 12),
                _buildMembersCard(),
                const SizedBox(height: 12),
                if (_isServer) ...[
                  _buildInvitesCard(),
                  const SizedBox(height: 12),
                ],
                _buildMediaCard(),
                if (_isServer) ...[
                  const SizedBox(height: 12),
                  _buildChannelsCard(),
                ],
              ],
            ),
    );
  }

  Widget _buildHeaderCard({
    required String title,
    required String description,
    required String? avatarUrl,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: avatarUrl != null
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl == null
                      ? Icon(
                          _isServer ? Icons.hub : Icons.group,
                          size: 34,
                          color: Colors.grey[700],
                        )
                      : null,
                ),
                if (_canManage)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: IconButton.filledTonal(
                      onPressed: _isUploadingIcon ? null : _pickAndUploadIcon,
                      icon: _isUploadingIcon
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit, size: 18),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              description.isEmpty ? 'No description' : description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_canManage) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _editName,
                    icon: const Icon(Icons.badge_outlined),
                    label: Text(_isServer ? 'Rename server' : 'Rename group'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _editDescription,
                    icon: const Icon(Icons.notes),
                    label: const Text('Edit description'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMembersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Members (${_participants.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_canManage && !_isServer)
                  TextButton.icon(
                    onPressed: _addMembers,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (final uid in _participants.take(14))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: _memberPhoto(uid) != null
                      ? CachedNetworkImageProvider(_memberPhoto(uid)!)
                      : null,
                  child: _memberPhoto(uid) == null
                      ? Icon(Icons.person, size: 16, color: Colors.grey[700])
                      : null,
                ),
                title: Text(_memberName(uid)),
                subtitle: Text(
                  uid == _currentUid ? 'You' : uid,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitesCard() {
    final code = _activeInviteCode();
    final hasInvite = code.isNotEmpty;
    final link = hasInvite ? _inviteLinkForCode(code) : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Invite links',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_canManage)
                  TextButton.icon(
                    onPressed: _isInviteBusy ? null : _createInviteLink,
                    icon: _isInviteBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(hasInvite ? 'New link' : 'Create'),
                  ),
              ],
            ),
            if (!hasInvite) ...[
              Text(
                'Create a link so people can join this server.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              SelectableText(
                link,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _copyInviteLink,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                  if (_canManage)
                    TextButton.icon(
                      onPressed: _isInviteBusy ? null : _revokeInviteLink,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Revoke'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMediaCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Media', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('conversations')
                  .doc(widget.conversationId)
                  .collection('messages')
                  .orderBy('clientTimestamp', descending: true)
                  .limit(160)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                final files = docs
                    .map((d) => {'id': d.id, 'data': d.data()})
                    .where((entry) => entry['data'] is Map<String, dynamic>)
                    .cast<Map<String, dynamic>>()
                    .where(
                      (entry) =>
                          (entry['data'] as Map<String, dynamic>)['type']
                              ?.toString() ==
                          'file',
                    )
                    .where(
                      (entry) =>
                          (((entry['data'] as Map<String, dynamic>)['fileUrl']
                                      ?.toString()
                                      .trim() ??
                                  '')
                              .isNotEmpty),
                    )
                    .toList();

                final media = files.where((entry) {
                  final map = entry['data'] as Map<String, dynamic>;
                  final mime = map['mimeType']?.toString().toLowerCase() ?? '';
                  return mime.startsWith('image/') || mime.startsWith('video/');
                }).toList();

                if (media.isEmpty) {
                  return Text(
                    'No shared media yet',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  );
                }

                final crossAxisCount = MediaQuery.of(context).size.width > 700
                    ? 4
                    : 3;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: media.length.clamp(0, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final entry = media[index];
                    final data = entry['data'] as Map<String, dynamic>;
                    final messageId = entry['id']?.toString() ?? '';
                    final fileUrl = data['fileUrl']?.toString() ?? '';
                    final fileName = data['fileName']?.toString() ?? 'media';
                    final fileSize = data['fileSize'] is num
                        ? (data['fileSize'] as num).toInt()
                        : 0;
                    final mimeType =
                        data['mimeType']?.toString().toLowerCase() ?? '';
                    final isVideo = mimeType.startsWith('video/');

                    return InkWell(
                      onTap: () {
                        if (isVideo) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VideoViewerScreen(
                                messageId: messageId.isEmpty
                                    ? 'media_$index'
                                    : messageId,
                                videoUrl: fileUrl,
                                localPath: null,
                                fileName: fileName,
                                fileSize: fileSize,
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ImageViewerScreen(
                              imageUrl: fileUrl,
                              fileName: fileName,
                              fileSize: fileSize,
                            ),
                          ),
                        );
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: fileUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    Container(color: Colors.grey[300]),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                          ),
                          if (isVideo)
                            const Positioned(
                              right: 6,
                              bottom: 6,
                              child: Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Text channels',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_canManage)
                  TextButton.icon(
                    onPressed: _showAddChannelDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (final channel in _channels)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tag, size: 18),
                title: Text(channel.name),
                trailing:
                    (_canManage && channel.id != _ServerChannel.general.id)
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _removeChannel(channel),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _ServerChannel {
  final String id;
  final String name;

  const _ServerChannel({required this.id, required this.name});

  static const _ServerChannel general = _ServerChannel(
    id: 'general',
    name: 'general',
  );
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
