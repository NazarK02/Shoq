import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum _EditorTool { move, pencil, eraser }

class PhotoEditorScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const PhotoEditorScreen({
    super.key,
    required this.filePath,
    this.title = 'Edit image',
  });

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  static const double _minZoom = 1.0;
  static const double _maxZoom = 5.0;
  static const double _outputSize = 1024.0;
  static const int _maxDecodeDimension = 2048;
  static const List<Color> _pencilPalette = [
    Color(0xFFFFFFFF),
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF007AFF),
    Color(0xFFAF52DE),
    Color(0xFF000000),
  ];

  ui.Image? _image;
  bool _isLoading = true;
  String? _error;

  _EditorTool _tool = _EditorTool.move;
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  double _circleScale = 0.82;
  double _strokeWidth = 4.5;
  Color _activeColor = _pencilPalette[1];

  List<_Stroke> _strokes = [];
  List<_Stroke> _redoStack = [];
  List<Offset> _activeStrokePoints = const [];
  double _activeStrokeWidthImageSpace = 1.0;
  bool _isDrawing = false;

  double _startZoom = 1.0;
  Offset _startPan = Offset.zero;
  Offset _startFocalPoint = Offset.zero;

  Size _canvasSize = Size.zero;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadImage());
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.filePath);
      if (!file.existsSync()) {
        throw Exception('Image file not found');
      }
      final bytes = await file.readAsBytes();
      final image = await _decodeImage(bytes);
      if (!mounted) return;
      setState(() {
        _image = image;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not open image: $e';
      });
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    return _decodeImageWithDownscale(bytes);
  }

  Future<ui.Image> _decodeImageWithDownscale(Uint8List bytes) async {
    final probeCodec = await ui.instantiateImageCodec(bytes);
    final probeFrame = await probeCodec.getNextFrame();
    final sourceWidth = probeFrame.image.width;
    final sourceHeight = probeFrame.image.height;
    probeFrame.image.dispose();
    probeCodec.dispose();

    final sourceMax = math.max(sourceWidth, sourceHeight);
    if (sourceMax <= _maxDecodeDimension) {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    }

    final scale = _maxDecodeDimension / sourceMax;
    final targetWidth = math.max(1, (sourceWidth * scale).round());
    final targetHeight = math.max(1, (sourceHeight * scale).round());
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Rect _imageRectForCanvas(Size size, ui.Image image, double zoom, Offset pan) {
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final baseScale = math.max(
      size.width / imageWidth,
      size.height / imageHeight,
    );
    final drawWidth = imageWidth * baseScale * zoom;
    final drawHeight = imageHeight * baseScale * zoom;
    final center = size.center(Offset.zero) + pan;
    return Rect.fromCenter(
      center: center,
      width: drawWidth,
      height: drawHeight,
    );
  }

  Offset _clampPan({
    required Size canvasSize,
    required ui.Image image,
    required double zoom,
    required Offset candidate,
  }) {
    final rect = _imageRectForCanvas(canvasSize, image, zoom, Offset.zero);
    final cropDiameter = canvasSize.width * _circleScale;
    final maxX = math.max(0.0, (rect.width - cropDiameter) / 2);
    final maxY = math.max(0.0, (rect.height - cropDiameter) / 2);
    return Offset(
      candidate.dx.clamp(-maxX, maxX).toDouble(),
      candidate.dy.clamp(-maxY, maxY).toDouble(),
    );
  }

  Offset _canvasToImagePoint({
    required Offset canvasPoint,
    required Rect imageRect,
    required ui.Image image,
  }) {
    final normalizedX = ((canvasPoint.dx - imageRect.left) / imageRect.width)
        .clamp(0.0, 1.0);
    final normalizedY = ((canvasPoint.dy - imageRect.top) / imageRect.height)
        .clamp(0.0, 1.0);
    return Offset(
      normalizedX * image.width.toDouble(),
      normalizedY * image.height.toDouble(),
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    final image = _image;
    if (image == null || _canvasSize.isEmpty) return;

    if (_tool == _EditorTool.move) {
      _startZoom = _zoom;
      _startPan = _pan;
      _startFocalPoint = details.localFocalPoint;
      return;
    }

    if (_tool != _EditorTool.pencil && _tool != _EditorTool.eraser) return;
    if (details.pointerCount != 1) return;
    _startStrokeAt(details.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final image = _image;
    if (image == null || _canvasSize.isEmpty) return;

    if (_tool == _EditorTool.move) {
      final nextZoom = (_startZoom * details.scale).clamp(_minZoom, _maxZoom);
      final delta = details.localFocalPoint - _startFocalPoint;
      final nextPan = _clampPan(
        canvasSize: _canvasSize,
        image: image,
        zoom: nextZoom,
        candidate: _startPan + delta,
      );
      setState(() {
        _zoom = nextZoom;
        _pan = nextPan;
      });
      return;
    }

    if (_tool != _EditorTool.pencil && _tool != _EditorTool.eraser) return;
    if (details.pointerCount != 1) {
      _endStroke();
      return;
    }
    _appendStrokeAt(details.localFocalPoint);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_tool == _EditorTool.pencil || _tool == _EditorTool.eraser) {
      _endStroke();
    }
  }

  void _startStrokeAt(Offset localPosition) {
    final image = _image;
    if (image == null || _canvasSize.isEmpty) return;
    if (_tool != _EditorTool.pencil && _tool != _EditorTool.eraser) return;

    final rect = _imageRectForCanvas(_canvasSize, image, _zoom, _pan);
    if (!rect.contains(localPosition)) return;

    final point = _canvasToImagePoint(
      canvasPoint: localPosition,
      imageRect: rect,
      image: image,
    );
    final imagePixelsPerCanvasPixel = image.width / rect.width;

    setState(() {
      _isDrawing = true;
      _activeStrokePoints = [point];
      _activeStrokeWidthImageSpace = _strokeWidth * imagePixelsPerCanvasPixel;
      _redoStack = [];
    });
  }

  void _appendStrokeAt(Offset localPosition) {
    final image = _image;
    if (image == null || !_isDrawing || _activeStrokePoints.isEmpty) return;

    final rect = _imageRectForCanvas(_canvasSize, image, _zoom, _pan);
    final point = _canvasToImagePoint(
      canvasPoint: localPosition,
      imageRect: rect,
      image: image,
    );

    setState(() {
      _activeStrokePoints = [..._activeStrokePoints, point];
    });
  }

  void _endStroke() {
    if (!_isDrawing || _activeStrokePoints.isEmpty) return;
    final points = List<Offset>.from(_activeStrokePoints);
    if (points.length == 1) {
      points.add(points.first);
    }

    final stroke = _Stroke(
      points: points,
      color: _activeColor,
      widthImageSpace: _activeStrokeWidthImageSpace,
      isEraser: _tool == _EditorTool.eraser,
    );

    setState(() {
      _strokes = [..._strokes, stroke];
      _activeStrokePoints = const [];
      _isDrawing = false;
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      final last = _strokes.last;
      _strokes = _strokes.sublist(0, _strokes.length - 1);
      _redoStack = [..._redoStack, last];
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      final stroke = _redoStack.last;
      _redoStack = _redoStack.sublist(0, _redoStack.length - 1);
      _strokes = [..._strokes, stroke];
    });
  }

  Future<void> _saveAndClose() async {
    final image = _image;
    if (image == null || _canvasSize.isEmpty || _isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final savedPath = await _renderToFile(image: image);
      if (!mounted) return;
      Navigator.of(context).pop(savedPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save edit: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<String> _renderToFile({required ui.Image image}) async {
    final previewRect = _imageRectForCanvas(_canvasSize, image, _zoom, _pan);
    final scale = _outputSize / _canvasSize.width;
    final outputRect = Rect.fromLTWH(
      previewRect.left * scale,
      previewRect.top * scale,
      previewRect.width * scale,
      previewRect.height * scale,
    );
    final center = Offset(_outputSize / 2, _outputSize / 2);
    final radius = (_canvasSize.width / 2) * _circleScale * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, _outputSize, _outputSize),
    );

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );

    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      outputRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    _paintStrokes(
      canvas: canvas,
      imageRect: outputRect,
      image: image,
      strokes: _strokes,
      activePoints: const [],
      activeWidthImageSpace: _activeStrokeWidthImageSpace,
      activeColor: _activeColor,
      activeTool: _tool,
    );

    canvas.restore();

    final outImage = await recorder.endRecording().toImage(
      _outputSize.toInt(),
      _outputSize.toInt(),
    );
    final bytes = await outImage.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw Exception('Could not encode edited image');
    }

    final folder = await Directory.systemTemp.createTemp('shoq_editor_');
    final path =
        '${folder.path}${Platform.pathSeparator}edited_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(path);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: (_isSaving || image == null || _canvasSize.isEmpty)
                ? null
                : _saveAndClose,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Save'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null || image == null)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _error ?? 'Could not load image',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final side = math.min(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        _canvasSize = Size(side, side);
                        final imageRect = _imageRectForCanvas(
                          _canvasSize,
                          image,
                          _zoom,
                          _pan,
                        );
                        final radius = (side / 2) * _circleScale;

                        return Center(
                          child: SizedBox(
                            width: side,
                            height: side,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: _onScaleStart,
                              onScaleUpdate: _onScaleUpdate,
                              onScaleEnd: _onScaleEnd,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CustomPaint(
                                    painter: _PhotoCanvasPainter(
                                      image: image,
                                      imageRect: imageRect,
                                      strokes: _strokes,
                                      activePoints: _activeStrokePoints,
                                      activeWidthImageSpace:
                                          _activeStrokeWidthImageSpace,
                                      activeColor: _activeColor,
                                      activeTool: _tool,
                                    ),
                                  ),
                                  IgnorePointer(
                                    child: CustomPaint(
                                      painter: _CircleOverlayPainter(
                                        radius: radius,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _buildControls(),
                ],
              ),
            ),
    );
  }

  Widget _buildControls() {
    final canUndo = _strokes.isNotEmpty;
    final canRedo = _redoStack.isNotEmpty;

    return Container(
      color: const Color(0xFF101214),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Circle size',
            style: TextStyle(
              color: Colors.grey[300],
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          Slider(
            min: 0.45,
            max: 0.95,
            value: _circleScale,
            onChanged: (value) {
              setState(() {
                _circleScale = value;
              });
            },
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final tools = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildToolButton(
                    label: 'Move',
                    icon: Icons.open_with,
                    selected: _tool == _EditorTool.move,
                    onTap: () => setState(() => _tool = _EditorTool.move),
                  ),
                  _buildToolButton(
                    label: 'Pencil',
                    icon: Icons.edit,
                    selected: _tool == _EditorTool.pencil,
                    onTap: () => setState(() => _tool = _EditorTool.pencil),
                  ),
                  _buildToolButton(
                    label: 'Eraser',
                    icon: Icons.auto_fix_off,
                    selected: _tool == _EditorTool.eraser,
                    onTap: () => setState(() => _tool = _EditorTool.eraser),
                  ),
                ],
              );

              final historyButtons = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: canUndo ? _undo : null,
                    icon: const Icon(Icons.undo),
                    tooltip: 'Undo',
                  ),
                  IconButton(
                    onPressed: canRedo ? _redo : null,
                    icon: const Icon(Icons.redo),
                    tooltip: 'Redo',
                  ),
                ],
              );

              if (constraints.maxWidth < 430) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tools,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [historyButtons],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tools),
                  const SizedBox(width: 8),
                  historyButtons,
                ],
              );
            },
          ),
          if (_tool == _EditorTool.pencil) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _pencilPalette.map((color) {
                  final selected = color.toARGB32() == _activeColor.toARGB32();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _activeColor = color;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: selected ? 30 : 26,
                        height: selected ? 30 : 26,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.white24,
                            width: selected ? 2.4 : 1.4,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Pencil width', style: TextStyle(color: Colors.grey[300])),
                Expanded(
                  child: Slider(
                    min: 2.0,
                    max: 14.0,
                    value: _strokeWidth,
                    onChanged: (value) {
                      setState(() {
                        _strokeWidth = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.white12,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Colors.white70 : Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 17),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoCanvasPainter extends CustomPainter {
  final ui.Image image;
  final Rect imageRect;
  final List<_Stroke> strokes;
  final List<Offset> activePoints;
  final double activeWidthImageSpace;
  final Color activeColor;
  final _EditorTool activeTool;

  const _PhotoCanvasPainter({
    required this.image,
    required this.imageRect,
    required this.strokes,
    required this.activePoints,
    required this.activeWidthImageSpace,
    required this.activeColor,
    required this.activeTool,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      imageRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    _paintStrokes(
      canvas: canvas,
      imageRect: imageRect,
      image: image,
      strokes: strokes,
      activePoints: activePoints,
      activeWidthImageSpace: activeWidthImageSpace,
      activeColor: activeColor,
      activeTool: activeTool,
    );
  }

  @override
  bool shouldRepaint(covariant _PhotoCanvasPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.imageRect != imageRect ||
        oldDelegate.strokes != strokes ||
        oldDelegate.activePoints != activePoints ||
        oldDelegate.activeWidthImageSpace != activeWidthImageSpace ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeTool != activeTool;
  }
}

void _paintStrokes({
  required Canvas canvas,
  required Rect imageRect,
  required ui.Image image,
  required List<_Stroke> strokes,
  required List<Offset> activePoints,
  required double activeWidthImageSpace,
  required Color activeColor,
  required _EditorTool activeTool,
}) {
  final sourceWidth = image.width.toDouble();
  final sourceHeight = image.height.toDouble();
  if (sourceWidth <= 0 || sourceHeight <= 0) return;

  Offset toCanvas(Offset point) {
    final normalizedX = point.dx / sourceWidth;
    final normalizedY = point.dy / sourceHeight;
    return Offset(
      imageRect.left + normalizedX * imageRect.width,
      imageRect.top + normalizedY * imageRect.height,
    );
  }

  void drawStroke(_Stroke stroke) {
    if (stroke.points.length < 2) return;
    final path = Path()
      ..moveTo(
        toCanvas(stroke.points.first).dx,
        toCanvas(stroke.points.first).dy,
      );
    for (var i = 1; i < stroke.points.length; i++) {
      final point = toCanvas(stroke.points[i]);
      path.lineTo(point.dx, point.dy);
    }

    final scale = imageRect.width / sourceWidth;
    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.0, stroke.widthImageSpace * scale)
      ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

    canvas.drawPath(path, paint);
  }

  canvas.save();
  canvas.clipRect(imageRect);
  canvas.saveLayer(imageRect, Paint());
  for (final stroke in strokes) {
    drawStroke(stroke);
  }

  if (activePoints.length > 1) {
    drawStroke(
      _Stroke(
        points: activePoints,
        color: activeColor,
        widthImageSpace: activeWidthImageSpace,
        isEraser: activeTool == _EditorTool.eraser,
      ),
    );
  }

  canvas.restore();
  canvas.restore();
}

class _CircleOverlayPainter extends CustomPainter {
  final double radius;

  const _CircleOverlayPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final center = size.center(Offset.zero);

    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(
      bounds,
      Paint()..color = Colors.black.withValues(alpha: 0.52),
    );
    canvas.drawCircle(center, radius, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CircleOverlayPainter oldDelegate) {
    return oldDelegate.radius != radius;
  }
}

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double widthImageSpace;
  final bool isEraser;

  const _Stroke({
    required this.points,
    required this.color,
    required this.widthImageSpace,
    required this.isEraser,
  });
}
