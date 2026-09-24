import 'dart:async';
import 'dart:convert';

import 'package:chat_app/models/message.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_web_socket_channel.dart';

Map<String, dynamic> _messageJson(String id, {String content = 'hi'}) => {
      'id': id,
      'content': content,
      'senderId': 'user2',
      'senderName': '好友',
      'chatRoomId': '1',
      'messageType': 'TEXT',
      'messageStatus': 'SENT',
      'createdAt': '2024-01-01T10:00:00',
    };

void main() {
  group('incoming message events', () {
    test('updates go to onMessageUpdated, new messages to onMessage', () async {
      final service = WebSocketService.forTesting(authService: SocketAuthService());
      final created = <Message>[];
      final updated = <Message>[];
      service.onMessage.listen(created.add);
      service.onMessageUpdated.listen(updated.add);

      service.handleMessageForTest(jsonEncode({
        'type': 'message',
        'event': 'updated',
        'message': _messageJson('7', content: '改过'),
      }));
      service.handleMessageForTest(jsonEncode({
        'type': 'message',
        'event': 'created',
        'message': _messageJson('8'),
      }));
      // 老服务器没有 event 字段：按新消息处理。
      service.handleMessageForTest(jsonEncode({
        'type': 'message',
        'message': _messageJson('9'),
      }));
      await Future<void>.delayed(Duration.zero);

      expect(updated.map((m) => m.id), ['7']);
      expect(created.map((m) => m.id), ['8', '9']);
    });
  });

  group('sending over the socket', () {
    late FakeWebSocketChannel channel;
    late WebSocketService service;

    setUp(() async {
      channel = FakeWebSocketChannel();
      service = WebSocketService.forTesting(
        authService: SocketAuthService(),
        channelFactory: (_) => channel,
      );
      await service.connect();
    });

    tearDown(() => service.disconnect());

    test('completes with the echoed message matched by clientMessageId',
        () async {
      final future = service.sendTextMessageAwaitingEcho(
        1,
        '回复你',
        clientMessageId: 'local-1',
        replyToId: '42',
      );
      expect(channel.sent.single, {
        'type': 'message',
        'chatRoomId': 1,
        'content': '回复你',
        'messageType': 'TEXT',
        'clientMessageId': 'local-1',
        'replyToId': 42,
      });

      channel.serverSends({
        'type': 'message',
        'event': 'created',
        'clientMessageId': 'local-1',
        'message': {
          ..._messageJson('100', content: '回复你'),
          'replyToMessageId': 42,
          'replyToMessage': _messageJson('42', content: '原话'),
        },
      });

      final sent = await future;
      expect(sent.id, '100');
      expect(sent.clientMessageId, 'local-1');
      expect(sent.replyToMessage?.content, '原话');
    });

    test('server rejection fails the send with the server reason', () async {
      final future = service.sendTextMessageAwaitingEcho(
        1,
        '被禁言了',
        clientMessageId: 'local-2',
      );
      channel.serverSends({
        'type': 'error',
        'message': '您在该聊天室中被禁言',
        'clientMessageId': 'local-2',
      });

      await expectLater(
        future,
        throwsA(isA<RealtimeSendException>()
            .having((e) => e.reason, 'reason', '您在该聊天室中被禁言')),
      );
    });

    test('no echo within the timeout fails the send', () async {
      final future = service.sendTextMessageAwaitingEcho(
        1,
        '石沉大海',
        clientMessageId: 'local-3',
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(future, throwsA(isA<TimeoutException>()));
    });

    test('disconnecting fails pending sends instead of leaving them hanging',
        () async {
      final future = service.sendTextMessageAwaitingEcho(
        1,
        '断线',
        clientMessageId: 'local-4',
      );
      service.disconnect();
      await expectLater(future, throwsA(isA<RealtimeSendException>()));
    });
  });

  test('is not connected until the handshake completes', () async {
    final handshake = Completer<void>();
    final channel = FakeWebSocketChannel(ready: handshake.future);
    final service = WebSocketService.forTesting(
      authService: SocketAuthService(),
      channelFactory: (_) => channel,
    );

    final connecting = service.connect();
    await Future<void>.delayed(Duration.zero);
    expect(service.isConnected, isFalse);
    expect(service.sendTextMessage(1, '握手中'), isFalse,
        reason: '握手没完成时发送必须报失败，不能假装发出去了');

    handshake.completeError(Exception('handshake failed'));
    await connecting;
    expect(service.isConnected, isFalse);
    service.disconnect();
  });

  test('logging out closes the socket so the server stops counting us online',
      () async {
    final auth = _LogoutAuthService();
    final service = WebSocketService.forTesting(
      authService: auth,
      channelFactory: (_) => FakeWebSocketChannel(),
    );
    await service.connect();
    expect(service.isConnected, isTrue);

    // 续期换 token 不算退出。
    auth.setToken('renewed-token');
    expect(service.isConnected, isTrue);

    auth.setToken(null);
    expect(service.isConnected, isFalse);
    service.dispose();
  });
}

class _LogoutAuthService extends SocketAuthService {
  String? _token = 'test-access-token';

  @override
  String? get accessToken => _token;

  void setToken(String? token) {
    _token = token;
    notifyListeners();
  }
}
