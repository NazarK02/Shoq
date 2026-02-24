import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  // Optional override via --dart-define=SIGNALING_URL.
  // Supports a comma-separated list (primary,secondary,...).
  static const String _configuredUrls = String.fromEnvironment(
    'SIGNALING_URL',
    defaultValue: '',
  );

  // Automatic fallback order when SIGNALING_URL is not provided.
  static const List<String> _defaultFallbackUrls = [
    'ws://10.64.238.12:3000',
    'ws://192.168.1.189:3000',
  ];

  static const int _maxReconnectAttempts = 3;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  WebSocket? _socket;
  Future<void>? _connectFuture;
  String? _userId;
  String? _url;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  Stream<Map<String, dynamic>> get messages => _controller.stream;
  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  Future<void> ensureConnected({required String userId, String? url}) async {
    final targetUrls = _resolveTargetUrls(url);

    if (targetUrls.isEmpty) {
      final error =
          'SignalingService: no signaling URL configured. Use --dart-define=SIGNALING_URL=ws://host1:3000,ws://host2:3000';
      print('SignalingService error: $error');
      throw Exception(error);
    }

    if (isConnected &&
        _userId == userId &&
        _url != null &&
        targetUrls.contains(_url)) {
      print('SignalingService: already connected to $_url');
      return;
    }

    if (_connectFuture != null) {
      print('SignalingService: connection in progress, waiting...');
      await _connectFuture;
      return;
    }

    _userId = userId;
    _connectFuture = _connectWithFallback(targetUrls, userId);

    try {
      await _connectFuture;
      _reconnectAttempts = 0;
      print('SignalingService: connected successfully');
    } catch (e) {
      print('SignalingService: connection failed: $e');
      rethrow;
    } finally {
      _connectFuture = null;
    }
  }

  List<String> _resolveTargetUrls(String? url) {
    if (url != null && url.trim().isNotEmpty) {
      return _parseUrls(url);
    }

    if (_configuredUrls.trim().isNotEmpty) {
      return _parseUrls(_configuredUrls);
    }

    return List<String>.from(_defaultFallbackUrls);
  }

  List<String> _parseUrls(String raw) {
    final seen = <String>{};
    final parsed = <String>[];

    for (final part in raw.split(',')) {
      final value = part.trim();
      if (value.isEmpty) {
        continue;
      }
      if (seen.add(value)) {
        parsed.add(value);
      }
    }

    return parsed;
  }

  Future<void> _connectWithFallback(
    List<String> targetUrls,
    String userId,
  ) async {
    Object? lastError;

    await _socket?.close();
    _socket = null;

    for (var i = 0; i < targetUrls.length; i++) {
      final targetUrl = targetUrls[i];
      try {
        await _connectSingle(targetUrl, userId);
        _url = targetUrl;
        return;
      } catch (e) {
        lastError = e;
        final hasMore = i < targetUrls.length - 1;
        if (hasMore) {
          print(
            'SignalingService: failed $targetUrl, trying ${targetUrls[i + 1]}',
          );
        } else {
          print('SignalingService: failed $targetUrl');
        }
      }
    }

    _socket = null;
    _scheduleReconnect(userId, reason: 'initial connection failure');

    throw Exception(
      'SignalingService: unable to connect to any signaling server (${targetUrls.join(', ')}). Last error: $lastError',
    );
  }

  Future<void> _connectSingle(String targetUrl, String userId) async {
    print('SignalingService: connecting to $targetUrl');
    _socket = await WebSocket.connect(targetUrl).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('WebSocket connection timed out'),
    );

    _socket!.listen(
      _handleMessage,
      onDone: () => _handleDone(userId),
      onError: (Object e) => _handleError(e, userId),
      cancelOnError: false,
    );

    _sendRaw({'type': 'register', 'userId': userId});
    print('SignalingService: registered as $userId');
  }

  Future<void> send(Map<String, dynamic> data) async {
    if (_connectFuture != null) {
      print('SignalingService: waiting for connection before sending...');
      await _connectFuture;
    }

    if (!isConnected) {
      print('SignalingService: cannot send, not connected');
      throw Exception('SignalingService not connected');
    }

    _sendRaw(data);
  }

  void _sendRaw(Map<String, dynamic> data) {
    if (!isConnected) {
      print('SignalingService: cannot send, socket not open');
      return;
    }

    try {
      final payload = jsonEncode(data);
      _socket!.add(payload);
      print('SignalingService: sent ${data['type']}');
    } catch (e) {
      print('SignalingService: send failed: $e');
    }
  }

  void disconnect() {
    print('SignalingService: disconnecting');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.close();
    _socket = null;
    _connectFuture = null;
    _url = null;
    _reconnectAttempts = 0;
  }

  void _handleMessage(dynamic message) {
    if (message is! String) {
      print('SignalingService: received non-string message');
      return;
    }

    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        print('SignalingService: received ${decoded['type']}');
        _controller.add(decoded);
      } else if (decoded is Map) {
        _controller.add(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      print('SignalingService: failed to parse message: $e');
    }
  }

  void _handleDone(String userId) {
    print('SignalingService: connection closed');
    _socket = null;
    _scheduleReconnect(userId, reason: 'socket closed');
  }

  void _handleError(Object error, String userId) {
    print('SignalingService: socket error: $error');
    _socket = null;
    _scheduleReconnect(userId, reason: 'socket error');
  }

  void _scheduleReconnect(String userId, {required String reason}) {
    if (_userId != userId) {
      return;
    }
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    print(
      'SignalingService: reconnecting in ${delay.inSeconds}s ($reason, attempt $_reconnectAttempts/$_maxReconnectAttempts)',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      ensureConnected(userId: userId);
    });
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
