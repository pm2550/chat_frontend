import 'dart:async';

import 'package:chat_app/models/call_state.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/chat_room_member.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/sticker.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.parse('2024-01-01T10:00:00');

User _user(String id, String name) => User(
      id: id,
      username: 'u$id',
      email: 'u$id@test.com',
      displayName: name,
      createdAt: _now,
    );

Message _msg(String id, String content, {bool starred = false}) => Message(
      id: id,
      content: content,
      senderId: '2',
      senderName: '好友',
      chatRoomId: '10',
      status: MessageStatus.sent,
      timestamp: _now.add(Duration(minutes: int.parse(id))),
      starredByMe: starred,
    );

void main() {
  setUp(() {
    ChatScreen.clearMessageCacheForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  late AuthService auth;

  Future<void> signIn(WidgetTester tester) async {
    auth = AuthService();
    await auth.replaceCurrentUser(_user('1', '我'));
    addTearDown(auth.clearLocalSession);
  }

  Chat privateChat() => Chat(
        id: '10',
        name: '好友',
        type: ChatType.private,
        createdAt: _now,
        participants: [_user('1', '我'), _user('2', '好友')],
      );

  Chat groupChat({String? createdBy}) => Chat(
        id: '10',
        name: '项目群',
        type: ChatType.group,
        createdAt: _now,
        createdBy: createdBy,
        participants: [_user('1', '我'), _user('2', '好友'), _user('3', '同事')],
      );

  Widget buildScreen(
    Chat chat,
    _UiFakeChatService service, {
    ContactDataService? contactService,
    RouteFactory? onGenerateRoute,
  }) {
    return MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name != null && settings.name!.startsWith('/chat/')) {
          return onGenerateRoute?.call(settings);
        }
        return MaterialPageRoute<void>(
          settings: RouteSettings(arguments: chat),
          builder: (_) => ChatScreen(
            chatService: service,
            authService: auth,
            botService: _NoBotService(),
            contactService: contactService ?? _FakeContactService(),
            webSocketService: WebSocketService.forTesting(authService: auth),
          ),
        );
      },
    );
  }

  group('pinned messages', () {
    testWidgets('shows the latest pin, lists all pins, jumps and unpins',
        (tester) async {
      await signIn(tester);
      final service = _UiFakeChatService(
        messages: [_msg('1', '第一条'), _msg('2', '开会时间改到三点')],
        pins: [_msg('2', '开会时间改到三点'), _msg('1', '第一条')],
      );

      await tester.pumpWidget(buildScreen(privateChat(), service));
      await tester.pumpAndSettle();

      final bar = find.byKey(const ValueKey('pinned-messages-bar'));
      expect(bar, findsOneWidget);
      expect(
        find.descendant(
          of: bar,
          matching: find.textContaining('开会时间改到三点', findRichText: true),
        ),
        findsOneWidget,
      );

      await tester.tap(bar);
      await tester.pumpAndSettle();
      expect(find.text('置顶消息'), findsOneWidget);
      expect(find.byKey(const ValueKey('pinned-message-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('pinned-message-2')), findsOneWidget);

      // Unpin the older one from the list.
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('pinned-message-1')),
        matching: find.byTooltip('取消置顶'),
      ));
      await tester.pumpAndSettle();
      expect(service.unpinnedIds, ['1']);
      expect(find.byKey(const ValueKey('pinned-message-1')), findsNothing);

      // Tapping a pin closes the sheet and jumps to the message.
      await tester.tap(find.byKey(const ValueKey('pinned-message-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pinned-message-2')), findsNothing);
      expect(find.text('开会时间改到三点'), findsOneWidget);
    });

    testWidgets('pinning from the message menu shows the bar; menu then unpins',
        (tester) async {
      await signIn(tester);
      final service = _UiFakeChatService(messages: [_msg('1', '重要通知')]);

      await tester.pumpWidget(buildScreen(privateChat(), service));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pinned-messages-bar')), findsNothing);

      await tester.longPress(find.text('重要通知'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置顶消息'));
      await tester.pumpAndSettle();

      expect(service.pinnedIds, ['1']);
      expect(find.byKey(const ValueKey('pinned-messages-bar')), findsOneWidget);

      await tester.longPress(find.text('重要通知').first);
      await tester.pumpAndSettle();
      expect(find.text('置顶消息'), findsNothing);
      await tester.tap(find.text('取消置顶'));
      await tester.pumpAndSettle();

      expect(service.unpinnedIds, ['1']);
      expect(find.byKey(const ValueKey('pinned-messages-bar')), findsNothing);
    });

    testWidgets('group members who are not admins cannot pin or unpin',
        (tester) async {
      await signIn(tester);
      final service = _UiFakeChatService(
        messages: [_msg('1', '群消息')],
        pins: [_msg('1', '群消息')],
        members: [
          _member('1', role: 'MEMBER'),
          _member('2', role: 'OWNER'),
        ],
      );

      await tester.pumpWidget(buildScreen(groupChat(createdBy: '2'), service));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('群消息').last);
      await tester.pumpAndSettle();
      expect(find.text('置顶消息'), findsNothing);
      expect(find.text('取消置顶'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pinned-messages-bar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pinned-message-1')), findsOneWidget);
      expect(find.byTooltip('取消置顶'), findsNothing);
    });

    testWidgets('group admins can pin', (tester) async {
      await signIn(tester);
      final service = _UiFakeChatService(
        messages: [_msg('1', '群消息')],
        members: [
          _member('1', role: 'ADMIN'),
          _member('2', role: 'OWNER'),
        ],
      );

      await tester.pumpWidget(buildScreen(groupChat(createdBy: '2'), service));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('群消息'));
      await tester.pumpAndSettle();
      expect(find.text('置顶消息'), findsOneWidget);
    });
  });

  group('starred messages', () {
    testWidgets('menu stars an unstarred message, then offers 取消收藏',
        (tester) async {
      await signIn(tester);
      final service = _UiFakeChatService(messages: [_msg('1', '值得收藏')]);

      await tester.pumpWidget(buildScreen(privateChat(), service));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('值得收藏'));
      await tester.pumpAndSettle();
      expect(find.text('取消收藏'), findsNothing);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(service.starredIds, ['1']);

      await tester.longPress(find.text('值得收藏'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消收藏'));
      await tester.pumpAndSettle();
      expect(service.unstarredIds, ['1']);
    });

    testWidgets('already-starred message from the server shows 取消收藏',
        (tester) async {
      await signIn(tester);
      final service =
          _UiFakeChatService(messages: [_msg('1', '早就收藏了', starred: true)]);

      await tester.pumpWidget(buildScreen(privateChat(), service));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('早就收藏了'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消收藏'));
      await tester.pumpAndSettle();

      expect(service.unstarredIds, ['1']);
      expect(service.starredIds, isEmpty);
    });
  });

  testWidgets('删除聊天 clears history, removes the chat from the list and leaves',
      (tester) async {
    await signIn(tester);
    final service = _UiFakeChatService(messages: [_msg('1', '旧消息')]);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              settings: RouteSettings(arguments: privateChat()),
              builder: (_) => ChatScreen(
                chatService: service,
                authService: auth,
                botService: _NoBotService(),
                contactService: _FakeContactService(),
                webSocketService:
                    WebSocketService.forTesting(authService: auth),
              ),
            )),
            child: const Text('open-chat'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open-chat'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除聊天'));
    await tester.pumpAndSettle();

    // The confirmation describes what really happens.
    expect(find.textContaining('从你的消息列表移除'), findsOneWidget);
    expect(find.textContaining('此操作无法撤销'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(service.displayActions, ['CLEAR', 'REMOVE_FROM_LIST']);
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('open-chat'), findsOneWidget);
  });

  testWidgets('desktop member 视频 opens a private chat and starts a video call',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await signIn(tester);

    final contacts = _FakeContactService();
    Object? openedArguments;
    await tester.pumpWidget(buildScreen(
      groupChat(),
      _UiFakeChatService(
        messages: const [],
        members: [
          _member('1', role: 'MEMBER'),
          _member('2', role: 'OWNER'),
          _member('3', role: 'MEMBER'),
        ],
      ),
      contactService: contacts,
      onGenerateRoute: (settings) {
        openedArguments = settings.arguments;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('opened-private-chat')),
        );
      },
    ));
    await tester.pumpAndSettle();

    final videoButtons = find.byTooltip('视频');
    // Me, 好友, 同事 → no button for myself.
    expect(videoButtons, findsNWidgets(2));
    await tester.tap(videoButtons.first);
    await tester.pumpAndSettle();

    expect(contacts.createdPrivateChatUserIds, ['2']);
    expect(find.text('opened-private-chat'), findsOneWidget);
    expect(openedArguments, isA<ChatScreenArguments>());
    final args = openedArguments as ChatScreenArguments;
    expect(args.chat.id, 'private-2');
    expect(args.startCall, CallMediaKind.video);
  });

  testWidgets(
      'desktop private panel 清空聊天记录 also clears the cache so old '
      'messages do not flash back on re-entry', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await signIn(tester);

    final service = _UiFakeChatService(messages: [_msg('1', '要被清掉的消息')]);
    await tester.pumpWidget(buildScreen(privateChat(), service));
    await tester.pumpAndSettle();
    expect(find.text('要被清掉的消息'), findsOneWidget);

    await tester.tap(find.text('清空聊天记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '清空'));
    await tester.pumpAndSettle();
    expect(service.displayActions, ['CLEAR']);
    expect(find.text('要被清掉的消息'), findsNothing);

    // Leave and re-enter while the server page is still loading: the screen
    // paints from the in-memory cache first, which must now be empty.
    await tester.pumpWidget(const SizedBox.shrink());
    final slow = _UiFakeChatService(
      messages: [_msg('1', '要被清掉的消息')],
      pageGate: Completer<void>(),
    );
    await tester.pumpWidget(buildScreen(privateChat(), slow));
    await tester.pump();
    await tester.pump();
    expect(find.text('要被清掉的消息'), findsNothing);
    slow.pageGate!.complete();
    await tester.pumpAndSettle();
  });
}

ChatRoomMember _member(String userId, {required String role}) =>
    ChatRoomMember(
      id: 'm$userId',
      userId: userId,
      user: _user(userId, '成员$userId'),
      role: role,
    );

Future<http.Response> _unusedRequest(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  throw UnimplementedError('$method $url');
}

class _UiFakeChatService extends ChatDataService {
  _UiFakeChatService({
    required List<Message> messages,
    List<Message> pins = const [],
    this.members = const [],
    this.pageGate,
  })  : messages = List<Message>.from(messages),
        pins = List<Message>.from(pins),
        super(authenticatedRequest: _unusedRequest);

  final List<Message> messages;
  final List<Message> pins;
  final List<ChatRoomMember> members;
  final Completer<void>? pageGate;
  final List<String> pinnedIds = [];
  final List<String> unpinnedIds = [];
  final List<String> starredIds = [];
  final List<String> unstarredIds = [];
  final List<String> displayActions = [];

  @override
  Future<MessagePage> getMessagePage(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    final gate = pageGate;
    if (gate != null) await gate.future;
    return MessagePage(
      messages: List<Message>.from(messages),
      currentPage: page,
      totalPages: 1,
      totalElements: messages.length,
      hasNext: false,
      hasPrevious: false,
    );
  }

  @override
  Future<List<Message>> getMessageDelta(
    String chatRoomId, {
    required String afterMessageId,
    int size = 50,
  }) async =>
      const [];

  @override
  Future<List<ChatRoomMember>> getChatRoomMembers(String chatRoomId) async =>
      members;

  @override
  Future<List<Message>> getPinnedMessages(String chatRoomId) async =>
      List<Message>.from(pins);

  @override
  Future<List<Message>> pinMessage(String chatRoomId, String messageId) async {
    pinnedIds.add(messageId);
    pins.insert(0, messages.firstWhere((m) => m.id == messageId));
    return List<Message>.from(pins);
  }

  @override
  Future<List<Message>> unpinMessage(
      String chatRoomId, String messageId) async {
    unpinnedIds.add(messageId);
    pins.removeWhere((m) => m.id == messageId);
    return List<Message>.from(pins);
  }

  @override
  Future<Message> starMessage(String messageId) async {
    starredIds.add(messageId);
    return messages.firstWhere((m) => m.id == messageId);
  }

  @override
  Future<Message> unstarMessage(String messageId) async {
    unstarredIds.add(messageId);
    return messages.firstWhere((m) => m.id == messageId);
  }

  @override
  Future<Map<String, dynamic>> updateChatRoomDisplayState(
    String chatRoomId, {
    required String action,
  }) async {
    displayActions.add(action);
    return const {};
  }

  @override
  Future<void> markAllRead(String chatRoomId) async {}

  @override
  Future<void> markMessageRead(String messageId) async {}

  @override
  Future<List<StickerPack>> getStickerPacks() async => const [];
}

class _NoBotService extends BotService {
  @override
  Future<List<BotConfig>> getBotsInRoom(int roomId) async => const [];
}

class _FakeContactService extends ContactDataService {
  _FakeContactService() : super(authenticatedRequest: _unusedRequest);

  final List<String> createdPrivateChatUserIds = [];

  @override
  Future<List<User>> getFriends() async => const [];

  @override
  Future<List<FriendshipRequest>> getSentFriendRequests() async => const [];

  @override
  Future<Chat> createPrivateChat(String userId) async {
    createdPrivateChatUserIds.add(userId);
    return Chat(
      id: 'private-$userId',
      name: '成员$userId',
      type: ChatType.private,
      createdAt: _now,
    );
  }
}
