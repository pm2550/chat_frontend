import 'dart:convert';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_screen_test.dart' show FakeChatDataService;

void main() {
  setUp(ChatScreen.clearMessageCacheForTesting);

  final messages = [
    Message(
      id: '1',
      content: '好友的消息',
      senderId: 'user2',
      senderName: '好友',
      chatRoomId: '42',
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:00:00'),
    ),
    Message(
      id: '2',
      content: '我的消息',
      senderId: 'user1',
      senderName: '我',
      chatRoomId: '42',
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:01:00'),
    ),
  ];

  Chat privateChat() => Chat(
        id: '42',
        name: '私聊',
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

  /// 首页 → 聊天页，两层路由，便于验证聊天页被关掉。
  Widget buildApp(_RecordingWebSocketService socket, {Chat? chat}) {
    final authService = _MeAuthService();
    final openedChat = chat ?? privateChat();
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: RouteSettings(arguments: openedChat),
                  builder: (_) => ChatScreen(
                    chatService: FakeChatDataService(messages: messages),
                    authService: authService,
                    webSocketService: socket,
                  ),
                ),
              ),
              child: const Text('打开聊天'),
            ),
          ),
        ),
      ),
    );
  }

  /// 推送经广播流异步送达，处理完再多渲染一帧。
  Future<void> deliver(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> openChat(WidgetTester tester) async {
    await tester.tap(find.text('打开聊天'));
    await tester.pumpAndSettle();
  }

  MessageBubble bubbleFor(WidgetTester tester, String id) {
    return tester
        .widgetList<MessageBubble>(find.byType(MessageBubble))
        .firstWhere((bubble) => bubble.message.id == id);
  }

  testWidgets('peer presence events update the header without a room id',
      (tester) async {
    final socket = _RecordingWebSocketService();
    await tester.pumpWidget(buildApp(socket));
    await openChat(tester);
    expect(find.text('在线'), findsOneWidget);

    socket.handleMessageForTest(jsonEncode({
      'type': 'status',
      'userId': 'user2',
      'onlineStatus': 'AWAY',
    }));
    await deliver(tester);
    expect(find.text('离开'), findsOneWidget);

    socket.handleMessageForTest(jsonEncode({
      'type': 'status',
      'userId': 'user2',
      'onlineStatus': 'OFFLINE',
    }));
    await deliver(tester);
    expect(find.textContaining('最后在线'), findsOneWidget);
  });

  testWidgets('read receipts from the peer mark my messages read live',
      (tester) async {
    final socket = _RecordingWebSocketService();
    await tester.pumpWidget(buildApp(socket));
    await openChat(tester);
    expect(bubbleFor(tester, '2').message.status, MessageStatus.sent);

    // 自己在另一台设备上读，不算对方已读。
    socket.handleMessageForTest(jsonEncode({
      'type': 'read_receipt',
      'chatRoomId': 42,
      'userId': 'user1',
      'lastReadMessageId': 2,
      'unreadCount': 0,
    }));
    await deliver(tester);
    expect(bubbleFor(tester, '2').message.status, MessageStatus.sent);

    socket.handleMessageForTest(jsonEncode({
      'type': 'read_receipt',
      'chatRoomId': 42,
      'userId': 'user2',
      'lastReadMessageId': 2,
    }));
    await deliver(tester);

    final mine = bubbleFor(tester, '2').message;
    expect(mine.status, MessageStatus.read);
    expect(mine.readCount, 1);
    // 对方自己的消息不会因为对方读了而变化。
    expect(bubbleFor(tester, '1').message.readCount, 0);

    // 同一批已读再推一次不会重复计数。
    socket.handleMessageForTest(jsonEncode({
      'type': 'read_receipt',
      'chatRoomId': 42,
      'userId': 'user2',
      'lastReadMessageId': 2,
    }));
    await deliver(tester);
    expect(bubbleFor(tester, '2').message.readCount, 1);
  });

  testWidgets('single-message read receipt counts only that message',
      (tester) async {
    final socket = _RecordingWebSocketService();
    await tester.pumpWidget(buildApp(socket));
    await openChat(tester);

    socket.handleMessageForTest(jsonEncode({
      'type': 'read_receipt',
      'chatRoomId': 42,
      'userId': 'user3',
      'messageId': 2,
    }));
    await deliver(tester);

    expect(bubbleFor(tester, '2').message.readCount, 1);
    expect(bubbleFor(tester, '1').message.readCount, 0);
  });

  testWidgets('typing snapshot never shows the current user', (tester) async {
    final socket = _RecordingWebSocketService();
    await tester.pumpWidget(buildApp(socket));
    await openChat(tester);

    socket.handleMessageForTest(jsonEncode({
      'type': 'typing_aggregated',
      'chatRoomId': 42,
      'userIds': ['user1'],
      'userNames': ['我'],
    }));
    await deliver(tester);
    expect(find.textContaining('正在输入'), findsNothing);

    socket.handleMessageForTest(jsonEncode({
      'type': 'typing_aggregated',
      'chatRoomId': 42,
      'userIds': ['user1', 'user2'],
      'userNames': ['我', '好友'],
    }));
    await deliver(tester);
    expect(find.text('好友 正在输入'), findsOneWidget);
    // 输入动画的错峰定时器跑完再结束。
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('composer sends typing start and stop to the server',
      (tester) async {
    final socket = _RecordingWebSocketService();
    await tester.pumpWidget(buildApp(socket));
    await openChat(tester);

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '你');
    await tester.pump();
    await tester.enterText(composer, '你好');
    await tester.pump();
    expect(socket.typingCalls, ['42:true']);

    await tester.enterText(composer, '');
    await tester.pump();
    expect(socket.typingCalls, ['42:true', '42:false']);

    await tester.enterText(composer, '再来');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(socket.typingCalls, ['42:true', '42:false', '42:true', '42:false']);
  });

  testWidgets('being kicked closes the open chat with a notice',
      (tester) async {
    final socket = _RecordingWebSocketService();
    final group = Chat(
      id: '42',
      name: '工作群',
      type: ChatType.group,
      createdAt: DateTime.parse('2024-01-01T09:00:00'),
    );
    await tester.pumpWidget(buildApp(socket, chat: group));
    await openChat(tester);
    expect(find.byType(ChatScreen), findsOneWidget);

    socket.handleMessageForTest(jsonEncode({
      'type': 'room_membership_removed',
      'chatRoomId': 42,
      'reason': 'kicked',
    }));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('你已被移出该群聊'), findsOneWidget);
    expect(find.text('打开聊天'), findsOneWidget);
  });

  testWidgets('room_updated applies a cleared background and new name',
      (tester) async {
    final socket = _RecordingWebSocketService();
    final group = Chat(
      id: '42',
      name: '旧群名',
      type: ChatType.group,
      createdAt: DateTime.parse('2024-01-01T09:00:00'),
      memberCount: 2,
    );
    await tester.pumpWidget(buildApp(socket, chat: group));
    await openChat(tester);

    socket.handleMessageForTest(jsonEncode({
      'type': 'room_updated',
      'chatRoomId': 42,
      'chatRoom': {
        'id': 42,
        'name': '新群名',
        'roomType': 'GROUP',
        'memberCount': 3,
      },
    }));
    await deliver(tester);

    expect(find.text('新群名'), findsWidgets);
    expect(find.text('3人'), findsWidgets);
  });
}

class _RecordingWebSocketService extends WebSocketService {
  _RecordingWebSocketService() : super.forTesting(authService: _MeAuthService());

  final List<String> typingCalls = [];

  @override
  void sendTyping(int chatRoomId, bool isTyping) {
    typingCalls.add('$chatRoomId:$isTyping');
  }
}

class _MeAuthService extends AuthService {
  _MeAuthService() : super.test();

  @override
  User? get currentUser => User(
        id: 'user1',
        username: 'me',
        email: 'me@test.com',
        displayName: '我',
        createdAt: DateTime.parse('2024-01-01T09:00:00'),
      );

  @override
  String? get accessToken => null;

  @override
  Future<bool> ensureAuthenticated() async => true;

  @override
  Future<bool> refreshAccessToken() async => false;
}
