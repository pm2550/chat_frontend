import 'dart:async';

import 'package:chat_app/constants/app_colors.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/chat_list_page.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestWidget(
    ChatDataService service, {
    FakeRealtimeService? realtimeService,
    String currentUserId = 'me',
  }) {
    return MaterialApp(
      routes: {
        '/chat': (context) => const Scaffold(body: Text('Chat Page')),
      },
      home: ChatListPage(
        chatService: service,
        realtimeService: realtimeService ?? FakeRealtimeService(),
        currentUserId: currentUserId,
      ),
    );
  }

  group('ChatListPage', () {
    testWidgets('renders real chat rooms from service', (tester) async {
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '真实群聊',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
          lastMessage: Message(
            id: 'm1',
            content: '真实最后一条',
            senderId: '2',
            senderName: 'Alice',
            chatRoomId: '1',
            timestamp: DateTime.parse('2024-01-01T10:01:00'),
          ),
          unreadCount: 2,
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.text('真实群聊'), findsOneWidget);
      expect(find.text('真实最后一条'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('renders empty state when service returns no rooms',
        (tester) async {
      final service = FakeChatListService(chats: const []);

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.text('暂无聊天记录'), findsOneWidget);
    });

    testWidgets('renders retry state when service fails', (tester) async {
      final service = FakeChatListService(error: Exception('offline'));

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.text('聊天列表加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('updates last message and unread count from realtime message',
        (tester) async {
      final realtime = FakeRealtimeService();
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '实时群聊',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
          lastMessage: Message(
            id: 'm1',
            content: '旧消息',
            senderId: 'alice',
            senderName: 'Alice',
            chatRoomId: '1',
            timestamp: DateTime.parse('2024-01-01T10:01:00'),
          ),
          unreadCount: 0,
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        realtimeService: realtime,
      ));
      await tester.pump();

      realtime.emitMessage(Message(
        id: 'm2',
        content: '实时新消息',
        senderId: 'alice',
        senderName: 'Alice',
        chatRoomId: '1',
        timestamp: DateTime.parse('2024-01-01T10:02:00'),
      ));
      await tester.pump();

      expect(find.text('实时新消息'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('实时群聊: 实时新消息'), findsOneWidget);
      expect(realtime.connectCalls, 1);
    });

    testWidgets('updates participant online status from realtime status event',
        (tester) async {
      final realtime = FakeRealtimeService();
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '私聊',
          type: ChatType.private,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
          participants: [
            User(
              id: 'alice',
              username: 'alice',
              email: 'alice@test.com',
              displayName: 'Alice',
              onlineStatus: OnlineStatus.offline,
              createdAt: DateTime.parse('2024-01-01T10:00:00'),
            ),
          ],
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        realtimeService: realtime,
      ));
      await tester.pump();

      expect(find.byWidgetPredicate((widget) {
        return widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle &&
            (widget.decoration as BoxDecoration).color == AppColors.online;
      }), findsNothing);

      realtime.emitStatus({
        'type': 'status',
        'userId': 'alice',
        'onlineStatus': 'ONLINE',
      });
      await tester.pump();

      expect(find.byWidgetPredicate((widget) {
        return widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle &&
            (widget.decoration as BoxDecoration).color == AppColors.online;
      }), findsOneWidget);
    });
  });
}

class FakeChatListService extends ChatDataService {
  FakeChatListService({
    this.chats = const [],
    this.error,
  }) : super(authenticatedRequest: _unusedRequest);

  final List<Chat> chats;
  final Object? error;

  static Future<dynamic> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Chat>> getChatRooms({
    int page = 0,
    int size = 50,
    bool includeDetails = true,
  }) async {
    final err = error;
    if (err != null) {
      throw err;
    }
    return chats;
  }
}

class FakeRealtimeService implements ChatRealtimeService {
  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _statusController =
      StreamController<Map<String, dynamic>>.broadcast();

  int connectCalls = 0;
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<Message> get onMessage => _messageController.stream;

  @override
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;

  @override
  Stream<Map<String, dynamic>> get onStatusChange => _statusController.stream;

  @override
  Future<void> connect() async {
    connectCalls += 1;
    _isConnected = true;
  }

  @override
  void disconnect() {
    _isConnected = false;
  }

  @override
  void sendMessage(Map<String, dynamic> message) {}

  @override
  bool sendTextMessage(
    int chatRoomId,
    String content, {
    bool isAnonymous = false,
  }) =>
      false;

  @override
  void sendTyping(int chatRoomId, bool isTyping) {}

  void emitMessage(Message message) {
    _messageController.add(message);
  }

  void emitStatus(Map<String, dynamic> status) {
    _statusController.add(status);
  }
}
