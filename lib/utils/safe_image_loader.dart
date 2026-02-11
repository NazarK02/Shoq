import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Utility class for safe image loading, especially on Windows platform.
/// 
/// Handles:
/// - Network timeouts
/// - Failed URL tracking
/// - Platform-specific optimizations
/// - Graceful error recovery
class SafeImageLoader {
  // Singleton instance
  static final SafeImageLoader _instance = SafeImageLoader._internal();
  factory SafeImageLoader() => _instance;
  SafeImageLoader._internal();

  // Track URLs that have failed to load (per session)
  final Set<String> _failedUrls = {};

  /// Clear the failed URLs cache (useful after network reconnection)
  void clearFailedUrls() {
    _failedUrls.clear();
  }

  /// Check if a URL has failed before
  bool hasFailedBefore(String url) {
    return _failedUrls.contains(url);
  }

  /// Mark a URL as failed
  void markAsFailed(String url) {
    _failedUrls.add(url);
  }

  /// Build a circular avatar with safe image loading
  /// 
  /// This is the main method to use for profile pictures.
  Widget buildAvatar({
    required String? photoUrl,
    required double radius,
    required BuildContext context,
    Color? backgroundColor,
    Color? iconColor,
    IconData icon = Icons.person,
  }) {
    final placeholder = _buildPlaceholder(
      radius: radius,
      backgroundColor: backgroundColor,
      iconColor: iconColor,
      icon: icon,
    );

    // Return placeholder if no URL
    if (photoUrl == null || photoUrl.isEmpty || photoUrl.toLowerCase() == 'null') {
      return placeholder;
    }

    // Return placeholder if this URL has failed before (Windows optimization)
    if (Platform.isWindows && _failedUrls.contains(photoUrl)) {
      return placeholder;
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (radius * 2 * dpr).round().clamp(64, 512);

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          // Windows-specific: Add connection headers
          httpHeaders: Platform.isWindows
              ? {
                  'Connection': 'keep-alive',
                  'Keep-Alive': 'timeout=5, max=1000',
                }
              : null,
          placeholder: (context, url) => placeholder,
          errorWidget: (context, url, error) {
            // Mark as failed on Windows to prevent retry loops
            if (Platform.isWindows) {
              _failedUrls.add(url);
            }
            debugPrint('⚠️ Failed to load image: $error');
            return placeholder;
          },
          fadeInDuration: const Duration(milliseconds: 200),
          fadeOutDuration: const Duration(milliseconds: 100),
          // Windows-specific: Reduced cache size
          maxHeightDiskCache: Platform.isWindows ? 512 : 1024,
          maxWidthDiskCache: Platform.isWindows ? 512 : 1024,
        ),
      ),
    );
  }

  /// Build a rectangular image with safe loading (for message previews, etc.)
  Widget buildRectangularImage({
    required String imageUrl,
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
    BorderRadius? borderRadius,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    final defaultPlaceholder = placeholder ??
        Container(
          width: width,
          height: height,
          color: Colors.grey[800],
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          ),
        );

    final defaultErrorWidget = errorWidget ??
        Container(
          width: width,
          height: height,
          color: Colors.grey[800],
          child: const Center(
            child: Icon(Icons.broken_image, size: 48, color: Colors.white54),
          ),
        );

    // Check if URL has failed before
    if (Platform.isWindows && _failedUrls.contains(imageUrl)) {
      return defaultErrorWidget;
    }

    Widget image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      httpHeaders: Platform.isWindows
          ? {
              'Connection': 'keep-alive',
              'Keep-Alive': 'timeout=5, max=1000',
            }
          : null,
      placeholder: (context, url) => defaultPlaceholder,
      errorWidget: (context, url, error) {
        if (Platform.isWindows) {
          _failedUrls.add(url);
        }
        debugPrint('⚠️ Failed to load image: $error');
        return defaultErrorWidget;
      },
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 100),
      maxHeightDiskCache: Platform.isWindows ? 512 : 1024,
      maxWidthDiskCache: Platform.isWindows ? 512 : 1024,
    );

    if (borderRadius != null) {
      image = ClipRRect(
        borderRadius: borderRadius,
        child: image,
      );
    }

    return image;
  }

  /// Build a placeholder for avatars
  Widget _buildPlaceholder({
    required double radius,
    Color? backgroundColor,
    Color? iconColor,
    IconData icon = Icons.person,
  }) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey[300],
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: radius,
        color: iconColor ?? Colors.grey[600],
      ),
    );
  }

  /// Preload an image with timeout (useful for critical images)
  Future<void> preloadImage({
    required String imageUrl,
    required BuildContext context,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (imageUrl.isEmpty || _failedUrls.contains(imageUrl)) {
      return;
    }

    try {
      await precacheImage(
        CachedNetworkImageProvider(imageUrl),
        context,
      ).timeout(timeout, onTimeout: () {
        debugPrint('⚠️ Image preload timed out: $imageUrl');
        if (Platform.isWindows) {
          _failedUrls.add(imageUrl);
        }
      });
    } catch (error) {
      debugPrint('⚠️ Image preload failed: $error');
      if (Platform.isWindows) {
        _failedUrls.add(imageUrl);
      }
    }
  }

  /// Get HTTP headers optimized for Windows
  Map<String, String> getWindowsHeaders() {
    return {
      'Connection': 'keep-alive',
      'Keep-Alive': 'timeout=5, max=1000',
      'Cache-Control': 'max-age=3600',
    };
  }
}

/// Extension on BuildContext for easy access
extension SafeImageLoaderExtension on BuildContext {
  SafeImageLoader get safeImageLoader => SafeImageLoader();
}