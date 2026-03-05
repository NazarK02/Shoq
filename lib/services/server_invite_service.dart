class ServerInviteService {
  static const String _defaultInviteBase = 'https://shoq-bfa54.web.app';

  String buildInviteLink(String code) {
    final normalized = _normalizeCode(code);
    if (normalized.isEmpty) return '';
    final base = _baseInviteUri();
    return base
        .replace(
          path: '/',
          queryParameters: <String, String>{'joinServer': normalized},
        )
        .toString();
  }

  String extractInviteCode(String rawInput) {
    final raw = rawInput.trim();
    if (raw.isEmpty) return '';

    final parsed = Uri.tryParse(raw);
    if (parsed != null) {
      final codeFromUri = extractInviteCodeFromUri(parsed);
      if (codeFromUri != null && codeFromUri.isNotEmpty) {
        return codeFromUri;
      }
    }

    if (raw.contains('/')) {
      final segments = raw
          .split('/')
          .map((segment) => segment.trim())
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (segments.isNotEmpty) {
        return _normalizeCode(segments.last);
      }
    }

    return _normalizeCode(raw);
  }

  String? extractInviteCodeFromUri(Uri uri) {
    for (final key in const ['code', 'joinServer', 'invite', 'server']) {
      final value = uri.queryParameters[key];
      if (value != null && value.trim().isNotEmpty) {
        return _normalizeCode(value);
      }
    }

    final codeFromPath = _codeFromPathSegments(uri.pathSegments);
    if (codeFromPath != null) {
      return codeFromPath;
    }

    final fragment = uri.fragment.trim();
    if (fragment.isNotEmpty) {
      final parsedFragment = Uri.tryParse(
        fragment.startsWith('/') ? fragment : '/$fragment',
      );
      if (parsedFragment != null) {
        for (final key in const ['code', 'joinServer', 'invite', 'server']) {
          final value = parsedFragment.queryParameters[key];
          if (value != null && value.trim().isNotEmpty) {
            return _normalizeCode(value);
          }
        }
        final fragmentPathCode = _codeFromPathSegments(
          parsedFragment.pathSegments,
        );
        if (fragmentPathCode != null) {
          return fragmentPathCode;
        }
      }
    }

    return null;
  }

  String? extractInitialInviteCode() {
    final uri = Uri.base;
    final code = extractInviteCodeFromUri(uri);
    if (code != null && code.isNotEmpty) {
      return code;
    }
    return null;
  }

  Uri _baseInviteUri() {
    final base = Uri.base;
    final isHttp = base.scheme == 'http' || base.scheme == 'https';
    if (isHttp && base.host.isNotEmpty) {
      return Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
      );
    }
    return Uri.parse(_defaultInviteBase);
  }

  String? _codeFromPathSegments(List<String> segments) {
    if (segments.isEmpty) return null;
    final cleaned = segments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) return null;
    final markerIndices = <String>{'join-server', 'invite', 'join'};
    for (var i = 0; i < cleaned.length - 1; i++) {
      if (markerIndices.contains(cleaned[i].toLowerCase())) {
        final normalized = _normalizeCode(cleaned[i + 1]);
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }
    final tail = _normalizeCode(cleaned.last);
    if (tail.length >= 6) {
      return tail;
    }
    return null;
  }

  String _normalizeCode(String input) {
    return input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }
}
