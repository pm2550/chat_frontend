import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// 服务器下发给后台连接的一条通知（标题/正文已由服务器按免打扰、@提醒规则算好）。
class BackgroundNotification {
  const BackgroundNotification({
    required this.title,
    required this.body,
    required this.data,
  });

  final String title;
  final String body;
  final Map<String, dynamic> data;

  bool get isCall => data['type'] == 'call';
  int? get chatRoomId => int.tryParse(data['chatRoomId']?.toString() ?? '');
}

/// 续 access token 的结果。
enum BackgroundTokenRefresh { refreshed, rejected, unavailable }

/// 一条可以替换的底层连接（测试里用假的）。
abstract class BackgroundSocket {
  Future<void> get ready;
  Stream<dynamic> get stream;
  void send(String text);
  Future<void> close();
}

typedef BackgroundSocketConnector = BackgroundSocket Function(Uri uri);

class _ChannelSocket implements BackgroundSocket {
  _ChannelSocket(this._channel);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close() => _channel.sink.close();
}

BackgroundSocket _defaultConnector(Uri uri) =>
    _ChannelSocket(WebSocketChannel.connect(uri));

/// Android 后台常驻服务里跑的那条"后台连接"（?mode=background）。
///
/// 服务器不把它算作在线，只在需要推送时下发 `notification`。这里负责：
/// 保活（30 秒 ping，服务器 75 秒没收到就判断线）、断线重连（逐步退避）、
/// access token 过期时自动续；refresh token 被服务器拒绝时停下并报告登录失效。
class BackgroundMessageClient {
  BackgroundMessageClient({
    required this.endpoint,
    required this.readAccessToken,
    required this.refreshAccessToken,
    required this.onNotification,
    this.onSessionExpired,
    BackgroundSocketConnector? connector,
    this.pingInterval = const Duration(seconds: 30),
    List<Duration>? retryDelays,
  })  : _connector = connector ?? _defaultConnector,
        _retryDelays = retryDelays ??
            const [
              Duration(seconds: 2),
              Duration(seconds: 5),
              Duration(seconds: 10),
              Duration(seconds: 30),
              Duration(seconds: 60),
            ];

  final Uri endpoint;
  final Future<String?> Function() readAccessToken;
  final Future<BackgroundTokenRefresh> Function() refreshAccessToken;
  final void Function(BackgroundNotification notification) onNotification;
  final void Function()? onSessionExpired;
  final Duration pingInterval;
  final BackgroundSocketConnector _connector;
  final List<Duration> _retryDelays;

  BackgroundSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Timer? _retryTimer;
  int _failures = 0;
  bool _running = false;
  bool _connecting = false;

  bool get isConnected => _socket != null && !_connecting;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _connect();
  }

  Future<void> stop() async {
    _running = false;
    _retryTimer?.cancel();
    await _teardown();
  }

  /// 网络恢复、手机被唤醒等时机可以主动催一次重连。
  Future<void> reconnectNow() async {
    if (!_running || _connecting) return;
    _retryTimer?.cancel();
    await _teardown();
    await _connect();
  }

  Uri _uriFor(String token) {
    final query = Map<String, String>.from(endpoint.queryParameters)
      ..['token'] = token
      ..['mode'] = 'background';
    return endpoint.replace(queryParameters: query);
  }

  Future<void> _connect() async {
    if (!_running || _connecting) return;
    _connecting = true;
    try {
      var token = await readAccessToken();
      if (token == null || token.isEmpty) {
        final refreshed = await refreshAccessToken();
        if (refreshed == BackgroundTokenRefresh.rejected) {
          _expire();
          return;
        }
        token = await readAccessToken();
      }
      if (token == null || token.isEmpty) {
        _scheduleRetry();
        return;
      }

      final socket = _connector(_uriFor(token));
      try {
        await socket.ready;
      } catch (_) {
        _closeQuietly(socket);
        // 握手失败最常见是 access token 过期（服务器直接拒绝握手）；先续一次再重试。
        final refreshed = await refreshAccessToken();
        if (refreshed == BackgroundTokenRefresh.rejected) {
          _expire();
          return;
        }
        _scheduleRetry();
        return;
      }
      if (!_running) {
        _closeQuietly(socket);
        return;
      }

      _socket = socket;
      _failures = 0;
      _subscription = socket.stream.listen(
        _handleMessage,
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
        cancelOnError: true,
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(pingInterval, (_) {
        _socket?.send('{"type":"ping"}');
      });
    } finally {
      _connecting = false;
    }
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map || decoded['type'] != 'notification') return;
    final data = decoded['data'];
    onNotification(BackgroundNotification(
      title: decoded['title']?.toString() ?? 'PM chat',
      body: decoded['body']?.toString() ?? '你有一条新消息',
      data: data is Map ? Map<String, dynamic>.from(data) : const {},
    ));
  }

  void _handleDisconnect() {
    unawaited(_teardown());
    if (_running) _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running) return;
    _retryTimer?.cancel();
    final delay = _retryDelays[_failures.clamp(0, _retryDelays.length - 1)];
    _failures++;
    _retryTimer = Timer(delay, () => unawaited(_connect()));
  }

  void _expire() {
    _running = false;
    unawaited(_teardown());
    onSessionExpired?.call();
  }

  Future<void> _teardown() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) _closeQuietly(socket);
  }

  /// 关闭不阻塞主流程：半开的连接或从没握手成功的连接，close 可能迟迟不返回。
  void _closeQuietly(BackgroundSocket socket) {
    unawaited(socket
        .close()
        .timeout(const Duration(seconds: 2))
        .catchError((_) {}));
  }
}
