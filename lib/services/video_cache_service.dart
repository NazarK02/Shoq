import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Persistent disk cache for decrypted/downloaded video files.
/// Keyed by messageId so re-entering a chat is instant.
class VideoCacheService {
  static final VideoCacheService _instance = VideoCacheService._();
  factory VideoCacheService() => _instance;
  VideoCacheService._();

  Directory? _cacheDir;

  Future<Directory> _getDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'msg_video_cache'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  /// Returns cached file path if it exists on disk, null otherwise.
  Future<String?> getCached(String messageId) async {
    final dir = await _getDir();
    final file = File(p.join(dir.path, '$messageId.mp4'));
    return file.existsSync() ? file.path : null;
  }

  /// Returns the path where a video for this message should be stored.
  Future<String> reservePath(String messageId) async {
    final dir = await _getDir();
    return p.join(dir.path, '$messageId.mp4');
  }

  /// Evict videos older than [maxAge] to avoid unbounded growth.
  Future<void> evictOlderThan(Duration maxAge) async {
    final dir = await _getDir();
    final cutoff = DateTime.now().subtract(maxAge);
    await for (final entity in dir.list()) {
      if (entity is File) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    }
  }
}
