// Minimal GIPHY API client for GIF search/trending.
// Get an API key at https://developers.giphy.com/docs/api/
// Paste it into _kGiphyApiKey below.
//
// No extra packages required: uses dart:io HttpClient + dart:convert.

import 'dart:convert';
import 'dart:io';

const String _kGiphyApiKey = 'HcXSGhQMrv39qzB0p89NdUcaAvdypRaD';

class GiphyGif {
  final String id;
  final String previewUrl;
  final String fullUrl;
  final int width;
  final int height;

  const GiphyGif({
    required this.id,
    required this.previewUrl,
    required this.fullUrl,
    required this.width,
    required this.height,
  });
}

class GiphyService {
  static final GiphyService _instance = GiphyService._internal();
  factory GiphyService() => _instance;
  GiphyService._internal();

  HttpClient? _client;

  HttpClient get _http {
    _client ??= HttpClient()..connectionTimeout = const Duration(seconds: 8);
    return _client!;
  }

  Future<List<GiphyGif>> search(String query, {int limit = 24}) async {
    if (_kGiphyApiKey == 'YOUR_GIPHY_API_KEY_HERE') {
      return [];
    }

    final trimmed = query.trim();
    final encoded = Uri.encodeQueryComponent(trimmed);
    final isTrending = trimmed.isEmpty || trimmed == 'trending';
    final uri = Uri.parse(
      isTrending
          ? 'https://api.giphy.com/v1/gifs/trending'
              '?api_key=$_kGiphyApiKey'
              '&limit=$limit'
              '&rating=pg-13'
          : 'https://api.giphy.com/v1/gifs/search'
              '?api_key=$_kGiphyApiKey'
              '&q=$encoded'
              '&limit=$limit'
              '&rating=pg-13'
              '&lang=en',
    );

    try {
      final request = await _http.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        return [];
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final results = json['data'] as List<dynamic>? ?? [];

      return results.map((raw) {
        final images = (raw['images'] as Map<String, dynamic>?) ?? {};
        final preview = (images['fixed_width_small'] as Map<String, dynamic>?) ??
            (images['fixed_height_small'] as Map<String, dynamic>?) ??
            (images['fixed_width'] as Map<String, dynamic>?) ??
            (images['fixed_height'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
        final original =
            (images['original'] as Map<String, dynamic>?) ?? preview;

        final previewUrl = preview['url']?.toString() ?? '';
        final fullUrl = original['url']?.toString() ?? previewUrl;
        final width = int.tryParse(original['width']?.toString() ?? '') ??
            int.tryParse(preview['width']?.toString() ?? '') ??
            200;
        final height = int.tryParse(original['height']?.toString() ?? '') ??
            int.tryParse(preview['height']?.toString() ?? '') ??
            200;

        return GiphyGif(
          id: raw['id']?.toString() ?? '',
          previewUrl: previewUrl,
          fullUrl: fullUrl,
          width: width,
          height: height,
        );
      }).where((g) => g.fullUrl.isNotEmpty).toList();
    } catch (e) {
      debugPrintSafe('GiphyService search error: $e');
      return [];
    }
  }

  void dispose() {
    _client?.close(force: true);
    _client = null;
  }
}

void debugPrintSafe(String msg) {
  // ignore: avoid_print
  assert(() {
    print('[GiphyService] $msg');
    return true;
  }());
}
