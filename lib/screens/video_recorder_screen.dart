import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class VideoRecorderScreen extends StatefulWidget {
  const VideoRecorderScreen({super.key});

  @override
  State<VideoRecorderScreen> createState() => _VideoRecorderScreenState();
}

class _VideoRecorderScreenState extends State<VideoRecorderScreen> {
  static const ResolutionPreset _recordingResolution = ResolutionPreset.medium;
  static const int _recordingFps = 24;
  static const int _videoBitrate = 1200000;
  static const int _audioBitrate = 64000;

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _isInitializing = true;
  bool _isRecording = false;
  String? _error;
  int _cameraIndex = 0;
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _isInitializing = true;
      _error = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _error = 'No camera available on this device';
          _isInitializing = false;
        });
        return;
      }
      await _initController(_cameraIndex);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to open camera: $e';
        _isInitializing = false;
      });
    }
  }

  Future<void> _initController(int index) async {
    final previous = _controller;
    final controller = CameraController(
      _cameras[index],
      _recordingResolution,
      enableAudio: true,
      fps: _recordingFps,
      videoBitrate: _videoBitrate,
      audioBitrate: _audioBitrate,
    );

    await controller.initialize();
    await previous?.dispose();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _cameraIndex = index;
      _isInitializing = false;
      _error = null;
    });
  }

  Future<void> _switchCamera() async {
    if (_isRecording) return;
    if (_cameras.length < 2) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    try {
      await _initController(next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not switch camera: $e')));
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (_isRecording) {
      try {
        final file = await controller.stopVideoRecording();
        _timer?.cancel();
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _seconds = 0;
        });
        Navigator.pop(context, file.path);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not stop recording: $e')));
      }
      return;
    }

    try {
      await controller.prepareForVideoRecording();
      await controller.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _seconds = 0;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecording) return;
        setState(() {
          _seconds++;
        });
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start recording: $e')));
    }
  }

  String _formatSeconds(int value) {
    final minutes = (value ~/ 60).toString().padLeft(2, '0');
    final seconds = (value % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : (_error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: AspectRatio(
                            aspectRatio: controller!.value.aspectRatio,
                            child: CameraPreview(controller),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          left: 16,
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          right: 16,
                          child: IconButton(
                            icon: const Icon(
                              Icons.cameraswitch,
                              color: Colors.white,
                            ),
                            onPressed: _switchCamera,
                          ),
                        ),
                        if (_isRecording)
                          Positioned(
                            top: 20,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  'REC ${_formatSeconds(_seconds)}',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 24,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _toggleRecording,
                                child: Container(
                                  width: 78,
                                  height: 78,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    color: _isRecording
                                        ? Colors.red
                                        : Colors.white24,
                                  ),
                                  child: Icon(
                                    _isRecording
                                        ? Icons.stop
                                        : Icons.fiber_manual_record,
                                    color: Colors.white,
                                    size: _isRecording ? 34 : 40,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _isRecording
                                    ? 'Tap to stop and send'
                                    : 'Tap to start recording',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )),
      ),
    );
  }
}
