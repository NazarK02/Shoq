import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Advanced image viewer with download, share, edit capabilities
class ImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String? localPath;
  final String fileName;
  final int? fileSize;

  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    this.localPath,
    required this.fileName,
    this.fileSize,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final TransformationController _transformationController = TransformationController();
  bool _showControls = true;
  String? _currentLocalPath;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _currentLocalPath = widget.localPath;
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  Future<void> _downloadImage() async {
    if (_currentLocalPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image already downloaded')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(widget.imageUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final targetPath = await _resolveDownloadPath();
      final file = File(targetPath);
      final sink = file.openWrite();

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      await response.listen((chunk) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        if (totalBytes > 0) {
          setState(() {
            _downloadProgress = (receivedBytes / totalBytes).clamp(0, 1);
          });
        }
      }).asFuture();

      await sink.close();
      client.close();

      setState(() {
        _currentLocalPath = targetPath;
        _isDownloading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Pictures/Shoq/${p.basename(targetPath)}'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openInExternalApp(targetPath),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<String> _resolveDownloadPath() async {
    final safeName = _sanitizeFileName(widget.fileName);
    final picturesDir = await _getPicturesDirectory();
    final shoqFolder = Directory(p.join(picturesDir.path, 'Shoq'));
    
    if (!shoqFolder.existsSync()) {
      await shoqFolder.create(recursive: true);
    }

    return _findUniquePath(shoqFolder.path, safeName);
  }

  Future<Directory> _getPicturesDirectory() async {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home != null) {
        final pictures = Directory(p.join(home, 'Pictures'));
        if (pictures.existsSync()) {
          return pictures;
        }
      }
    }
    
    if (Platform.isAndroid) {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final pictures = Directory(p.join(externalDir.path.split('Android')[0], 'Pictures'));
        if (!pictures.existsSync()) {
          await pictures.create(recursive: true);
        }
        return pictures;
      }
    }

    return getApplicationDocumentsDirectory();
  }

  String _sanitizeFileName(String name) {
    final trimmed = name.trim().isEmpty ? 'image.jpg' : name.trim();
    return trimmed.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  String _findUniquePath(String directory, String fileName) {
    final basePath = p.join(directory, fileName);
    
    if (!File(basePath).existsSync()) {
      return basePath;
    }

    final name = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    
    int counter = 1;
    while (true) {
      final newPath = p.join(directory, '$name ($counter)$ext');
      if (!File(newPath).existsSync()) {
        return newPath;
      }
      counter++;
    }
  }

  Future<void> _shareImage() async {
    if (_currentLocalPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download image first to share')),
      );
      return;
    }

    // TODO: Implement share functionality with share_plus package
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share feature coming soon')),
    );
  }

  Future<void> _editImage() async {
    if (_currentLocalPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download image first to edit')),
      );
      return;
    }

    // Open with system default editor
    await _openInExternalApp(_currentLocalPath!);
  }

  Future<void> _openInExternalApp(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _copyImagePath() async {
    if (_currentLocalPath == null) return;

    await Clipboard.setData(ClipboardData(text: _currentLocalPath!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Path copied to clipboard')),
      );
    }
  }

  Future<void> _deleteLocalImage() async {
    if (_currentLocalPath == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Delete this image from your device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final file = File(_currentLocalPath!);
      if (file.existsSync()) {
        await file.delete();
        setState(() {
          _currentLocalPath = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image deleted from device')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${e.toString()}')),
        );
      }
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Image viewer with pinch-to-zoom
          GestureDetector(
            onTap: _toggleControls,
            child: Center(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 4.0,
                child: _buildImage(),
              ),
            ),
          ),

          // Top app bar
          if (_showControls)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(
                      widget.fileName,
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    iconTheme: const IconThemeData(color: Colors.white),
                    actions: [
                      if (_currentLocalPath != null)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          onSelected: (value) {
                            switch (value) {
                              case 'copy_path':
                                _copyImagePath();
                                break;
                              case 'open_external':
                                _openInExternalApp(_currentLocalPath!);
                                break;
                              case 'delete':
                                _deleteLocalImage();
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'copy_path',
                              child: Row(
                                children: [
                                  Icon(Icons.copy, size: 20),
                                  SizedBox(width: 12),
                                  Text('Copy path'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'open_external',
                              child: Row(
                                children: [
                                  Icon(Icons.open_in_new, size: 20),
                                  SizedBox(width: 12),
                                  Text('Open with...'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, size: 20, color: Colors.red),
                                  SizedBox(width: 12),
                                  Text('Delete from device', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom controls
          if (_showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isDownloading)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              children: [
                                LinearProgressIndicator(
                                  value: _downloadProgress,
                                  backgroundColor: Colors.white24,
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Downloading... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildActionButton(
                              icon: Icons.download,
                              label: _currentLocalPath != null ? 'Downloaded' : 'Download',
                              onPressed: _currentLocalPath != null || _isDownloading 
                                  ? null 
                                  : _downloadImage,
                            ),
                            _buildActionButton(
                              icon: Icons.edit,
                              label: 'Edit',
                              onPressed: _currentLocalPath != null ? _editImage : null,
                            ),
                            _buildActionButton(
                              icon: Icons.share,
                              label: 'Share',
                              onPressed: _currentLocalPath != null ? _shareImage : null,
                            ),
                            _buildActionButton(
                              icon: Icons.zoom_out_map,
                              label: 'Reset',
                              onPressed: _resetZoom,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (_currentLocalPath != null) {
      final file = File(_currentLocalPath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorWidget();
          },
        );
      }
    }

    // Load from network
    return Image.network(
      widget.imageUrl,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                : null,
            color: Colors.white,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorWidget();
      },
    );
  }

  Widget _buildErrorWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.white70),
          SizedBox(height: 16),
          Text(
            'Failed to load image',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          color: isEnabled ? Colors.white : Colors.white38,
          onPressed: onPressed,
          iconSize: 28,
        ),
        Text(
          label,
          style: TextStyle(
            color: isEnabled ? Colors.white : Colors.white38,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
