import 'dart:convert';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_web_socket_channel.dart';
import 'chat_screen_test.dart' show FakeChatDataService;

/// 发送/接收正确性：WebSocket 发送的回显与失败、引用、编辑推送。
void main() {
  setUp(() {
    ChatScreen.clearMessageCacheForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  final history = [
    Message(
      id: '1',
      content: '后端消息一',
      senderId: 'user2',
      senderName: '好友',
      chatRoomId: '1',
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:00:00'),
    ),
    Message(
      id: '2',
      content: '后端消息二',
      senderId: 'user1',
      senderName: '我',
      chatRoomId: '1',
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:01:00'),
    ),
  ];

  Chat room() => Chat(
        id: '1',
        name: '测试聊天',
        type: ChatType.private,
        createdAt: DateTime.parse('2024-01-01T09:00:00'),
        participants: [
          User(
            id: 'user2',
            username: 'friend',
            email: 'friend@example.com',
            displayName: '好友',
            onlineStatus: OnlineStatus.online,
            createdAt: DateTime.parse('2024-01-01T09:00:00'),
          ),
        ],
      );

  Widget build({
    required FakeChatDataService chatService,
    required WebSocketService webSocketService,
  }) {
    final chat = room();
    return MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: RouteSettings(arguments: chat),
          builder: (context) => ChatScreen(
            chatService: chatService,
            authService: SocketAuthService(),
            webSocketService: webSocketService,
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> serverMessage(
    String id,
    String content, {
    String senderId = 'user1',
    Map<String, dynamic>? extra,
  }) =>
      {
        'id': id,
        'content': content,
        'senderId': senderId,
        'senderName': senderId == 'user1' ? '我' : '好友',
        'chatRoomId': 1,
        'messageType': 'TEXT',
        'messageStatus': 'SENT',
        'createdAt': '2024-01-01T10:05:00',
        ...?extra,
      };

  Future<(FakeWebSocketChannel, WebSocketService, FakeChatDataService)>
      pumpConnectedChat(WidgetTester tester) async {
    final channel = FakeWebSocketChannel();
    final socket = WebSocketService.forTesting(
      authService: SocketAuthService(),
      channelFactory: (_) => channel,
    );
    final service = FakeChatDataService(messages: history);
    await tester.pumpWidget(build(chatService: service, webSocketService: socket));
    await tester.pumpAndSettle();
    expect(socket.isConnected, isTrue);
    return (channel, socket, service);
  }

  Future<void> finish(WidgetTester tester, WebSocketService socket) async {
    socket.disconnect();
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('quoted reply goes over the socket and the echo keeps the quote',
      (tester) async {
    final (channel, socket, service) = await pumpConnectedChat(tester);

    await tester.longPress(find.text('后端消息一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('引用'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '回复内容');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final frame = channel.sent.lastWhere((f) => f['type'] == 'message');
    expect(frame['replyToId'], 1);
    final clientMessageId = frame['clientMessageId'] as String;
    expect(clientMessageId, startsWith('local-'));
    expect(service.sentTexts, isEmpty, reason: '连接可用时回复也走 WebSocket');
    // 回显之前就能看到这条"发送中"的消息。
    expect(find.text('回复内容'), findsOneWidget);

    channel.serverSends({
      'type': 'message',
      'event': 'created',
      'clientMessageId': clientMessageId,
      'message': serverMessage('100', '回复内容', extra: {
        'replyToMessageId': 1,
        'replyToMessage': serverMessage('1', '后端消息一', senderId: 'user2'),
      }),
    });
    await tester.pumpAndSettle();

    expect(find.text('回复内容'), findsOneWidget, reason: '回显替换本地气泡，不重复');
    expect(find.text('原消息已删除'), findsNothing);
    expect(find.text('后端消息一'), findsNWidgets(2), reason: '原消息 + 引用块');
    await finish(tester, socket);
  });

  testWidgets('rejected socket send marks the message failed with the reason',
      (tester) async {
    final (channel, socket, _) = await pumpConnectedChat(tester);

    await tester.enterText(find.byType(TextField), '被拒的话');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final frame = channel.sent.lastWhere((f) => f['type'] == 'message');

    channel.serverSends({
      'type': 'error',
      'message': '您在该聊天室中被禁言',
      'clientMessageId': frame['clientMessageId'],
    });
    await tester.pumpAndSettle();

    expect(find.text('被拒的话'), findsOneWidget, reason: '消息不能凭空消失');
    expect(find.text('发送失败: 您在该聊天室中被禁言'), findsOneWidget);
    expect(find.text('重发'), findsOneWidget);

    final before = channel.sent.where((f) => f['type'] == 'message').length;
    await tester.tap(find.text('重发'));
    await tester.pump();
    final resent = channel.sent.where((f) => f['type'] == 'message').toList();
    expect(resent.length, before + 1);
    expect(resent.last['content'], '被拒的话');
    await finish(tester, socket);
  });

  testWidgets('realtime reply without the quoted body uses the local message',
      (tester) async {
    final (_, socket, _) = await pumpConnectedChat(tester);

    socket.handleMessageForTest(jsonEncode({
      'type': 'message',
      'event': 'created',
      'message': serverMessage('101', '只带了引用 id', senderId: 'user2', extra: {
        'replyToMessageId': 2,
      }),
    }));
    await tester.pumpAndSettle();

    expect(find.text('只带了引用 id'), findsOneWidget);
    expect(find.text('原消息已删除'), findsNothing);
    expect(find.text('后端消息二'), findsNWidgets(2), reason: '原消息 + 引用块');
    await finish(tester, socket);
  });

  testWidgets('an edit pushed over the socket replaces the bubble in place',
      (tester) async {
    final (_, socket, _) = await pumpConnectedChat(tester);

    socket.handleMessageForTest(jsonEncode({
      'type': 'message',
      'event': 'updated',
      'message': serverMessage('1', '后端消息一（已改）', senderId: 'user2', extra: {
        'createdAt': '2024-01-01T10:00:00',
        'editedAt': '2024-01-01T10:06:00',
      }),
    }));
    // 本页没有的旧消息被编辑：不能插进历史里。
    socket.handleMessageForTest(jsonEncode({
      'type': 'message',
      'event': 'updated',
      'message': serverMessage('0', '更早的消息', senderId: 'user2'),
    }));
    await tester.pumpAndSettle();

    expect(find.text('后端消息一'), findsNothing);
    expect(find.text('后端消息一（已改）'), findsOneWidget);
    expect(find.text('更早的消息'), findsNothing);
    await finish(tester, socket);
  });
}
