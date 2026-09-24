import 'dart:async';
import 'dart:convert';

import 'package:chat_app/models/user.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 内存里的 WebSocket：记录客户端发出的帧，测试可以随时推入服务器帧。
class FakeWebSocketChannel implements WebSocketChannel {
  FakeWebSocketChannel({Future<void>? ready})
      : ready = ready ?? Future<void>.value();

  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  late final FakeWebSocketSink _sink = FakeWebSocketSink();

  @override
  final Future<void> ready;

  /// 客户端发出的帧（已解析的 JSON）。
  List<Map<String, dynamic>> get sent => _sink.sent;

  /// 模拟服务器推送一帧。
  void serverSends(Map<String, dynamic> frame) =>
      _incoming.add(jsonEncode(frame));

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWebSocketSink implements WebSocketSink {
  final List<Map<String, dynamic>> sent = [];
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) {
    sent.add(Map<String, dynamic>.from(jsonDecode(data.toString()) as Map));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final item in stream) {
      add(item);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

/// 有有效 token、能真正建立连接的登录状态。
class SocketAuthService extends AuthService {
  SocketAuthService({this.userId = 'user1'}) : super.test();

  final String userId;

  @override
  User? get currentUser => User(
        id: userId,
        username: 'me',
        email: 'me@test.com',
        displayName: '我',
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      );

  @override
  String? get accessToken => 'test-access-token';

  @override
  Future<bool> ensureAuthenticated() async => true;

  @override
  Future<bool> refreshAccessToken() async => true;
}
