import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils/qr_utils.dart';

/// Displays the current user's QR code in a modal bottom sheet.
/// The user can share the QR as an image via the system share sheet.
///
/// Usage:
///   MyQrSheet.show(context, uid: currentUser.uid, displayName: 'Alice');
class MyQrSheet extends StatefulWidget {
  const MyQrSheet({
    super.key,
    required this.uid,
    required this.displayName,
  });

  final String uid;
  final String displayName;

  static Future<void> show(
    BuildContext context, {
    required String uid,
    required String displayName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MyQrSheet(uid: uid, displayName: displayName),
    );
  }

  @override
  State<MyQrSheet> createState() => _MyQrSheetState();
}

class _MyQrSheetState extends State<MyQrSheet> {
  final _repaintKey = GlobalKey();
  bool _sharing = false;

  String get _payload => QrUtils.encodeUser(widget.uid);

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      // Render the QR widget to an image for sharing.
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/shoq_qr.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Add me on Shoq: $_payload',
      );
    } catch (e) {
      debugPrint('QR share error: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
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
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: cs.onSurface.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Text(
            'My QR Code',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.displayName,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 28),

          // QR code — wrapped in RepaintBoundary for capture
          RepaintBoundary(
            key: _repaintKey,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: _payload,
                version: QrVersions.auto,
                size: 220,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF111111),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF111111),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // UID label — user can copy it manually if needed
          SelectableText(
            widget.uid,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.4),
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 28),

          FilledButton.icon(
            onPressed: _sharing ? null : _share,
            icon: _sharing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.share_outlined),
            label: const Text('Share QR'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}
