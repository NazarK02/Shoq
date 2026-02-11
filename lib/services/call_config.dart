class CallConfig {
  // Provide TURN server(s) via --dart-define to keep secrets out of source:
  // --dart-define=TURN_URLS=turn:your.domain:3478?transport=udp,turn:your.domain:3478?transport=tcp
  // --dart-define=TURN_USER=yourUser
  // --dart-define=TURN_PASS=yourPass
  static const String _turnUrls =
      String.fromEnvironment('TURN_URLS', defaultValue: '');
  static const String _turnUser =
      String.fromEnvironment('TURN_USER', defaultValue: '');
  static const String _turnPass =
      String.fromEnvironment('TURN_PASS', defaultValue: '');
  static const String _localOnlyFlag =
      String.fromEnvironment('LOCAL_ONLY', defaultValue: 'false');

  static List<Map<String, dynamic>> get iceServers {
    if (_localOnlyFlag.toLowerCase() == 'true') {
      return [];
    }

    final urls = _turnUrls
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (urls.isNotEmpty) {
      return [
        {
          'urls': urls,
          'username': _turnUser,
          'credential': _turnPass,
        }
      ];
    }

    // Fallback STUN for local/dev if TURN not set.
    return [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      }
    ];
  }
}
