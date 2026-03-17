import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

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
    'ws://10.173.244.12:3000',
    'ws://192.168.1.189:3000',
  ];

  static const int _maxReconnectDelaySeconds = 20;
  static const bool _traceTraffic = bool.fromEnvironment(
    'TRACE_SIGNALING',
    defaultValue: false,
  );

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  WebSocket? _socket;
  Future<void>? _connectFuture;
  String? _userId;
  String? _url;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  final String _clientId =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';

  Stream<Map<String, dynamic>> get messages => _controller.stream;
  String get clientId => _clientId;
  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  void _log(String message, {bool noisy = false}) {
    if (!kDebugMode) {
      return;
    }
    if (noisy && !_traceTraffic) {
      return;
    }
    debugPrint(message);
  }

  Future<void> ensureConnected({required String userId, String? url}) async {
    final targetUrls = _resolveTargetUrls(url);

    if (targetUrls.isEmpty) {
      final error =
          'SignalingService: no signaling URL configured. Use --dart-define=SIGNALING_URL=ws://host1:3000,ws://host2:3000';
      _log('SignalingService error: $error');
      throw Exception(error);
    }

    if (isConnected &&
        _userId == userId &&
        _url != null &&
        targetUrls.contains(_url)) {
      _log('SignalingService: already connected to $_url');
      return;
    }

    if (_connectFuture != null) {
      _log('SignalingService: connection in progress, waiting...');
      await _connectFuture;
      if (isConnected &&
          _userId == userId &&
          _url != null &&
          targetUrls.contains(_url)) {
        return;
      }
    }

    _userId = userId;
    _connectFuture = _connectWithFallback(targetUrls, userId);

    try {
      await _connectFuture;
      _reconnectAttempts = 0;
      _log('SignalingService: connected successfully');
    } catch (e) {
      _log('SignalingService: connection failed: $e');
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
          _log(
            'SignalingService: failed $targetUrl, trying ${targetUrls[i + 1]}',
          );
        } else {
          _log('SignalingService: failed $targetUrl');
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
    _log('SignalingService: connecting to $targetUrl');
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

    _sendRaw({'type': 'register', 'userId': userId, 'clientId': _clientId});
    _log('SignalingService: registered as $userId ($_clientId)');
  }

  Future<void> send(Map<String, dynamic> data) async {
    if (_connectFuture != null) {
      _log('SignalingService: waiting for connection before sending...');
      await _connectFuture;
    }

    if (!isConnected) {
      _log('SignalingService: cannot send, not connected');
      throw Exception('SignalingService not connected');
    }

    _sendRaw(data);
  }

  void _sendRaw(Map<String, dynamic> data) {
    if (!isConnected) {
      _log('SignalingService: cannot send, socket not open');
      return;
    }

    try {
      final payload = jsonEncode(data);
      _socket!.add(payload);
      _log('SignalingService: sent ${data['type']}', noisy: true);
    } catch (e) {
      _log('SignalingService: send failed: $e');
    }
  }

  void disconnect() {
    _log('SignalingService: disconnecting');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.close();
    _socket = null;
    _connectFuture = null;
    _userId = null;
    _url = null;
    _reconnectAttempts = 0;
  }

  void _handleMessage(dynamic message) {
    if (message is! String) {
      _log('SignalingService: received non-string message');
      return;
    }

    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        _log('SignalingService: received ${decoded['type']}', noisy: true);
        _controller.add(decoded);
      } else if (decoded is Map) {
        _controller.add(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      _log('SignalingService: failed to parse message: $e');
    }
  }

  void _handleDone(String userId) {
    _log('SignalingService: connection closed');
    _socket = null;
    _scheduleReconnect(userId, reason: 'socket closed');
  }

  void _handleError(Object error, String userId) {
    _log('SignalingService: socket error: $error');
    _socket = null;
    _scheduleReconnect(userId, reason: 'socket error');
  }

  void _scheduleReconnect(String userId, {required String reason}) {
    if (_userId != userId) {
      return;
    }

    _reconnectAttempts++;
    final delaySeconds = (2 * _reconnectAttempts).clamp(
      2,
      _maxReconnectDelaySeconds,
    );
    final delay = Duration(seconds: delaySeconds);
    _log(
      'SignalingService: reconnecting in ${delay.inSeconds}s ($reason, attempt $_reconnectAttempts)',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        await ensureConnected(userId: userId);
      } catch (_) {
        // keep retry loop active
      }
    });
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
