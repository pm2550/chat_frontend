import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/api_constants.dart';
import '../models/message.dart';
import 'auth_service.dart';

abstract class ChatRealtimeService {
  bool get isConnected;
  Stream<Message> get onMessage;
  Stream<Map<String, dynamic>> get onTyping;
  Stream<Map<String, dynamic>> get onStatusChange;

  Future<void> connect();
  void disconnect();
  void sendMessage(Map<String, dynamic> message);
  bool sendTextMessage(
    int chatRoomId,
    String content, {
    bool isAnonymous = false,
  });
  void sendTyping(int chatRoomId, bool isTyping);
}

class WebSocketService extends ChangeNotifier implements ChatRealtimeService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  final AuthService _authService = AuthService();
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;

  @override
  bool get isConnected => _isConnected;

  // Stream controllers for different message types
  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _statusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _callController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Message> get onMessage => _messageController.stream;
  @override
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  @override
  Stream<Map<String, dynamic>> get onStatusChange => _statusController.stream;
  Stream<Map<String, dynamic>> get onCallSignal => _callController.stream;

  /// Connect to WebSocket server
  @override
  Future<void> connect() async {
    if (_isConnected) return;

    final token = _authService.accessToken;
    if (token == null) return;

    try {
      final uri = Uri.parse('${ApiConstants.wsEndpoint}?token=$token');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (data) => _handleMessage(data),
        onDone: () => _handleDisconnect(),
        onError: (error) => _handleError(error),
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _startHeartbeat();
      notifyListeners();

      debugPrint('WebSocket connected');
    } catch (e) {
      debugPrint('WebSocket connection error: $e');
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket server
  @override
  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    notifyListeners();
  }

  /// Send a message via WebSocket
  @override
  void sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  /// Send a text chat message using the backend raw WebSocket protocol.
  @override
  bool sendTextMessage(
    int chatRoomId,
    String content, {
    bool isAnonymous = false,
  }) {
    if (!_isConnected || _channel == null) {
      return false;
    }
    sendMessage({
      'type': 'message',
      'chatRoomId': chatRoomId,
      'content': content,
      'messageType': 'TEXT',
      if (isAnonymous) 'isAnonymous': true,
    });
    return true;
  }

  bool sendEncryptedTextMessage(
    int chatRoomId, {
    required String encryptedContent,
    String content = '[加密消息]',
    int encryptionVersion = 1,
  }) {
    if (!_isConnected || _channel == null) {
      return false;
    }
    sendMessage({
      'type': 'message',
      'chatRoomId': chatRoomId,
      'content': content,
      'messageType': 'TEXT',
      'encryptedContent': encryptedContent,
      'encryptionVersion': encryptionVersion,
    });
    return true;
  }

  /// Send typing indicator
  @override
  void sendTyping(int chatRoomId, bool isTyping) {
    sendMessage({
      'type': 'typing',
      'chatRoomId': chatRoomId,
      'isTyping': isTyping,
    });
  }

  bool sendCallSignal(Map<String, dynamic> signal) {
    if (!_isConnected || _channel == null) {
      return false;
    }
    sendMessage({
      'type': 'call',
      ...signal,
    });
    return true;
  }

  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data.toString());
      final type = json['type'] as String?;

      switch (type) {
        case 'message':
          if (json['message'] != null) {
            _messageController.add(Message.fromJson(json['message']));
          }
          break;
        case 'typing':
          _typingController.add(json);
          break;
        case 'status':
          _statusController.add(json);
          break;
        case 'read_receipt':
          _statusController.add(json);
          break;
        case 'call':
          _callController.add(Map<String, dynamic>.from(json));
          break;
        case 'pong':
          // Heartbeat response
          break;
        default:
          debugPrint('Unknown WebSocket message type: $type');
      }
    } catch (e) {
      debugPrint('WebSocket message parse error: $e');
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    notifyListeners();
    _scheduleReconnect();
  }

  void _handleError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _handleDisconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      sendMessage({'type': 'ping'});
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('Max reconnect attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    final delay =
        Duration(seconds: (2 * (_reconnectAttempts + 1)).clamp(2, 30));
    _reconnectAttempts++;

    _reconnectTimer = Timer(delay, () {
      debugPrint('Reconnecting (attempt $_reconnectAttempts)...');
      connect();
    });
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    _typingController.close();
    _statusController.close();
    _callController.close();
    super.dispose();
  }
}
