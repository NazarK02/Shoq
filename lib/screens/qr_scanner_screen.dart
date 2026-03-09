import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/utils/qr_utils.dart';

/// Full-screen QR scanner for reading a friend's Shoq QR code.
///
/// Returns the decoded UID via Navigator.pop(context, uid) on success.
/// Returns null if the user dismisses without scanning.
///
/// Only available on mobile (Android / iOS). The caller is responsible
/// for gating this on [kIsDesktop] or platform checks — desktop does
/// not have a camera API through mobile_scanner.
///
/// Usage:
///   final uid = await Navigator.push<String>(
///     context,
///     MaterialPageRoute(builder: (_) => const QrScannerScreen()),
///   );
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final uid = QrUtils.decodeUser(raw);
      if (uid != null) {
        _handled = true;
        _controller.stop();
        Navigator.of(context).pop(uid);
        return;
      }
    }

    // Scanned something, but it's not a Shoq QR — show a brief error.
    _showInvalidSnack();
  }

  void _showInvalidSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Not a valid Shoq QR code.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_outlined),
            tooltip: 'Toggle torch',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Viewfinder overlay
          _ScanOverlay(),

          // Hint text at the bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 48),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Point the camera at a Shoq QR code',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple square viewfinder cutout overlay.
class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  static const _size = 240.0;
  static const _cornerLength = 24.0;
  static const _cornerRadius = 4.0;
  static const _strokeWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final left = cx - _size / 2;
    final top = cy - _size / 2;
    final right = cx + _size / 2;
    final bottom = cy + _size / 2;

    // Dim everything outside the square
    final dimPaint = Paint()..color = Colors.black.withOpacity(0.55);
    canvas
      ..drawRect(Rect.fromLTWH(0, 0, size.width, top), dimPaint)
      ..drawRect(Rect.fromLTWH(0, bottom, size.width, size.height - bottom), dimPaint)
      ..drawRect(Rect.fromLTWH(0, top, left, _size), dimPaint)
      ..drawRect(Rect.fromLTWH(right, top, size.width - right, _size), dimPaint);

    // Corner brackets
    final bracketPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void drawCorner(double x, double y, double dx, double dy) {
      final path = Path()
        ..moveTo(x, y + dy * _cornerLength)
        ..lineTo(x, y)
        ..lineTo(x + dx * _cornerLength, y);
      canvas.drawPath(path, bracketPaint);
    }

    drawCorner(left, top, 1, 1);
    drawCorner(right, top, -1, 1);
    drawCorner(left, bottom, 1, -1);
    drawCorner(right, bottom, -1, -1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
