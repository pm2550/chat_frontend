import 'dart:async';

import 'package:chat_app/services/background_message_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSocket implements BackgroundSocket {
  _FakeSocket(this.uri, {this.failHandshake = false});

  final Uri uri;
  final bool failHandshake;
  final controller = StreamController<dynamic>();
  final sent = <String>[];
  bool closed = false;

  @override
  Future<void> get ready =>
      failHandshake ? Future.error(StateError('401')) : Future.value();

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }
}

void main() {
  final endpoint = Uri.parse('wss://example.test/api/ws');

  BackgroundMessageClient build({
    required List<_FakeSocket> sockets,
    List<bool> failHandshakes = const [],
    String? token = 'access-1',
    BackgroundTokenRefresh refreshResult = BackgroundTokenRefresh.refreshed,
    List<BackgroundNotification>? received,
    void Function()? onExpired,
    List<String>? refreshCalls,
  }) {
    var index = 0;
    return BackgroundMessageClient(
      endpoint: endpoint,
      readAccessToken: () async => token,
      refreshAccessToken: () async {
        refreshCalls?.add('refresh');
        return refreshResult;
      },
      onNotification: (n) => received?.add(n),
      onSessionExpired: onExpired,
      pingInterval: const Duration(milliseconds: 40),
      retryDelays: const [Duration(milliseconds: 10)],
      connector: (uri) {
        final fail = index < failHandshakes.length && failHandshakes[index];
        index++;
        final socket = _FakeSocket(uri, failHandshake: fail);
        sockets.add(socket);
        return socket;
      },
    );
  }

  test('connects as a background session and surfaces server notifications',
      () async {
    final sockets = <_FakeSocket>[];
    final received = <BackgroundNotification>[];
    final client = build(sockets: sockets, received: received);

    await client.start();
    expect(sockets.single.uri.queryParameters['mode'], 'background');
    expect(sockets.single.uri.queryParameters['token'], 'access-1');

    sockets.single.controller.add('{"type":"pong"}');
    sockets.single.controller.add(
        '{"type":"notification","title":"小王","body":"你好","data":{"type":"message","chatRoomId":42}}');
    sockets.single.controller.add(
        '{"type":"notification","title":"PM chat 来电","body":"小王 来电","data":{"type":"call","callId":"c1","chatRoomId":42}}');
    await Future<void>.delayed(Duration.zero);

    expect(received.map((n) => n.body), ['你好', '小王 来电']);
    expect(received.first.chatRoomId, 42);
    expect(received.first.isCall, isFalse);
    expect(received.last.isCall, isTrue);
    await client.stop();
  });

  test('keeps the session alive with periodic pings', () async {
    final sockets = <_FakeSocket>[];
    final client = build(sockets: sockets);

    await client.start();
    await Future<void>.delayed(const Duration(milliseconds: 130));

    expect(sockets.single.sent.where((s) => s.contains('ping')).length,
        greaterThanOrEqualTo(2));
    await client.stop();
  });

  test('reconnects after the connection drops', () async {
    final sockets = <_FakeSocket>[];
    final client = build(sockets: sockets);

    await client.start();
    await sockets.first.controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(sockets.length, 2);
    expect(client.isConnected, isTrue);
    await client.stop();
  });

  test('a rejected handshake refreshes the token and retries', () async {
    final sockets = <_FakeSocket>[];
    final refreshCalls = <String>[];
    final client = build(
      sockets: sockets,
      failHandshakes: [true],
      refreshCalls: refreshCalls,
    );

    await client.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(refreshCalls, ['refresh']);
    expect(sockets.length, 2);
    expect(client.isConnected, isTrue);
    await client.stop();
  });

  test('stops and reports expiry when the refresh token is rejected', () async {
    final sockets = <_FakeSocket>[];
    var expired = 0;
    final client = build(
      sockets: sockets,
      failHandshakes: [true, true, true],
      refreshResult: BackgroundTokenRefresh.rejected,
      onExpired: () => expired++,
    );

    await client.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(expired, 1);
    expect(sockets.length, 1);
    expect(client.isConnected, isFalse);
  });

  test('a transient refresh failure keeps retrying instead of logging out',
      () async {
    final sockets = <_FakeSocket>[];
    var expired = 0;
    final client = build(
      sockets: sockets,
      failHandshakes: [true, true],
      refreshResult: BackgroundTokenRefresh.unavailable,
      onExpired: () => expired++,
    );

    await client.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(expired, 0);
    expect(sockets.length, greaterThanOrEqualTo(3));
    await client.stop();
  });
}
