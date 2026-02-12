import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  // Fallback to localhost for development
  static const String _defaultUrl =
      String.fromEnvironment('SIGNALING_URL', defaultValue: 'ws://localhost:3000');

  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  WebSocket? _socket;
  Future<void>? _connectFuture;
  String? _userId;
  String? _url;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  Timer? _reconnectTimer;

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  Future<void> ensureConnected({required String userId, String? url}) async {
    final targetUrl = url ?? _defaultUrl;
    
    if (targetUrl.isEmpty) {
      final error = 'SignalingService: SIGNALING_URL not configured. Please set it in your environment or use --dart-define=SIGNALING_URL=ws://your-server:3000';
      print('❌ $error');
      throw Exception(error);
    }

    if (isConnected && _userId == userId && _url == targetUrl) {
      print('✅ SignalingService: Already connected');
      return;
    }

    if (_connectFuture != null) {
      print('⏳ SignalingService: Connection in progress, waiting...');
      await _connectFuture;
      return;
    }

    _userId = userId;
    _url = targetUrl;

    _connectFuture = _connect(targetUrl, userId);

    try {
      await _connectFuture;
      _reconnectAttempts = 0; // Reset on successful connection
      print('✅ SignalingService: Connected successfully');
    } catch (e) {
      print('❌ SignalingService: Connection failed: $e');
      rethrow;
    } finally {
      _connectFuture = null;
    }
  }

  Future<void> _connect(String targetUrl, String userId) async {
    try {
      await _socket?.close();
      _socket = null;
      
      print('🔌 SignalingService: Connecting to $targetUrl...');
      _socket = await WebSocket.connect(targetUrl).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('WebSocket connection timed out');
        },
      );

      _socket!.listen(
        _handleMessage,
        onDone: () => _handleDone(userId),
        onError: (e) => _handleError(e, userId),
        cancelOnError: false,
      );

      // Register user
      _sendRaw({
        'type': 'register',
        'userId': userId,
      });
      
      print('📝 SignalingService: Registered as $userId');
    } catch (e) {
      print('❌ SignalingService: Connect failed: $e');
      _socket = null;
      
      // Auto-reconnect logic
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _reconnectAttempts++;
        final delay = Duration(seconds: 2 * _reconnectAttempts);
        print('🔄 SignalingService: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)');
        
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(delay, () {
          ensureConnected(userId: userId);
        });
      }
      
      throw e;
    }
  }

  Future<void> send(Map<String, dynamic> data) async {
    if (_connectFuture != null) {
      print('⏳ SignalingService: Waiting for connection before sending...');
      await _connectFuture;
    }
    
    if (!isConnected) {
      print('❌ SignalingService: Cannot send - not connected');
      throw Exception('SignalingService not connected');
    }
    
    _sendRaw(data);
  }

  void _sendRaw(Map<String, dynamic> data) {
    if (!isConnected) {
      print('⚠️  SignalingService: Cannot send - socket not open');
      return;
    }
    
    try {
      final json = jsonEncode(data);
      _socket!.add(json);
      print('📤 SignalingService: Sent ${data['type']}');
    } catch (e) {
      print('❌ SignalingService: Send failed: $e');
    }
  }

  void disconnect() {
    print('🔌 SignalingService: Disconnecting...');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.close();
    _socket = null;
    _connectFuture = null;
    _reconnectAttempts = 0;
  }

  void _handleMessage(dynamic message) {
    if (message is! String) {
      print('⚠️  SignalingService: Received non-string message');
      return;
    }
    
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        print('📥 SignalingService: Received ${decoded['type']}');
        _controller.add(decoded);
      } else if (decoded is Map) {
        _controller.add(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      print('❌ SignalingService: Failed to parse message: $e');
    }
  }

  void _handleDone(String userId) {
    print('🔌 SignalingService: Connection closed');
    _socket = null;
    
    // Auto-reconnect if user is still logged in
    if (_reconnectAttempts < _maxReconnectAttempts && _userId == userId) {
      _reconnectAttempts++;
      final delay = Duration(seconds: 2 * _reconnectAttempts);
      print('🔄 SignalingService: Auto-reconnecting in ${delay.inSeconds}s');
      
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () {
        ensureConnected(userId: userId);
      });
    }
  }

  void _handleError(Object error, String userId) {
    print('❌ SignalingService: Socket error: $error');
    _socket = null;
    
    // Auto-reconnect on error
    if (_reconnectAttempts < _maxReconnectAttempts && _userId == userId) {
      _reconnectAttempts++;
      final delay = Duration(seconds: 2 * _reconnectAttempts);
      print('🔄 SignalingService: Reconnecting after error in ${delay.inSeconds}s');
      
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () {
        ensureConnected(userId: userId);
      });
    }
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}