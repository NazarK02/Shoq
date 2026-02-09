import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// Service to manage file downloads with proper organization
class FileDownloadService extends ChangeNotifier {
  static final FileDownloadService _instance = FileDownloadService._internal();
  factory FileDownloadService() => _instance;
  FileDownloadService._internal();

  final Map<String, DownloadProgress> _downloads = {};
  final HttpClient _client = HttpClient();

  /// Get download progress for a specific file
  DownloadProgress? getProgress(String messageId) => _downloads[messageId];

  /// Check if file is already downloaded
  Future<String?> getLocalPath(String messageId, String fileName, String mimeType) async {
    final targetPath = await _resolveTargetPath(fileName, mimeType);
    final file = File(targetPath);
    
    if (file.existsSync()) {
      return targetPath;
    }
    return null;
  }

  /// Download a file with progress tracking
  Future<String> downloadFile({
    required String messageId,
    required String url,
    required String fileName,
    required String mimeType,
    required int fileSize,
  }) async {
    // Check if already downloading
    if (_downloads[messageId]?.status == DownloadStatus.downloading) {
      throw Exception('Download already in progress');
    }

    final targetPath = await _resolveTargetPath(fileName, mimeType);
    final file = File(targetPath);

    // If file already exists, return path
    if (file.existsSync()) {
      return targetPath;
    }

    // Create progress tracker
    _downloads[messageId] = DownloadProgress(
      status: DownloadStatus.downloading,
      progress: 0,
      totalBytes: fileSize,
      downloadedBytes: 0,
      localPath: null,
    );
    notifyListeners();

    try {
      final request = await _client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final sink = file.openWrite();
      int received = 0;

      await response.listen((chunk) {
        received += chunk.length;
        sink.add(chunk);

        _downloads[messageId] = DownloadProgress(
          status: DownloadStatus.downloading,
          progress: fileSize > 0 ? (received / fileSize).clamp(0, 1) : 0,
          totalBytes: fileSize,
          downloadedBytes: received,
          localPath: null,
        );
        notifyListeners();
      }).asFuture();

      await sink.close();

      _downloads[messageId] = DownloadProgress(
        status: DownloadStatus.completed,
        progress: 1.0,
        totalBytes: fileSize,
        downloadedBytes: received,
        localPath: targetPath,
      );
      notifyListeners();

      return targetPath;
    } catch (e) {
      _downloads[messageId] = DownloadProgress(
        status: DownloadStatus.failed,
        progress: 0,
        totalBytes: fileSize,
        downloadedBytes: 0,
        localPath: null,
        error: e.toString(),
      );
      notifyListeners();
      rethrow;
    }
  }

  /// Cancel an ongoing download
  Future<void> cancelDownload(String messageId) async {
    final download = _downloads[messageId];
    if (download?.status != DownloadStatus.downloading) return;

    _downloads.remove(messageId);
    notifyListeners();
  }

  /// Resolve the correct target path based on file type
  Future<String> _resolveTargetPath(String fileName, String mimeType) async {
    final safeName = _sanitizeFileName(fileName);
    Directory baseDir;

    if (mimeType.toLowerCase().startsWith('image/')) {
      // Images go to Pictures/Shoq
      baseDir = await _getPicturesDirectory();
    } else {
      // Other files go to Downloads/Shoq
      baseDir = await _getDownloadsDirectory();
    }

    final shoqFolder = Directory(p.join(baseDir.path, 'Shoq'));
    if (!shoqFolder.existsSync()) {
      await shoqFolder.create(recursive: true);
    }

    // Find unique filename
    return _findUniquePath(shoqFolder.path, safeName);
  }

  /// Get platform-specific Pictures directory
  Future<Directory> _getPicturesDirectory() async {
    if (Platform.isWindows) {
      // On Windows, try to get Pictures folder
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home != null) {
        final pictures = Directory(p.join(home, 'Pictures'));
        if (pictures.existsSync()) {
          return pictures;
        }
      }
    }
    
    if (Platform.isAndroid) {
      // On Android, use external storage Pictures
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final pictures = Directory(p.join(externalDir.path.split('Android')[0], 'Pictures'));
        if (!pictures.existsSync()) {
          await pictures.create(recursive: true);
        }
        return pictures;
      }
    }

    // Fallback to Documents
    return getApplicationDocumentsDirectory();
  }

  /// Get platform-specific Downloads directory
  Future<Directory> _getDownloadsDirectory() async {
    if (Platform.isWindows) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    }

    if (Platform.isAndroid) {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final downloads = Directory(p.join(externalDir.path.split('Android')[0], 'Download'));
        if (!downloads.existsSync()) {
          await downloads.create(recursive: true);
        }
        return downloads;
      }
    }

    // Fallback to Documents
    return getApplicationDocumentsDirectory();
  }

  /// Sanitize filename to be safe for filesystem
  String _sanitizeFileName(String name) {
    final trimmed = name.trim().isEmpty ? 'file' : name.trim();
    return trimmed.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  /// Find unique path by appending numbers if file exists
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

  /// Clear all completed downloads from memory
  void clearCompleted() {
    _downloads.removeWhere((key, value) => 
      value.status == DownloadStatus.completed
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _client.close(force: true);
    super.dispose();
  }
}

enum DownloadStatus {
  downloading,
  completed,
  failed,
}

class DownloadProgress {
  final DownloadStatus status;
  final double progress;
  final int totalBytes;
  final int downloadedBytes;
  final String? localPath;
  final String? error;

  DownloadProgress({
    required this.status,
    required this.progress,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.localPath,
    this.error,
  });
}
