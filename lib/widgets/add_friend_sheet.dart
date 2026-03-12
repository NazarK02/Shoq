import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/qr_scanner_screen.dart';

/// Bottom sheet for adding a new friend.
///
/// The user can either:
///   (a) type a UID or email into the search field, or
///   (b) tap "Scan QR" to open the camera scanner on mobile.
///
/// On desktop (Windows / macOS / Linux) the QR scan button is hidden
/// because mobile_scanner requires a device camera.
///
/// On a successful lookup the [onFriendResolved] callback receives the
/// Firestore user document so the caller can send a friend request.
class AddFriendSheet extends StatefulWidget {
  const AddFriendSheet({
    super.key,
    required this.onFriendResolved,
  });

  /// Called with the Firestore user document when a valid user is found.
  final void Function(Map<String, dynamic> userData) onFriendResolved;

  static Future<void> show(
    BuildContext context, {
    required void Function(Map<String, dynamic>) onFriendResolved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: AddFriendSheet(onFriendResolved: onFriendResolved),
      ),
    );
  }

  @override
  State<AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<AddFriendSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final db = FirebaseFirestore.instance;
      QuerySnapshot snap;

      if (q.startsWith("@")) {
        final friendId = q.substring(1).trim();
        if (friendId.isEmpty) {
          setState(() => _error = 'Enter a valid friend ID.');
          return;
        }
        snap = await db
            .collection('users')
            .where('friendIdLower', isEqualTo: friendId.toLowerCase())
            .limit(1)
            .get();
      } else if (q.contains('@')) {
        // Search by email (case-insensitive)
        snap = await db
            .collection('users')
            .where('emailLower', isEqualTo: q.toLowerCase())
            .limit(1)
            .get();
      } else {
        // Treat as UID - direct document fetch is faster than a query
        final doc = await db.collection('users').doc(q).get();
        if (doc.exists) {
          final data = {'uid': doc.id, ...doc.data()!};
          setState(() => _result = data);
          return;
        }
        // Fallback: friendId without leading "@"
        snap = await db
            .collection('users')
            .where('friendIdLower', isEqualTo: q.toLowerCase())
            .limit(1)
            .get();
      }

      if (snap.docs.isEmpty) {
        setState(() => _error = 'No user found with that ID or email.');
      } else {
        final doc = snap.docs.first;
        setState(() =>
            _result = {'uid': doc.id, ...doc.data() as Map<String, dynamic>});
      }
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
      debugPrint('AddFriendSheet search error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openScanner() async {
    final uid = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (uid == null || !mounted) return;

    // Populate the field so the user sees what was scanned, then search.
    _controller.text = uid;
    await _search(uid);
  }

  void _confirm() {
    if (_result == null) return;
    Navigator.of(context).pop();
    widget.onFriendResolved(_result!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text(
            'Add Friend',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),

          // Search field
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'UID, email, or @friendId',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            onSubmitted: _search,
          ),

          // QR scan button — mobile only
          if (_isMobile) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner_outlined),
              label: const Text('Scan QR Code'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],

          // Error
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
          ],

          // Result card
          if (_result != null) ...[
            const SizedBox(height: 20),
            _UserResultCard(
              data: _result!,
              onAdd: _confirm,
            ),
          ],
        ],
      ),
    );
  }
}

/// Displays a resolved user profile with an "Add" button.
class _UserResultCard extends StatelessWidget {
  const _UserResultCard({required this.data, required this.onAdd});

  final Map<String, dynamic> data;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = data['displayName'] as String? ?? 'Unknown';
    final photoUrl = data['photoUrl'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage:
                photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  data['email'] as String? ?? data['uid'] as String? ?? '',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

