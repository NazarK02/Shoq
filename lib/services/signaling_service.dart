import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  static const String _defaultUrl =
      String.fromEnvironment('SIGNALING_URL', defaultValue: '');

  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  WebSocket? _socket;
  Future<void>? _connectFuture;
  String? _userId;
  String? _url;

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  Future<void> ensureConnected({required String userId, String? url}) async {
    final targetUrl = url ?? _defaultUrl;
    if (targetUrl.isEmpty) {
      print('SignalingService: SIGNALING_URL not set.');
      return;
    }
    if (isConnected && _userId == userId && _url == targetUrl) return;

    if (_connectFuture != null) {
      await _connectFuture;
      return;
    }

    _userId = userId;
    _url = targetUrl;

    _connectFuture = () async {
      try {
        await _socket?.close();
        _socket = await WebSocket.connect(targetUrl);
        _socket!.listen(
          _handleMessage,
          onDone: _handleDone,
          onError: _handleError,
          cancelOnError: true,
        );
        _sendRaw({
          'type': 'register',
          'userId': userId,
        });
      } catch (e) {
        print('SignalingService: connect failed: $e');
      }
    }();

    try {
      await _connectFuture;
    } finally {
      _connectFuture = null;
    }
  }

  Future<void> send(Map<String, dynamic> data) async {
    if (_connectFuture != null) {
      await _connectFuture;
    }
    if (!isConnected) return;
    _sendRaw(data);
  }

  void _sendRaw(Map<String, dynamic> data) {
    if (!isConnected) return;
    try {
      _socket!.add(jsonEncode(data));
    } catch (e) {
      print('SignalingService: send failed: $e');
    }
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
    _connectFuture = null;
  }

  void _handleMessage(dynamic message) {
    if (message is! String) return;
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        _controller.add(decoded);
      } else if (decoded is Map) {
        _controller.add(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
  }

  void _handleDone() {
    _socket = null;
  }

  void _handleError(Object error) {
    _socket = null;
    print('SignalingService: socket error: $error');
  }
}
