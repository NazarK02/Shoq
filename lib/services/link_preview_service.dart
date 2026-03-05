import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LinkPreviewData {
  final Uri uri;
  final String title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final bool isYouTube;
  final String? youtubeVideoId;

  const LinkPreviewData({
    required this.uri,
    required this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.isYouTube = false,
    this.youtubeVideoId,
  });
}

class LinkPreviewService {
  static final LinkPreviewService _instance = LinkPreviewService._internal();
  factory LinkPreviewService() => _instance;
  LinkPreviewService._internal();

  final Map<String, Future<LinkPreviewData?>> _cache = {};

  List<String> extractLinks(String text, {int maxCount = 3}) {
    if (text.trim().isEmpty || maxCount <= 0) return const [];
    final pattern = RegExp(
      r'((?:https?:\/\/|www\.)[^\s<>()]+)',
      caseSensitive: false,
    );
    final links = <String>[];
    for (final match in pattern.allMatches(text)) {
      final raw = match.group(0)?.trim() ?? '';
      if (raw.isEmpty) continue;
      final normalized = _sanitizeMatchedUrl(raw);
      if (normalized.isEmpty || links.contains(normalized)) continue;
      links.add(normalized);
      if (links.length >= maxCount) break;
    }
    return links;
  }

  Uri? normalizeUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;
    var candidate = trimmed;
    if (!candidate.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      if (candidate.startsWith(RegExp(r'www\.', caseSensitive: false))) {
        candidate = 'https://$candidate';
      } else {
        return null;
      }
    }
    final parsed = Uri.tryParse(candidate);
    if (parsed == null || !parsed.hasAuthority) return null;
    return parsed;
  }

  Future<LinkPreviewData?> fetchPreview(String rawUrl) {
    final uri = normalizeUri(rawUrl);
    if (uri == null) return Future.value(null);
    final key = uri.toString();
    return _cache.putIfAbsent(key, () => _fetchPreviewInternal(uri));
  }

  bool isLikelyImageUrl(String rawUrl) {
    final uri = normalizeUri(rawUrl);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return path.endsWith('.gif') ||
        path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp');
  }

  bool isLikelyGifUrl(String rawUrl) {
    final uri = normalizeUri(rawUrl);
    if (uri == null) return false;
    return uri.path.toLowerCase().endsWith('.gif');
  }

  Future<LinkPreviewData?> _fetchPreviewInternal(Uri uri) async {
    final youtubeVideoId = _extractYouTubeVideoId(uri);
    final isYouTube = youtubeVideoId != null;
    final fallback = _buildFallback(uri, youtubeVideoId: youtubeVideoId);

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (compatible; ShoqLinkPreview/1.0)',
      );
      request.followRedirects = true;
      request.maxRedirects = 4;
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode >= 400) {
        return fallback;
      }

      final contentType = response.headers.contentType?.mimeType ?? '';
      if (!contentType.contains('html') && !isYouTube) {
        return fallback;
      }

      final chunks = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        chunks.addAll(chunk);
        if (chunks.length > 150000) break;
      }
      final html = utf8.decode(chunks, allowMalformed: true);
      if (html.trim().isEmpty) return fallback;

      final title =
          _extractMetaValue(html, 'og:title') ??
          _extractMetaValue(html, 'twitter:title') ??
          _extractTitleTag(html) ??
          fallback.title;
      final description =
          _extractMetaValue(html, 'og:description') ??
          _extractMetaValue(html, 'twitter:description') ??
          _extractMetaValue(html, 'description');
      final siteName =
          _extractMetaValue(html, 'og:site_name') ??
          _extractMetaValue(html, 'twitter:site');
      var imageUrl =
          _extractMetaValue(html, 'og:image') ??
          _extractMetaValue(html, 'twitter:image');
      if (imageUrl != null && imageUrl.trim().isNotEmpty) {
        final parsed = Uri.tryParse(imageUrl.trim());
        imageUrl = parsed == null
            ? null
            : (parsed.hasScheme
                  ? parsed.toString()
                  : uri.resolveUri(parsed).toString());
      }

      final resolvedImage = imageUrl ?? fallback.imageUrl;
      return LinkPreviewData(
        uri: uri,
        title: _decodeHtml(title),
        description: description == null ? null : _decodeHtml(description),
        siteName: siteName == null ? null : _decodeHtml(siteName),
        imageUrl: resolvedImage,
        isYouTube: isYouTube,
        youtubeVideoId: youtubeVideoId,
      );
    } catch (_) {
      return fallback;
    } finally {
      client.close(force: true);
    }
  }

  LinkPreviewData _buildFallback(Uri uri, {String? youtubeVideoId}) {
    final host = uri.host.trim();
    final cleanHost = host.startsWith('www.') ? host.substring(4) : host;
    final isYouTube = youtubeVideoId != null;
    final title = isYouTube ? 'YouTube video' : cleanHost;
    final imageUrl = isYouTube
        ? 'https://img.youtube.com/vi/$youtubeVideoId/hqdefault.jpg'
        : null;

    return LinkPreviewData(
      uri: uri,
      title: title.isEmpty ? uri.toString() : title,
      siteName: cleanHost.isEmpty ? null : cleanHost,
      imageUrl: imageUrl,
      isYouTube: isYouTube,
      youtubeVideoId: youtubeVideoId,
    );
  }

  String? _extractMetaValue(String html, String propertyOrName) {
    final escaped = RegExp.escape(propertyOrName);
    final patterns = [
      RegExp(
        '<meta[^>]+(?:property|name)=[\'"]$escaped[\'"][^>]*content=[\'"]([^\'"]+)[\'"][^>]*>',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=[\'"]([^\'"]+)[\'"][^>]*(?:property|name)=[\'"]$escaped[\'"][^>]*>',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _extractTitleTag(String html) {
    final match = RegExp(
      r'<title[^>]*>([^<]+)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String _sanitizeMatchedUrl(String value) {
    var result = value.trim();
    while (result.endsWith('.') ||
        result.endsWith(',') ||
        result.endsWith(';') ||
        result.endsWith('!') ||
        result.endsWith('?') ||
        result.endsWith(')')) {
      result = result.substring(0, result.length - 1).trim();
    }
    return result;
  }

  String? _extractYouTubeVideoId(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.contains('youtu.be')) {
      final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      final id = segment.trim();
      return id.isEmpty ? null : id;
    }
    if (!host.contains('youtube.com')) return null;
    final queryId = uri.queryParameters['v']?.trim() ?? '';
    if (queryId.isNotEmpty) return queryId;
    if (uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first.toLowerCase() == 'shorts' &&
        uri.pathSegments.length >= 2) {
      final id = uri.pathSegments[1].trim();
      return id.isEmpty ? null : id;
    }
    if (uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first.toLowerCase() == 'embed' &&
        uri.pathSegments.length >= 2) {
      final id = uri.pathSegments[1].trim();
      return id.isEmpty ? null : id;
    }
    return null;
  }

  String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
}
