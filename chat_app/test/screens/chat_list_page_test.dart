import 'dart:async';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/constants/app_colors.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/chat_list_page.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/desktop_notification_service.dart';
import 'package:chat_app/services/desktop_notification_stub.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestWidget(
    ChatDataService service, {
    FakeRealtimeService? realtimeService,
    DesktopNotificationService? notificationService,
    String currentUserId = 'me',
  }) {
    return MaterialApp(
      routes: {
        '/chat': (context) => const Scaffold(body: Text('Chat Page')),
      },
      home: ChatListPage(
        chatService: service,
        realtimeService: realtimeService ?? FakeRealtimeService(),
        notificationService: notificationService,
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

    testWidgets('renders group avatar image when room has avatarUrl',
        (tester) async {
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '头像群聊',
          type: ChatType.group,
          avatarUrl: '/api/files/avatar/group.png',
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.byWidgetPredicate((widget) {
        return widget is CircleAvatar &&
            widget.backgroundImage is NetworkImage &&
            (widget.backgroundImage as NetworkImage).url ==
                ApiConstants.resolveFileUrl('/api/files/avatar/group.png');
      }), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();
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

    testWidgets('syncs favicon unread badge and desktop notification state',
        (tester) async {
      final realtime = FakeRealtimeService();
      final backend = StubDesktopNotificationBackend(
        supported: true,
        permissionGranted: true,
        visible: false,
      );
      final notificationService = DesktopNotificationService(backend: backend);
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '通知群聊',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
          unreadCount: 2,
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        realtimeService: realtime,
        notificationService: notificationService,
      ));
      await tester.pump();

      expect(backend.lastUnreadCount, 2);

      realtime.emitMessage(Message(
        id: 'm2',
        content: '桌面通知消息',
        senderId: 'alice',
        senderName: 'Alice',
        chatRoomId: '1',
        timestamp: DateTime.parse('2024-01-01T10:02:00'),
      ));
      await tester.pump();

      expect(backend.lastUnreadCount, 3);
      expect(backend.shownNotifications, hasLength(1));
      expect(backend.shownNotifications.single.title, '通知群聊');
      expect(backend.shownNotifications.single.body, '桌面通知消息');
    });

    testWidgets('shows @ badge for unread latest mention', (tester) async {
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '提醒群聊',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
          lastMessage: Message(
            id: 'm1',
            content: '@Me 看这里',
            senderId: 'alice',
            senderName: 'Alice',
            chatRoomId: '1',
            timestamp: DateTime.parse('2024-01-01T10:01:00'),
            mentionedUserIds: const ['me'],
          ),
          unreadCount: 1,
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.text('@'), findsOneWidget);
    });

    testWidgets('@me filter loads mentioned messages', (tester) async {
      final service = FakeChatListService(
        chats: [
          Chat(
            id: '1',
            name: '提醒群聊',
            type: ChatType.group,
            createdAt: DateTime.parse('2024-01-01T10:00:00'),
          ),
        ],
        mentionedMessages: {
          '1': [
            Message(
              id: 'm1',
              content: '@Me 需要你看',
              senderId: 'alice',
              senderName: 'Alice',
              chatRoomId: '1',
              timestamp: DateTime.parse('2024-01-01T10:01:00'),
              mentionedUserIds: const ['me'],
            ),
          ],
        },
      );

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      await tester.tap(find.text('@我'));
      await tester.pump();
      await tester.pump();

      expect(service.loadedMentionRoomIds, ['1']);
      expect(find.text('@Me 需要你看'), findsOneWidget);
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

    testWidgets('room_updated event refreshes group avatar in list',
        (tester) async {
      final realtime = FakeRealtimeService();
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '更新群聊',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        realtimeService: realtime,
      ));
      await tester.pump();

      realtime.emitStatus({
        'type': 'room_updated',
        'chatRoomId': 1,
        'chatRoom': {
          'id': 1,
          'name': '更新群聊',
          'roomType': 'GROUP',
          'avatarUrl': '/api/files/avatar/new-group.png',
          'createdAt': '2024-01-01T10:00:00',
        },
      });
      await tester.pump();

      expect(find.byWidgetPredicate((widget) {
        return widget is CircleAvatar &&
            widget.backgroundImage is NetworkImage &&
            (widget.backgroundImage as NetworkImage).url ==
                ApiConstants.resolveFileUrl('/api/files/avatar/new-group.png');
      }), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();
    });

    testWidgets('long press menu clears chat history after confirmation',
        (tester) async {
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '清空会话',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      await tester.longPress(find.text('清空会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空聊天记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();

      expect(service.clearedRoomIds, ['1']);
      expect(find.text('清空会话'), findsOneWidget);
    });

    testWidgets('long press menu removes and blocks chats from message list',
        (tester) async {
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '移出会话',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
        ),
        Chat(
          id: '2',
          name: '屏蔽会话',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      await tester.longPress(find.text('移出会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出列表'));
      await tester.pumpAndSettle();

      expect(service.hiddenRoomIds, ['1']);
      expect(find.text('移出会话'), findsNothing);

      await tester.longPress(find.text('屏蔽会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '屏蔽'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '屏蔽'));
      await tester.pumpAndSettle();

      expect(service.blockedRoomIds, ['2']);
      expect(find.text('屏蔽会话'), findsNothing);
    });
  });
}

class FakeChatListService extends ChatDataService {
  FakeChatListService({
    this.chats = const [],
    this.mentionedMessages = const {},
    this.error,
  }) : super(authenticatedRequest: _unusedRequest);

  final List<Chat> chats;
  final Map<String, List<Message>> mentionedMessages;
  final Object? error;
  final List<String> loadedMentionRoomIds = [];
  final List<String> clearedRoomIds = [];
  final List<String> hiddenRoomIds = [];
  final List<String> blockedRoomIds = [];
  final List<String> pinnedRoomIds = [];

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
    int size = 30,
    bool includeDetails = true,
    int detailLimit = 8,
    bool includeHidden = false,
    bool includeBlocked = false,
    ChatType? type,
  }) async {
    final err = error;
    if (err != null) {
      throw err;
    }
    return chats;
  }

  @override
  Future<MessagePage> getMentionedMessages(
    String chatRoomId, {
    int page = 0,
    int size = 20,
  }) async {
    loadedMentionRoomIds.add(chatRoomId);
    final messages = mentionedMessages[chatRoomId] ?? const <Message>[];
    return MessagePage(
      messages: messages,
      currentPage: page,
      totalPages: messages.isEmpty ? 0 : 1,
      totalElements: messages.length,
      hasNext: false,
      hasPrevious: false,
    );
  }

  @override
  Future<void> clearChatHistory(String chatRoomId) async {
    clearedRoomIds.add(chatRoomId);
  }

  @override
  Future<void> hideChatRoom(String chatRoomId) async {
    hiddenRoomIds.add(chatRoomId);
  }

  @override
  Future<void> blockChatRoom(String chatRoomId) async {
    blockedRoomIds.add(chatRoomId);
  }

  @override
  Future<Map<String, dynamic>> updateNotificationSettings(
    String chatRoomId, {
    bool? muted,
    bool? pinned,
  }) async {
    if (pinned == true) {
      pinnedRoomIds.add(chatRoomId);
    }
    return {'pinned': pinned ?? false, 'muted': muted ?? false};
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
    String? replyToId,
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
