import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class VideoViewerScreen extends StatefulWidget {
  final String messageId;
  final String videoUrl;
  final String? localPath;
  final String fileName;
  final int fileSize;

  const VideoViewerScreen({
    super.key,
    required this.messageId,
    required this.videoUrl,
    required this.localPath,
    required this.fileName,
    required this.fileSize,
  });

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  String? _localPath;
  String? _error;
  bool _showControls = true;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _localPath = widget.localPath;
    if (!Platform.isWindows) {
      _initializePlayer();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    final old = _controller;
    old?.removeListener(_handleControllerUpdate);

    VideoPlayerController? next;
    try {
      if (_localPath != null && File(_localPath!).existsSync()) {
        next = VideoPlayerController.file(File(_localPath!));
      } else {
        final uri = Uri.tryParse(widget.videoUrl);
        if (uri == null) {
          throw Exception('Invalid video link');
        }
        next = VideoPlayerController.networkUrl(uri);
      }

      next.addListener(_handleControllerUpdate);
      final future = next.initialize().then((_) {
        next!.setLooping(false);
      });
      setState(() {
        _controller = next;
        _initializeFuture = future;
        _error = null;
      });
      await future;
    } catch (e) {
      if (next != null) {
        next.removeListener(_handleControllerUpdate);
        await next.dispose();
      }
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initializeFuture = null;
        _error = 'Could not load video';
      });
    } finally {
      await old?.dispose();
    }
  }

  void _handleControllerUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Future<void> _downloadVideo() async {
    if (_isDownloading) return;
    if (_localPath != null && File(_localPath!).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video already downloaded')),
        );
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final uri = Uri.tryParse(widget.videoUrl);
      if (uri == null) {
        throw Exception('Invalid video link');
      }

      final target = await _resolveDownloadPath();
      final output = File(target);
      final sink = output.openWrite();
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength;
      var received = 0;
      await response.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() {
            _downloadProgress = (received / total).clamp(0, 1);
          });
        }
      }).asFuture();

      await sink.close();
      client.close();

      if (!mounted) return;
      setState(() {
        _localPath = target;
        _isDownloading = false;
      });
      if (!Platform.isWindows) {
        await _initializePlayer();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${p.basename(target)}'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openExternal(target),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Future<String> _resolveDownloadPath() async {
    final baseDir = await _resolveMediaDirectory();
    final shoqDir = Directory(p.join(baseDir.path, 'Shoq'));
    if (!shoqDir.existsSync()) {
      await shoqDir.create(recursive: true);
    }

    final safeName = _sanitizeFileName(widget.fileName);
    final basePath = p.join(shoqDir.path, safeName);
    if (!File(basePath).existsSync()) return basePath;

    final stem = p.basenameWithoutExtension(safeName);
    final ext = p.extension(safeName);
    var counter = 1;
    while (true) {
      final candidate = p.join(shoqDir.path, '$stem ($counter)$ext');
      if (!File(candidate).existsSync()) return candidate;
      counter++;
    }
  }

  Future<Directory> _resolveMediaDirectory() async {
    if (Platform.isWindows) {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home != null) {
        final videos = Directory(p.join(home, 'Videos'));
        if (videos.existsSync()) return videos;
        final pictures = Directory(p.join(home, 'Pictures'));
        if (pictures.existsSync()) return pictures;
      }
    }

    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final root = external.path.split('Android').first;
        final movies = Directory(p.join(root, 'Movies'));
        if (!movies.existsSync()) {
          await movies.create(recursive: true);
        }
        return movies;
      }
    }

    return getApplicationDocumentsDirectory();
  }

  String _sanitizeFileName(String input) {
    final fallback = 'video_${widget.messageId}.mp4';
    final name = input.trim().isEmpty ? fallback : input.trim();
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<void> _openExternal(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  String _formatDuration(Duration value) {
    final total = value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initFuture = _initializeFuture;
    final canOpen = _localPath != null && File(_localPath!).existsSync();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(canOpen ? Icons.open_in_new : Icons.download),
            onPressed: _isDownloading
                ? null
                : () {
                    if (canOpen) {
                      _openExternal(_localPath!);
                    } else {
                      _downloadVideo();
                    }
                  },
            tooltip: canOpen ? 'Open' : 'Download',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (Platform.isWindows)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off,
                      size: 54,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Video playback is unavailable on Windows preview mode.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _isDownloading ? null : _downloadVideo,
                      icon: const Icon(Icons.download),
                      label: const Text('Download video'),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Center(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white70),
              ),
            )
          else if (controller == null || initFuture == null)
            const Center(child: CircularProgressIndicator())
          else
            FutureBuilder<void>(
              future: initFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                final aspect = controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : 16 / 9;
                final duration = controller.value.duration;
                final position = controller.value.position;
                final isPlaying = controller.value.isPlaying;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _showControls = !_showControls;
                    });
                  },
                  child: Stack(
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: aspect,
                          child: VideoPlayer(controller),
                        ),
                      ),
                      if (_showControls)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black45,
                                  Colors.transparent,
                                  Colors.black45,
                                ],
                              ),
                            ),
                            child: Column(
                              children: [
                                const Spacer(),
                                IconButton(
                                  iconSize: 56,
                                  color: Colors.white,
                                  onPressed: _togglePlayback,
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_fill,
                                  ),
                                ),
                                const Spacer(),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Column(
                                    children: [
                                      VideoProgressIndicator(
                                        controller,
                                        allowScrubbing: true,
                                        colors: const VideoProgressColors(
                                          playedColor: Colors.white,
                                          bufferedColor: Colors.white54,
                                          backgroundColor: Colors.white24,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatDuration(position),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            _formatDuration(duration),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          if (_isDownloading)
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: _downloadProgress),
                  const SizedBox(height: 8),
                  Text(
                    'Downloading ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
