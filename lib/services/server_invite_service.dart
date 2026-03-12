class ServerInviteService {
  static const String _defaultInviteBase = 'https://shoq-bfa54.web.app';

  String buildInviteLink(
    String code, {
    String? serverName,
    String? serverAvatarUrl,
    String? serverDescription,
  }) {
    final normalized = _normalizeCode(code);
    if (normalized.isEmpty) return '';
    final base = _baseInviteUri();
    final queryParameters = <String, String>{'joinServer': normalized};
    final trimmedName = serverName?.trim() ?? '';
    if (trimmedName.isNotEmpty) {
      queryParameters['serverName'] = trimmedName;
    }
    final trimmedAvatar = serverAvatarUrl?.trim() ?? '';
    final parsedAvatar = Uri.tryParse(trimmedAvatar);
    if (parsedAvatar != null &&
        parsedAvatar.hasScheme &&
        (parsedAvatar.scheme == 'http' || parsedAvatar.scheme == 'https')) {
      queryParameters['serverAvatar'] = parsedAvatar.toString();
    }
    final trimmedDesc = serverDescription?.trim() ?? '';
    if (trimmedDesc.isNotEmpty) {
      final sanitized = trimmedDesc.replaceAll(RegExp(r'\\s+'), ' ');
      queryParameters['serverDesc'] =
          sanitized.length > 180 ? sanitized.substring(0, 180) : sanitized;
    }
    return base
        .replace(
          path: '/join-server',
          queryParameters: queryParameters,
        )
        .toString();
  }

  String extractInviteCode(String rawInput) {
    final raw = rawInput.trim();
    if (raw.isEmpty) return '';

    final parsed = Uri.tryParse(raw);
    if (parsed != null) {
      final codeFromUri = extractInviteCodeFromUri(
        parsed,
        allowLoosePath: true,
      );
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

  String? extractInviteCodeFromUri(Uri uri, {bool allowLoosePath = true}) {
    for (final key in const ['code', 'joinServer', 'invite', 'server']) {
      final value = uri.queryParameters[key];
      if (value != null && value.trim().isNotEmpty) {
        return _normalizeCode(value);
      }
    }

    final codeFromPath = _codeFromPathSegments(
      uri.pathSegments,
      allowLoosePath: allowLoosePath,
    );
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
          allowLoosePath: allowLoosePath,
        );
        if (fragmentPathCode != null) {
          return fragmentPathCode;
        }
      }
    }

    return null;
  }

  String? extractInitialInviteCode({bool allowLoosePath = true}) {
    final uri = Uri.base;
    final code =
        extractInviteCodeFromUri(uri, allowLoosePath: allowLoosePath);
    if (code != null && code.isNotEmpty) {
      return code;
    }
    return null;
  }

  Uri _baseInviteUri() {
    // Always generate shareable invite links on Firebase Hosting.
    // This prevents accidental links to local/GitHub docs hosts.
    return Uri.parse(_defaultInviteBase);
  }

  String? _codeFromPathSegments(
    List<String> segments, {
    bool allowLoosePath = true,
  }) {
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
    if (allowLoosePath) {
      final tail = _normalizeCode(cleaned.last);
      if (tail.length >= 6) {
        return tail;
      }
    }
    return null;
  }

  String _normalizeCode(String input) {
    return input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }
}
