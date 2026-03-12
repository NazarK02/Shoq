// Minimal Tenor API v2 client for GIF search.
// Get a free API key at https://developers.google.com/tenor/guides/quickstart
// Then set TENOR_API_KEY below (or pass it via a config file / env).
//
// No extra packages required: uses dart:io HttpClient + dart:convert.

import 'dart:convert';
import 'dart:io';

// Replace with your actual Tenor v2 API key.
const String _kTenorApiKey = 'YOUR_TENOR_API_KEY_HERE';

class TenorGif {
  final String id;
  final String previewUrl; // tinygif - small, fast to load
  final String fullUrl; // gif - full size for sending
  final int width;
  final int height;

  const TenorGif({
    required this.id,
    required this.previewUrl,
    required this.fullUrl,
    required this.width,
    required this.height,
  });
}

class TenorService {
  static final TenorService _instance = TenorService._internal();
  factory TenorService() => _instance;
  TenorService._internal();

  HttpClient? _client;

  HttpClient get _http {
    _client ??= HttpClient()..connectionTimeout = const Duration(seconds: 8);
    return _client!;
  }

  Future<List<TenorGif>> search(String query, {int limit = 20}) async {
    if (_kTenorApiKey == 'YOUR_TENOR_API_KEY_HERE') {
      // Key not configured - return empty list silently.
      return [];
    }

    final encoded = Uri.encodeQueryComponent(query.trim());
    final uri = Uri.parse(
      'https://tenor.googleapis.com/v2/search'
      '?q=$encoded'
      '&key=$_kTenorApiKey'
      '&limit=$limit'
      '&media_filter=tinygif,gif'
      '&contentfilter=medium',
    );

    try {
      final request = await _http.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        return [];
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>? ?? [];

      return results.map((raw) {
        final formats = (raw['media_formats'] as Map<String, dynamic>?) ?? {};
        final gif = (formats['gif'] as Map<String, dynamic>?) ?? {};
        final tinygif = (formats['tinygif'] as Map<String, dynamic>?) ?? {};
        final dims = (gif['dims'] as List<dynamic>?) ?? [200, 200];

        return TenorGif(
          id: raw['id']?.toString() ?? '',
          previewUrl: tinygif['url']?.toString() ?? gif['url']?.toString() ?? '',
          fullUrl: gif['url']?.toString() ?? '',
          width: (dims.isNotEmpty ? dims[0] as int? : null) ?? 200,
          height: (dims.length > 1 ? dims[1] as int? : null) ?? 200,
        );
      }).where((g) => g.fullUrl.isNotEmpty).toList();
    } catch (e) {
      debugPrintSafe('TenorService search error: $e');
      return [];
    }
  }

  void dispose() {
    _client?.close(force: true);
    _client = null;
  }
}

// Avoids importing flutter/material just for debugPrint.
void debugPrintSafe(String msg) {
  // ignore: avoid_print
  assert(() {
    print('[TenorService] $msg');
    return true;
  }());
}
