import 'dart:async';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/screens/home/chat_list_page.dart';
import 'package:chat_app/screens/home/hidden_chats_screen.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final _created = DateTime.parse('2024-01-01T10:00:00');

User _user(String id, String name, {String? username}) => User(
      id: id,
      username: username ?? 'user$id',
      email: '$id@test.com',
      displayName: name,
      createdAt: _created,
    );

void main() {
  late _ListService service;
  late _Contacts contacts;
  RouteSettings? openedChat;

  setUp(() {
    ChatDataService.clearChatRoomsCacheForTesting();
    openedChat = null;
    contacts = _Contacts(friends: [
      _user('20', '王设计', username: 'wangdesign'),
      _user('21', '李后端', username: 'libackend'),
    ]);
    service = _ListService(
      chats: [
        Chat(
          id: '1',
          name: '设计评审群',
          type: ChatType.group,
          createdAt: _created,
        ),
        Chat(
          id: '2',
          name: '老王',
          type: ChatType.private,
          createdAt: _created,
          participants: [_user('me', '我'), _user('30', '王小明')],
        ),
        Chat(
          id: '3',
          name: '无关会话',
          type: ChatType.group,
          createdAt: _created,
        ),
      ],
      hidden: [
        Chat(
          id: '8',
          name: '被移出的群',
          type: ChatType.group,
          createdAt: _created,
          hiddenAt: _created,
        ),
        Chat(
          id: '9',
          name: '被屏蔽的人',
          type: ChatType.private,
          createdAt: _created,
          hiddenAt: _created,
          isBlocked: true,
        ),
      ],
      messageHits: [
        Message(
          id: '501',
          content: '设计稿周五前给到',
          senderId: '21',
          senderName: '李后端',
          chatRoomId: '3',
          status: MessageStatus.sent,
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ],
    );
  });

  Widget build() {
    return MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name?.startsWith('/chat/') == true) {
          openedChat = settings;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('chat-opened')),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ChatListPage(
            chatService: service,
            contactService: contacts,
            realtimeService: _Realtime(),
            currentUserId: 'me',
          ),
        );
      },
    );
  }

  group('search', () {
    testWidgets('finds chats, contacts and messages across all chats',
        (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '设计');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(service.globalQueries, ['设计']);
      final results = find.byKey(const ValueKey('chat-list-search-results'));
      expect(results, findsOneWidget);
      // 聊天: matched by room name.
      expect(find.descendant(of: results, matching: find.text('设计评审群')),
          findsOneWidget);
      expect(find.text('无关会话'), findsNothing);
      // 联系人: matched by username.
      expect(find.byKey(const ValueKey('search-friend-20')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-friend-21')), findsNothing);
      // 消息: server-side hit inside a chat whose name does not match.
      expect(find.byKey(const ValueKey('search-message-501')), findsOneWidget);
      expect(find.text('设计稿周五前给到'), findsOneWidget);
    });

    testWidgets('private chats match the peer name', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '王小明');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('老王'), findsOneWidget);
    });

    testWidgets('opening a message hit focuses that message in its chat',
        (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '设计');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-message-501')));
      await tester.pumpAndSettle();

      expect(find.text('chat-opened'), findsOneWidget);
      expect(openedChat?.name, '/chat/3');
      final args = openedChat?.arguments as ChatScreenArguments;
      expect(args.chat.name, '无关会话');
      expect(args.focusMessage?.id, '501');
    });

    testWidgets('opening a contact hit opens the private chat', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'wangdesign');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-friend-20')));
      await tester.pumpAndSettle();

      expect(contacts.openedPrivateChats, ['20']);
      expect(openedChat?.name, '/chat/p20');
    });

    testWidgets('clearing the query returns to the chat list', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '设计');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat-list-search-results')),
          findsNothing);
      expect(find.text('无关会话'), findsOneWidget);
    });
  });

  testWidgets('移出列表 can be undone from the snackbar', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('设计评审群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出列表'));
    await tester.pumpAndSettle();
    expect(service.hiddenIds, ['1']);
    expect(find.text('设计评审群'), findsNothing);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(service.restoredIds, ['1']);
    expect(find.text('设计评审群'), findsOneWidget);
  });

  testWidgets('已移出的聊天 lists hidden and blocked chats and restores them',
      (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已移出的聊天'));
    await tester.pumpAndSettle();

    expect(find.byType(HiddenChatsScreen), findsOneWidget);
    expect(find.text('被移出的群'), findsOneWidget);
    expect(find.text('被屏蔽的人'), findsOneWidget);
    expect(find.text('设计评审群'), findsNothing);

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('hidden-chat-8')),
      matching: find.text('恢复'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('hidden-chat-9')),
      matching: find.text('取消屏蔽'),
    ));
    await tester.pumpAndSettle();

    expect(service.restoredIds, ['8']);
    expect(service.unblockedIds, ['9']);
    expect(find.text('没有被移出或屏蔽的聊天'), findsOneWidget);

    final refreshesBefore = service.forceRefreshCount;
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(service.forceRefreshCount, greaterThan(refreshesBefore));
    expect(find.text('被移出的群'), findsOneWidget);
    expect(find.text('被屏蔽的人'), findsOneWidget);
  });
}

class _ListService extends ChatDataService {
  _ListService({
    required List<Chat> chats,
    required List<Chat> hidden,
    required this.messageHits,
  })  : _visible = List<Chat>.from(chats),
        _hidden = List<Chat>.from(hidden),
        super(authenticatedRequest: _unused);

  final List<Chat> _visible;
  final List<Chat> _hidden;
  final List<Message> messageHits;
  final List<String> globalQueries = [];
  final List<String> hiddenIds = [];
  final List<String> restoredIds = [];
  final List<String> unblockedIds = [];
  int forceRefreshCount = 0;

  static Future<dynamic> _unused(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError('$method $url');
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
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) forceRefreshCount++;
    if (page > 0) return const [];
    return [
      ..._visible,
      if (includeHidden)
        ..._hidden.where((c) => !c.isBlocked || includeBlocked),
    ];
  }

  @override
  Future<MessagePage> searchAllMessages(
    String keyword, {
    int page = 0,
    int size = 20,
  }) async {
    globalQueries.add(keyword);
    final hits =
        messageHits.where((m) => m.content.contains(keyword)).toList();
    return MessagePage(
      messages: hits,
      currentPage: 0,
      totalPages: 1,
      totalElements: hits.length,
      hasNext: false,
      hasPrevious: false,
    );
  }

  Chat _move(List<Chat> from, List<Chat> to, String id, Chat Function(Chat) f) {
    final chat = from.firstWhere((c) => c.id == id);
    from.remove(chat);
    final next = f(chat);
    to.add(next);
    return next;
  }

  @override
  Future<void> hideChatRoom(String chatRoomId) async {
    hiddenIds.add(chatRoomId);
    _move(_visible, _hidden, chatRoomId, (c) => c.copyWith(hiddenAt: _created));
  }

  @override
  Future<void> restoreChatRoom(String chatRoomId) async {
    restoredIds.add(chatRoomId);
    _move(_hidden, _visible, chatRoomId,
        (c) => Chat(id: c.id, name: c.name, type: c.type, createdAt: _created));
  }

  @override
  Future<void> unblockChatRoom(String chatRoomId) async {
    unblockedIds.add(chatRoomId);
    _move(_hidden, _visible, chatRoomId,
        (c) => Chat(id: c.id, name: c.name, type: c.type, createdAt: _created));
  }
}

class _Contacts extends ContactDataService {
  _Contacts({required this.friends}) : super(authenticatedRequest: _unused);

  final List<User> friends;
  final List<String> openedPrivateChats = [];

  static Future<http.Response> _unused(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError('$method $url');
  }

  @override
  Future<List<User>> getFriends() async => friends;

  @override
  Future<Chat> createPrivateChat(String userId) async {
    openedPrivateChats.add(userId);
    return Chat(
      id: 'p$userId',
      name: '私聊$userId',
      type: ChatType.private,
      createdAt: _created,
    );
  }
}

class _Realtime implements ChatRealtimeService {
  final _messages = StreamController<Message>.broadcast();
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<Message> get onMessage => _messages.stream;

  @override
  Stream<Map<String, dynamic>> get onTyping => _events.stream;

  @override
  Stream<Map<String, dynamic>> get onStatusChange => _events.stream;

  @override
  Future<void> connect() async {}

  @override
  void disconnect() {}

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
}
