import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/api_constants.dart';
import '../models/message.dart';
import 'active_call_tracker.dart';
import 'agent_client_tools.dart';
import 'auth_service.dart';

/// 服务器拒收一条消息（被禁言、不是成员、引用的消息无效……），[reason] 是服务器给的原因。
class RealtimeSendException implements Exception {
  const RealtimeSendException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

abstract class ChatRealtimeService {
  bool get isConnected;

  /// 新消息（计未读、弹提醒）。
  Stream<Message> get onMessage;

  /// 已有消息被编辑、撤回、删除或状态变化：只替换内容，不算新消息。
  Stream<Message> get onMessageUpdated;
  Stream<Map<String, dynamic>> get onTyping;
  Stream<Map<String, dynamic>> get onStatusChange;

  Future<void> connect();
  void disconnect();
  void sendMessage(Map<String, dynamic> message);
  bool sendTextMessage(
    int chatRoomId,
    String content, {
    bool isAnonymous = false,
    String? replyToId,
  });
  void sendTyping(int chatRoomId, bool isTyping);
}

/// 服务器推送的 message_action：置顶（全房间）或收藏（只发给收藏者本人的各个设备）。
class MessageActionEvent {
  const MessageActionEvent({
    required this.chatRoomId,
    required this.action,
    this.messageId,
    this.pins,
  });

  final String chatRoomId;
  final String action;
  final String? messageId;

  /// 置顶变化时服务器附带的最新置顶列表；为 null 表示需要自己重新拉取。
  final List<Message>? pins;

  bool get isPinChange => action == 'pin_added' || action == 'pin_removed';
  bool get isStarChange => action == 'star_added' || action == 'star_removed';

  static MessageActionEvent? fromJson(Map<String, dynamic> json) {
    final chatRoomId = json['chatRoomId']?.toString();
    final action = json['action']?.toString();
    if (chatRoomId == null || action == null) return null;
    final data = json['data'];
    final pinsValue = data is Map ? data['pins'] : null;
    return MessageActionEvent(
      chatRoomId: chatRoomId,
      action: action,
      messageId: data is Map ? data['messageId']?.toString() : null,
      pins: pinsValue is List
          ? pinsValue
              .whereType<Map>()
              .map((item) => Message.fromJson(
                    Map<String, dynamic>.from(item),
                    fallbackChatRoomId: chatRoomId,
                  ))
              .toList()
          : null,
    );
  }
}

class WebSocketService extends ChangeNotifier implements ChatRealtimeService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal({AuthService? authService})
      : _authService = authService ?? AuthService(),
        _channelFactory = WebSocketChannel.connect;

  @visibleForTesting
  WebSocketService.forTesting({
    required AuthService authService,
    WebSocketChannel Function(Uri uri)? channelFactory,
  })  : _authService = authService,
        _channelFactory = channelFactory ?? WebSocketChannel.connect;

  final WebSocketChannel Function(Uri uri) _channelFactory;

  WebSocketChannel? _channel;
  Future<void>? _connectFuture;
  Future<void>? _reconnectFuture;
  final AuthService _authService;
  AgentClientToolRegistry _agentClientToolRegistry = AgentClientToolRegistry();
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _connectionGeneration = 0;
  static const int _maxReconnectAttempts = 10;

  @override
  bool get isConnected => _isConnected;

  // Stream controllers for different message types
  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final StreamController<Message> _messageUpdateController =
      StreamController<Message>.broadcast();

  /// 等服务器回显的 WebSocket 发送，按 clientMessageId 对应。
  final Map<String, Completer<Message>> _pendingSends = {};
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _statusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _callController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _appUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<MessageActionEvent> _messageActionController =
      StreamController<MessageActionEvent>.broadcast();
  final Map<String, List<Message>> _pinnedMessagesByRoom = {};

  @override
  Stream<Message> get onMessage => _messageController.stream;
  @override
  Stream<Message> get onMessageUpdated => _messageUpdateController.stream;
  @override
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  @override
  Stream<Map<String, dynamic>> get onStatusChange => _statusController.stream;
  Stream<Map<String, dynamic>> get onCallSignal => _callController.stream;
  Stream<Map<String, dynamic>> get onAppUpdateAvailable =>
      _appUpdateController.stream;

  /// 置顶 / 收藏变化。置顶消息列表页可以监听 [MessageActionEvent.isPinChange]
  /// 刷新（或直接用事件里带的 pins），收藏页监听 [MessageActionEvent.isStarChange]。
  Stream<MessageActionEvent> get onMessageAction =>
      _messageActionController.stream;

  /// 本次连接期间从推送里拿到的最新置顶列表；没收到过推送时为 null，应走 REST。
  List<Message>? pinnedMessagesFor(String chatRoomId) {
    final pins = _pinnedMessagesByRoom[chatRoomId];
    return pins == null ? null : List<Message>.unmodifiable(pins);
  }

  /// Connect to WebSocket server
  @override
  Future<void> connect() {
    if (_isConnected) return Future<void>.value();
    final pending = _connectFuture;
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _connectInternal().whenComplete(() {
      if (identical(_connectFuture, operation)) {
        _connectFuture = null;
      }
    });
    _connectFuture = operation;
    return operation;
  }

  Future<void> _connectInternal() async {
    if (_isConnected) return;
    final generation = ++_connectionGeneration;

    await _authService.ensureAuthenticated();
    if (generation != _connectionGeneration) return;
    if (_authService.accessToken == null) return;

    // A mobile app may reconnect long after the cached access token expired.
    // Refresh before opening the socket so app updates/restarts do not fall
    // into a stale-token reconnect loop that looks like a forced logout.
    await _authService.refreshAccessToken();
    if (generation != _connectionGeneration) return;
    final token = _authService.accessToken;
    if (token == null) return;

    try {
      final uri = Uri.parse('${ApiConstants.wsEndpoint}?token=$token');
      final channel = _channelFactory(uri);
      // 握手完成前不能算已连接：以前这里立刻置 true，握手失败期间发出的消息
      // 返回"已发送"却直接丢了。
      await channel.ready;
      if (generation != _connectionGeneration) {
        unawaited(channel.sink.close());
        return;
      }
      _channel = channel;

      channel.stream.listen(
        (data) => _handleMessage(data),
        onDone: () {
          if (generation == _connectionGeneration) _handleDisconnect();
        },
        onError: (error) {
          if (generation == _connectionGeneration) _handleError(error);
        },
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

  _BackgroundPushHandoff? _backgroundHandoff;

  /// 手机上的网页/PWA：切到后台就主动断开，服务器立刻把用户当离线、改走系统推送；
  /// 回到前台再连上。iOS 会直接冻结后台页面，不断开的话连接会"半死"，
  /// 服务器以为你还在线，一条推送都不发。
  ///
  /// 原生 App 不走这里：它在后台靠这条连接弹本地通知；电脑端后台标签页也照常收消息。
  void enableMobileWebBackgroundHandoff() {
    if (!shouldHandOffToPushInBackground(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return;
    }
    _attachBackgroundHandoff();
  }

  /// Android App 的后台常驻服务启动后调用：前台连接在切后台时断开，
  /// 由服务里的后台连接接收通知（见 BackgroundMessageService）。
  void enableNativeBackgroundHandoff() {
    if (!shouldHandOffToPushInBackground(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      nativeBackgroundService: true,
    )) {
      return;
    }
    _attachBackgroundHandoff();
  }

  void _attachBackgroundHandoff() {
    if (_backgroundHandoff != null) return;
    final handoff = _BackgroundPushHandoff(this);
    _backgroundHandoff = handoff;
    WidgetsBinding.instance.addObserver(handoff);
    ActiveCallTracker.active.addListener(handoff.onCallActivityChanged);
  }

  @visibleForTesting
  static bool shouldHandOffToPushInBackground({
    required bool isWeb,
    required TargetPlatform platform,
    bool nativeBackgroundService = false,
  }) {
    if (isWeb) {
      return platform == TargetPlatform.iOS ||
          platform == TargetPlatform.android;
    }
    return nativeBackgroundService && platform == TargetPlatform.android;
  }

  /// Disconnect from WebSocket server
  @override
  void disconnect() {
    _connectionGeneration += 1;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _failPendingSends('连接已断开，消息可能未发送');
    notifyListeners();
  }

  /// Replaces a socket that may have gone stale while a browser/PWA was
  /// suspended. The normal reconnect budget is reset because foregrounding is
  /// an explicit signal that network access should be tried again.
  Future<void> reconnect() async {
    final pending = _reconnectFuture;
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _reconnectInternal().whenComplete(() {
      if (identical(_reconnectFuture, operation)) {
        _reconnectFuture = null;
      }
    });
    _reconnectFuture = operation;
    return operation;
  }

  Future<void> _reconnectInternal() async {
    disconnect();
    final connecting = _connectFuture;
    if (connecting != null) {
      await connecting.catchError((_) {});
    }
    _reconnectAttempts = 0;
    await connect();
  }

  /// Send a message via WebSocket
  @override
  void sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  /// 通过 WebSocket 发一条文本消息，并等服务器把存好的消息推回来（按 [clientMessageId]
  /// 对上）才算成功。服务器拒收时抛 [RealtimeSendException]（带原因），
  /// 迟迟没有回音抛 [TimeoutException]，连接断开时抛 [RealtimeSendException]。
  /// 调用前先确认 [isConnected]，没连上就改走 REST。
  Future<Message> sendTextMessageAwaitingEcho(
    int chatRoomId,
    String content, {
    required String clientMessageId,
    bool isAnonymous = false,
    String? replyToId,
    Duration timeout = const Duration(seconds: 20),
  }) {
    if (!_isConnected || _channel == null) {
      return Future.error(const RealtimeSendException('实时连接不可用'));
    }
    final completer = Completer<Message>();
    _pendingSends[clientMessageId] = completer;
    sendMessage({
      'type': 'message',
      'chatRoomId': chatRoomId,
      'content': content,
      'messageType': 'TEXT',
      'clientMessageId': clientMessageId,
      if (isAnonymous) 'isAnonymous': true,
      if (replyToId != null) 'replyToId': int.tryParse(replyToId) ?? replyToId,
    });
    return completer.future.timeout(timeout, onTimeout: () {
      _pendingSends.remove(clientMessageId);
      throw TimeoutException('发送超时', timeout);
    });
  }

  static const Uuid _uuid = Uuid();

  /// 本地"发送中"消息的临时 id，同时作为 clientMessageId 发给服务器。
  static String newClientMessageId() => 'local-${_uuid.v4()}';

  void _failPendingSends(String reason) {
    if (_pendingSends.isEmpty) return;
    final pending = Map<String, Completer<Message>>.from(_pendingSends);
    _pendingSends.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(RealtimeSendException(reason));
      }
    }
  }

  /// Send a text chat message using the backend raw WebSocket protocol.
  @override
  bool sendTextMessage(
    int chatRoomId,
    String content, {
    bool isAnonymous = false,
    String? replyToId,
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
      if (replyToId != null) 'replyToId': int.tryParse(replyToId) ?? replyToId,
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
            _handleChatMessage(json);
          }
          break;
        case 'error':
          _handleServerError(json);
          break;
        case 'typing_aggregated':
          _typingController.add(json);
          break;
        case 'typing':
          // 旧服务器会把同一份聚合快照再以 typing 发一遍，只处理 typing_aggregated。
          break;
        case 'status':
          _statusController.add(json);
          break;
        case 'read_receipt':
          _statusController.add(json);
          break;
        case 'reaction_changed':
        case 'poll_voted':
        case 'room_updated':
        case 'room_display_state_changed':
        case 'room_membership_added':
        case 'room_membership_removed':
          _statusController.add(json);
          break;
        case 'message_action':
          _handleMessageAction(Map<String, dynamic>.from(json));
          break;
        case 'call':
          _callController.add(Map<String, dynamic>.from(json));
          break;
        case 'app_update_available':
          _appUpdateController.add(Map<String, dynamic>.from(json));
          break;
        case 'agent_tool_request':
          unawaited(_handleAgentToolRequest(Map<String, dynamic>.from(json)));
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

  void _handleChatMessage(Map<String, dynamic> envelope) {
    final clientMessageId = envelope['clientMessageId']?.toString();
    var message = Message.fromJson(
      Map<String, dynamic>.from(envelope['message'] as Map),
    );
    if (clientMessageId != null && clientMessageId.isNotEmpty) {
      message = message.copyWith(clientMessageId: clientMessageId);
      final pending = _pendingSends.remove(clientMessageId);
      if (pending != null && !pending.isCompleted) pending.complete(message);
    }
    // 老服务器不带 event，一律当新消息。
    if (envelope['event'] == 'updated') {
      _messageUpdateController.add(message);
    } else {
      _messageController.add(message);
    }
  }

  void _handleServerError(Map<String, dynamic> envelope) {
    final reason = envelope['message']?.toString();
    final clientMessageId = envelope['clientMessageId']?.toString();
    final pending =
        clientMessageId == null ? null : _pendingSends.remove(clientMessageId);
    if (pending != null && !pending.isCompleted) {
      pending.completeError(RealtimeSendException(
        reason == null || reason.isEmpty ? '服务器拒绝了这条消息' : reason,
      ));
      return;
    }
    debugPrint('WebSocket server error: $reason');
  }

  void _handleMessageAction(Map<String, dynamic> json) {
    final event = MessageActionEvent.fromJson(json);
    if (event == null) return;
    final pins = event.pins;
    if (event.isPinChange) {
      if (pins != null) {
        _pinnedMessagesByRoom[event.chatRoomId] = pins;
      } else {
        _pinnedMessagesByRoom.remove(event.chatRoomId);
      }
    }
    _messageActionController.add(event);
  }

  @visibleForTesting
  void handleMessageForTest(dynamic data) => _handleMessage(data);

  @visibleForTesting
  void setAgentClientToolRegistryForTesting(AgentClientToolRegistry registry) {
    _agentClientToolRegistry = registry;
  }

  Future<void> _handleAgentToolRequest(Map<String, dynamic> message) async {
    final payload = await buildAgentToolResultForTest(message);
    if (payload != null) {
      sendMessage(payload);
    }
  }

  @visibleForTesting
  Future<Map<String, dynamic>?> buildAgentToolResultForTest(
    Map<String, dynamic> message,
  ) async {
    final callId = message['callId']?.toString();
    final toolName = message['toolName']?.toString();
    final paramsValue = message['params'];
    if (callId == null ||
        callId.isEmpty ||
        toolName == null ||
        toolName.isEmpty) {
      debugPrint('Invalid agent_tool_request: missing callId/toolName');
      return null;
    }
    final params = paramsValue is Map
        ? Map<String, dynamic>.from(paramsValue)
        : <String, dynamic>{};
    debugPrint(
        'Agent client tool request received tool=$toolName callId=$callId');
    final tool = _agentClientToolRegistry.getByName(toolName);
    if (tool == null) {
      return {
        'type': 'agent_tool_result',
        'callId': callId,
        'error': {
          'code': 'tool_not_registered',
          'message': 'Client tool is not registered: $toolName',
        },
      };
    }
    try {
      final result = await tool.execute(params);
      final payload = {
        'type': 'agent_tool_result',
        'callId': callId,
        'result': result,
      };
      debugPrint('Agent client tool result sent tool=$toolName callId=$callId');
      return payload;
    } catch (e) {
      return {
        'type': 'agent_tool_result',
        'callId': callId,
        'error': {
          'code': 'client_tool_error',
          'message': e.toString(),
        },
      };
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _failPendingSends('连接已断开，消息可能未发送');
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
    _messageUpdateController.close();
    _typingController.close();
    _statusController.close();
    _callController.close();
    _appUpdateController.close();
    _messageActionController.close();
    super.dispose();
  }
}

class _BackgroundPushHandoff with WidgetsBindingObserver {
  _BackgroundPushHandoff(this._service);

  final WebSocketService _service;
  bool _disconnectedForBackground = false;
  bool _inBackground = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // inactive 只是失去焦点（拉下通知栏、弹出键盘），不算切后台。
        _inBackground = true;
        _handOffIfIdle();
      case AppLifecycleState.resumed:
        _inBackground = false;
        if (_disconnectedForBackground) {
          _disconnectedForBackground = false;
          unawaited(_service.reconnect());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// 通话中切到后台不断开（否则收不到对方挂断、发不出自己的挂断）；
  /// 通话在后台结束后再补一次交接。
  void onCallActivityChanged() {
    if (_inBackground) _handOffIfIdle();
  }

  void _handOffIfIdle() {
    if (ActiveCallTracker.active.value) return;
    if (_service.isConnected) {
      _disconnectedForBackground = true;
      _service.disconnect();
    }
  }
}
