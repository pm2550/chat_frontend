import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:chat_app/design/design.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/models/call_state.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/sticker.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/chat_call_service.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(ChatScreen.clearMessageCacheForTesting);

  final testMessages = [
    Message(
      id: '1',
      content: '后端消息一',
      senderId: 'user2',
      senderName: '好友',
      chatRoomId: 'chat1',
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:00:00'),
    ),
    Message(
      id: '2',
      content: '后端消息二',
      senderId: 'user1',
      senderName: '我',
      chatRoomId: 'chat1',
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:01:00'),
    ),
  ];

  // Create a test Chat object with participants.
  Chat createTestChat({
    String id = 'chat1',
    String name = '测试聊天',
    ChatType type = ChatType.private,
    String participantId = 'user2',
  }) {
    final now = DateTime.now();
    return Chat(
      id: id,
      name: name,
      type: type,
      createdAt: now,
      participants: [
        User(
          id: participantId,
          username: 'friend',
          email: 'friend@example.com',
          displayName: '好友',
          onlineStatus: OnlineStatus.online,
          createdAt: now,
        ),
      ],
    );
  }

  /// Builds the ChatScreen inside a MaterialApp, passing the Chat object
  /// via route settings arguments (as ChatScreen reads it from ModalRoute).
  Widget buildTestWidget(
    Chat chat, {
    ChatDataService? chatService,
    ChatCallService? callService,
    ContactDataService? contactService,
    AuthService? authService,
    BotService? botService,
    WebSocketService? webSocketService,
    ChatAttachmentPicker? imagePicker,
    ChatAttachmentPicker? filePicker,
  }) {
    final effectiveWebSocketService = webSocketService ??
        WebSocketService.forTesting(authService: _NoSocketAuthService());
    return MaterialApp(
      home: Builder(
        builder: (context) {
          // We use a Navigator with an initial route that passes the Chat
          // as arguments to ChatScreen.
          return Navigator(
            onGenerateRoute: (settings) {
              return MaterialPageRoute(
                settings: RouteSettings(arguments: chat),
                builder: (context) => ChatScreen(
                  chatService: chatService ??
                      FakeChatDataService(messages: testMessages),
                  callService: callService,
                  contactService: contactService,
                  authService: authService,
                  botService: botService,
                  webSocketService: effectiveWebSocketService,
                  imagePicker: imagePicker,
                  filePicker: filePicker,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget buildRouteOnlyWidget(
    String routeName, {
    required ChatDataService chatService,
  }) {
    return MaterialApp(
      home: Navigator(
        onGenerateInitialRoutes: (navigator, initialRoute) => [
          MaterialPageRoute(
            settings: RouteSettings(name: routeName),
            builder: (context) => ChatScreen(chatService: chatService),
          ),
        ],
      ),
    );
  }

  group('ChatScreen', () {
    testWidgets('renders private peer display name in app bar', (tester) async {
      final chat = createTestChat(name: '李四');

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.text('好友'), findsOneWidget);
      expect(find.text('李四'), findsNothing);
    });

    testWidgets('own realtime message does not show new message badge',
        (tester) async {
      final chat = createTestChat();
      final authService = _CurrentUserNoSocketAuthService(userId: 'user1');
      final webSocketService =
          WebSocketService.forTesting(authService: authService);
      final messages = List<Message>.generate(
        36,
        (index) => Message(
          id: 'history-$index',
          content: '历史消息 $index',
          senderId: index.isEven ? 'user2' : 'user1',
          senderName: index.isEven ? '好友' : '我',
          chatRoomId: 'chat1',
          status: MessageStatus.sent,
          timestamp: DateTime.parse('2024-01-01T10:00:00')
              .add(Duration(minutes: index)),
        ),
      );

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: messages),
        authService: authService,
        webSocketService: webSocketService,
      ));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
      await tester.pump();

      webSocketService.handleMessageForTest(jsonEncode({
        'type': 'message',
        'message': {
          'id': 'own-realtime',
          'content': '自己的远端回包',
          'senderId': 'user1',
          'senderName': '我',
          'chatRoomId': 'chat1',
          'messageType': 'TEXT',
          'messageStatus': 'SENT',
          'createdAt': '2024-01-01T11:00:00',
        },
      }));
      await tester.pump();

      expect(find.text('1 条新消息'), findsNothing);
    });

    testWidgets('initial long history stays anchored to the newest message',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final messages = List<Message>.generate(
        90,
        (index) => Message(
          id: 'history-$index',
          content: '第 $index 条消息 ${'较长内容 ' * (index % 5 + 1)}',
          senderId: index.isEven ? 'user2' : 'user1',
          senderName: index.isEven ? '好友' : '我',
          chatRoomId: 'chat1',
          status: MessageStatus.sent,
          timestamp: DateTime.parse('2024-01-01T10:00:00')
              .add(Duration(minutes: index)),
        ),
      );

      await tester.pumpWidget(buildTestWidget(
        createTestChat(),
        chatService: FakeChatDataService(messages: messages),
      ));
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('chat-message-list')),
      );
      final position = list.controller!.position;
      expect(position.maxScrollExtent - position.pixels, lessThanOrEqualTo(2));
      expect(find.textContaining('第 89 条消息'), findsOneWidget);
    });

    testWidgets('mobile composer moves above keyboard viewInsets',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      final chat = createTestChat(id: '42');

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      final shellFinder =
          find.byKey(const ValueKey('chat-composer-text-field-shell'));
      expect(shellFinder, findsOneWidget);
      final shellBottom = tester.getBottomLeft(shellFinder).dy;
      const keyboardTop = 844 - 250;

      expect(shellBottom, lessThanOrEqualTo(keyboardTop + 4));
      expect(shellBottom, greaterThan(keyboardTop - 60));
    });

    testWidgets('mobile composer sits near bottom when keyboard is closed',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat(id: '42');

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      final shellFinder =
          find.byKey(const ValueKey('chat-composer-text-field-shell'));
      expect(shellFinder, findsOneWidget);
      final shellBottom = tester.getBottomLeft(shellFinder).dy;

      expect(shellBottom, greaterThan(760));
      expect(shellBottom, lessThanOrEqualTo(844));
    });

    testWidgets('375px composer collapses leading actions into more menu',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat(id: '42');

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      expect(find.byTooltip('其它操作'), findsOneWidget);
      expect(find.byTooltip('表情'), findsNothing);
      expect(find.byTooltip('贴纸'), findsNothing);
      expect(find.byTooltip('插入 AI 助手'), findsNothing);

      await tester.tap(find.byTooltip('其它操作'));
      await tester.pumpAndSettle();

      for (final label in [
        '表情',
        '贴纸',
        '插入 AI 助手',
        '拍照',
        '相册',
        '文件',
        '语音文件',
        '位置',
        '投票',
      ]) {
        expect(find.text(label), findsOneWidget);
      }

      final shellWidth = tester
          .getSize(find.byKey(const ValueKey('chat-composer-text-field-shell')))
          .width;
      expect(shellWidth, greaterThanOrEqualTo(180));
    });

    testWidgets('375px more menu launches emoji panel', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat(id: '42');

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      await tester.tap(find.byTooltip('其它操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('表情'));
      await tester.pumpAndSettle();

      expect(find.byType(EmojiPicker), findsOneWidget);
    });

    testWidgets('375px more menu launches sticker panel', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat(id: '42');

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      await tester.tap(find.byTooltip('其它操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('贴纸'));
      await tester.pumpAndSettle();

      expect(find.text('暂无贴纸包'), findsOneWidget);
    });

    testWidgets('375px more menu inserts system Agent mention without sending',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat(id: '42');
      final service = FakeChatDataService(messages: const []);

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: service,
        botService: FakeBotService(roomBots: [
          BotConfig(id: 3, botName: 'Deploy Bot', llmProvider: 'HERMES'),
        ]),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('其它操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('插入 AI 助手'));
      await tester.pumpAndSettle();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '@Deploy Bot ');
      expect(find.text('/ask · 问 AI'), findsNothing);
      expect(service.sentTexts, isEmpty);
    });

    testWidgets('375x812 composer more sheet exposes expanded actions',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      expect(find.byTooltip('其它操作'), findsOneWidget);

      await tester.tap(find.byTooltip('其它操作'));
      await tester.pumpAndSettle();

      for (final label in [
        '表情',
        '贴纸',
        '插入 AI 助手',
        '拍照',
        '相册',
        '文件',
        '语音文件',
        '位置',
        '投票',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('414px composer collapses when usable row width is tight',
        (tester) async {
      tester.view.physicalSize = const Size(414, 896);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      expect(find.byTooltip('其它操作'), findsOneWidget);
      expect(find.byTooltip('表情'), findsNothing);
      expect(find.byTooltip('贴纸'), findsNothing);
      expect(find.byTooltip('插入 AI 助手'), findsNothing);

      final shellWidth = tester
          .getSize(find.byKey(const ValueKey('chat-composer-text-field-shell')))
          .width;
      expect(shellWidth, greaterThanOrEqualTo(180));
    });

    testWidgets('720px composer keeps primary actions inline', (tester) async {
      tester.view.physicalSize = const Size(720, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      expect(find.byTooltip('表情'), findsOneWidget);
      expect(find.byTooltip('贴纸'), findsOneWidget);
      expect(find.byTooltip('插入 AI 助手'), findsOneWidget);
      expect(find.byTooltip('附件'), findsOneWidget);

      final shellWidth = tester
          .getSize(find.byKey(const ValueKey('chat-composer-text-field-shell')))
          .width;
      expect(shellWidth, greaterThanOrEqualTo(180));
    });

    testWidgets('inline Agent button inserts mention and does not submit',
        (tester) async {
      tester.view.physicalSize = const Size(720, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat(id: '42');
      final service = FakeChatDataService(messages: const []);

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: service,
        botService: FakeBotService(roomBots: [
          BotConfig(id: 4, botName: 'Helper Bot', llmProvider: 'HERMES'),
        ]),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('插入 AI 助手'));
      await tester.pumpAndSettle();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '@Helper Bot ');
      expect(find.text('/ask · 问 AI'), findsNothing);
      expect(service.sentTexts, isEmpty);
    });

    testWidgets('loads chat by route id when arguments are missing',
        (tester) async {
      final routeChat = createTestChat(id: '42', name: '直链房间');
      final service = FakeChatDataService(
        messages: const [],
        routeChat: routeChat,
      );

      await tester.pumpWidget(buildRouteOnlyWidget(
        '/chat/42',
        chatService: service,
      ));
      await tester.pump();
      await tester.pump();

      expect(service.loadedChatRoomIds, ['42']);
      expect(find.text('好友'), findsWidgets);
      expect(find.text('直链房间'), findsNothing);
      expect(find.text('无法打开聊天'), findsNothing);
    });

    testWidgets('shows friendly error instead of crashing without chat id',
        (tester) async {
      final service = FakeChatDataService(messages: const []);

      await tester.pumpWidget(buildRouteOnlyWidget(
        '/chat',
        chatService: service,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('无法打开聊天'), findsOneWidget);
      expect(find.textContaining('缺少聊天室编号'), findsOneWidget);
    });

    testWidgets('renders message input hint text', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.text('输入消息...'), findsOneWidget);
    });

    testWidgets('renders a TextField for message input', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders mic button initially (no text typed)', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // When no text is entered, should show mic button instead of send.
      expect(find.byTooltip('录音说话'), findsOneWidget);
    });

    testWidgets('shows send button when text is typed', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // Type some text in the input field.
      await tester.enterText(find.byType(TextField), '你好');
      await tester.pump();

      // Now the send icon should appear.
      expect(find.byTooltip('发送'), findsOneWidget);
      expect(find.byTooltip('录音说话'), findsNothing);
    });

    testWidgets('typing @ opens mention picker with keyboard selection',
        (tester) async {
      final now = DateTime.now();
      final groupChat = Chat(
        id: '42',
        name: 'Mention Room',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: '2',
            username: 'alice',
            email: 'alice@test.com',
            displayName: 'Alice',
            createdAt: now,
          ),
          User(
            id: '3',
            username: 'bob',
            email: 'bob@test.com',
            displayName: 'Bob',
            createdAt: now,
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(
        groupChat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();

      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '@bob ');
    });

    testWidgets('typing @ filters mention picker by display name prefix',
        (tester) async {
      final now = DateTime.now();
      final groupChat = Chat(
        id: '42',
        name: 'Mention Room',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: '2',
            username: 'zhangsan',
            email: 'zhang@test.com',
            displayName: '张三',
            createdAt: now,
          ),
          User(
            id: '3',
            username: 'alice',
            email: 'alice@test.com',
            displayName: 'Alice',
            createdAt: now,
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(
        groupChat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '@张');
      await tester.pump();

      expect(find.text('张三'), findsWidgets);
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('tapping mention picker member inserts username mention',
        (tester) async {
      final now = DateTime.now();
      final groupChat = Chat(
        id: '42',
        name: 'Mention Room',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: '2',
            username: 'zhangsan',
            email: 'zhang@test.com',
            displayName: '张三',
            createdAt: now,
          ),
          User(
            id: '3',
            username: 'alice',
            email: 'alice@test.com',
            displayName: 'Alice',
            createdAt: now,
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(
        groupChat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '@张');
      await tester.pump();
      await tester.tap(find.text('张三').first);
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '@zhangsan ');
      expect(find.text('张三'), findsNothing);
    });

    testWidgets('anonymous-like participants are excluded from mention picker',
        (tester) async {
      final now = DateTime.now();
      final groupChat = Chat(
        id: 'chat1',
        name: 'Mention Room',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: '2',
            username: 'alice',
            email: 'alice@test.com',
            displayName: 'Alice',
            createdAt: now,
          ),
          User(
            id: 'anon',
            username: '',
            email: 'anon@test.com',
            displayName: '神秘小象',
            createdAt: now,
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(
        groupChat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();

      expect(find.text('Alice'), findsWidgets);
      expect(find.text('神秘小象'), findsNothing);
    });

    testWidgets('typing @ includes active room bots in mention picker',
        (tester) async {
      final now = DateTime.now();
      final groupChat = Chat(
        id: '42',
        name: 'Mention Bot Room',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: '2',
            username: 'alice',
            email: 'alice@test.com',
            displayName: 'Alice',
            createdAt: now,
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(
        groupChat,
        chatService: FakeChatDataService(messages: const []),
        botService: FakeBotService(roomBots: [
          BotConfig(
            id: 9,
            botName: 'HelperBot',
            llmProvider: 'HERMES',
            roomNickname: 'DeployBot',
          ),
        ]),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('DeployBot'), findsOneWidget);
      expect(find.text('AI Bot · @DeployBot'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '@Dep');
      await tester.pump();

      expect(find.text('DeployBot'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('right-click avatar in member panel inserts mention',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final groupChat = Chat(
        id: 'group1',
        name: 'Mention Room',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: '2',
            username: 'alice',
            email: 'alice@test.com',
            displayName: 'Alice',
            createdAt: now,
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(
        groupChat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();
      await tester.pump();

      final avatarFinder = find.byKey(const ValueKey('member-avatar-2'));
      expect(avatarFinder, findsOneWidget);
      final center = tester.getCenter(avatarFinder);
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await tester.pump();
      await gesture.down(center);
      await gesture.up();
      await gesture.removePointer();
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '@alice ');
    });

    testWidgets('long-press message avatar inserts mention on mobile',
        (tester) async {
      final now = DateTime.now();
      final groupChat = Chat(
        id: 'group1',
        name: 'Mention Room',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: '2',
            username: 'alice',
            email: 'alice@test.com',
            displayName: 'Alice',
            createdAt: now,
          ),
        ],
      );
      final service = FakeChatDataService(messages: [
        Message(
          id: 'm1',
          content: '大家看这里',
          senderId: '2',
          senderName: 'Alice',
          chatRoomId: 'group1',
          status: MessageStatus.sent,
          timestamp: DateTime.parse('2024-01-01T10:00:00'),
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(groupChat, chatService: service));
      await tester.pump();

      await tester.longPress(find.byType(PMUserAvatar).first);
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '@alice ');
    });

    testWidgets('long-press bot message avatar inserts bot mention on mobile',
        (tester) async {
      final now = DateTime.now();
      final groupChat = Chat(
        id: 'group1',
        name: 'Mention Room',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: 'moondubai',
            username: 'Moondubai',
            email: 'moon@test.com',
            displayName: 'MoonDubai',
            createdAt: now,
          ),
        ],
      );
      final service = FakeChatDataService(messages: [
        Message(
          id: 'bot-msg',
          content: '我是 Agent',
          senderId: 'moondubai',
          senderName: 'Moondubai',
          chatRoomId: 'group1',
          status: MessageStatus.sent,
          timestamp: DateTime.parse('2024-01-01T10:00:00'),
          botConfigId: '9',
          botSenderId: '9',
          botName: 'Agent',
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(groupChat, chatService: service));
      await tester.pump();

      await tester.longPress(find.byType(PMUserAvatar).first);
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '@Agent ');
      expect(editable.controller.text, isNot('@Moondubai '));
    });

    testWidgets('pressing Enter sends message and clears input',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(messages: const []);

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Enter 发送');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(service.sentTexts, ['Enter 发送']);
      expect(find.text('Enter 发送'), findsOneWidget);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, isEmpty);
    });

    testWidgets('pressing Shift Enter keeps newline without sending',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(messages: const []);

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '第一行');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(service.sentTexts, isEmpty);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '第一行\n');
    });

    testWidgets('long press quote sends replyToId with next message',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(messages: testMessages);

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      await tester.longPress(find.text('后端消息一'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('引用'));
      await tester.pumpAndSettle();

      expect(find.text('回复 好友'), findsOneWidget);
      expect(find.text('后端消息一'), findsWidgets);

      await tester.enterText(find.byType(TextField), '回复内容');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(service.sentTexts, ['回复内容']);
      expect(service.sentReplyIds, ['1']);
      expect(find.text('回复 好友'), findsNothing);
    });

    testWidgets('desktop secondary click opens message actions',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(messages: testMessages);

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      final center = tester.getCenter(find.text('后端消息一'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await tester.pump();
      await gesture.down(center);
      await gesture.up();
      await gesture.removePointer();
      await tester.pumpAndSettle();

      expect(find.text('查看已读'), findsOneWidget);
      expect(find.text('引用'), findsOneWidget);
    });

    testWidgets('renders loaded messages as MessageBubble widgets',
        (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byType(MessageBubble), findsWidgets);
    });

    testWidgets('renders loaded message content text', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.text('后端消息一'), findsOneWidget);
      expect(find.text('后端消息二'), findsOneWidget);
    });

    testWidgets('opens loaded history pinned to the latest message',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final chat = createTestChat(id: 'long-history-room');
      final messages = List<Message>.generate(
        48,
        (index) => Message(
          id: 'history-$index',
          content: '历史消息 $index',
          senderId: index.isEven ? 'user2' : 'user1',
          senderName: index.isEven ? '好友' : '我',
          chatRoomId: 'long-history-room',
          status: MessageStatus.sent,
          timestamp: DateTime.parse('2024-01-01T10:00:00')
              .add(Duration(minutes: index)),
        ),
      );

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: messages),
      ));
      await tester.pumpAndSettle();

      final scrollableState =
          tester.state<ScrollableState>(find.byType(Scrollable).first);

      expect(
        scrollableState.position.pixels,
        closeTo(scrollableState.position.maxScrollExtent, 2),
      );
      expect(find.text('历史消息 47'), findsOneWidget);
    });

    testWidgets('reuses cached messages when re-enter refresh fails',
        (tester) async {
      final chat = createTestChat(id: 'cache-room');
      final firstService = FakeChatDataService(messages: [
        Message(
          id: 'cached-1',
          content: '缓存里的最后消息',
          senderId: 'user2',
          senderName: '好友',
          chatRoomId: 'cache-room',
          status: MessageStatus.sent,
          timestamp: DateTime.parse('2024-01-01T10:00:00'),
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(chat, chatService: firstService));
      await tester.pumpAndSettle();
      expect(find.text('缓存里的最后消息'), findsOneWidget);

      final failingService = FakeChatDataService(
        messages: const [],
        messagePageError: Exception('network flicker'),
      );

      await tester.pumpWidget(
        buildTestWidget(chat, chatService: failingService),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('缓存里的最后消息'), findsOneWidget);
      expect(find.text('消息加载失败'), findsNothing);
      expect(find.text('重试'), findsNothing);
    });

    testWidgets('announcement banner dismiss persists seen state',
        (tester) async {
      final updatedAt = DateTime.now();
      SharedPreferences.setMockInitialValues({});
      final chat = Chat(
        id: 'group1',
        name: '公告群',
        description: '群描述',
        announcement: '今天十点部署，请留意通知。',
        announcementUpdatedAt: updatedAt,
        announcementUpdatedBy: '1',
        type: ChatType.group,
        createdAt: updatedAt,
      );

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: FakeChatDataService(messages: const []),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('群公告'), findsOneWidget);
      expect(find.text('今天十点部署，请留意通知。'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭群公告'));
      await tester.pumpAndSettle();

      expect(find.text('今天十点部署，请留意通知。'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(
          'announcement_seen:group1:${updatedAt.toIso8601String()}',
        ),
        isTrue,
      );
    });

    testWidgets('renders app bar action buttons (call, video, settings, more)',
        (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byTooltip('语音通话'), findsOneWidget);
      expect(find.byTooltip('视频通话'), findsOneWidget);
      expect(find.byTooltip('聊天信息'), findsWidgets);
      expect(find.byTooltip('更多'), findsOneWidget);
    });

    testWidgets('voice call passes private peer id to call service',
        (tester) async {
      final chat = createTestChat(id: '42', participantId: '7');
      final callService = RecordingCallService();

      await tester.pumpWidget(buildTestWidget(chat, callService: callService));
      await tester.pump();

      await tester.tap(find.byTooltip('语音通话'));
      await tester.pump();

      expect(callService.startedRoomId, 42);
      expect(callService.startedPeerUserId, 7);
      expect(callService.startedMediaKind, CallMediaKind.audio);
    });

    testWidgets('private voice call panel hides mesh participant limit',
        (tester) async {
      final chat = createTestChat(id: '42', participantId: '7');
      final callService = FixedStateCallService(const ChatCallState(
        phase: CallPhase.outgoing,
        callId: 'call-private',
        chatRoomId: 42,
        mediaKind: CallMediaKind.audio,
        selfUserId: 1,
        participants: [
          CallParticipant(
            userId: 1,
            displayName: '我',
            state: PeerConnectionState.connected,
          ),
          CallParticipant(userId: 7, displayName: '好友'),
        ],
      ));

      await tester.pumpWidget(buildTestWidget(chat, callService: callService));
      await tester.pump();

      expect(find.text('好友 · 正在呼叫'), findsOneWidget);
      expect(find.textContaining('/6 人'), findsNothing);
    });

    testWidgets('private outgoing call status shows peer name not room name',
        (tester) async {
      final chat = createTestChat(
        id: '42',
        name: '参与者1&李四',
        participantId: '7',
      );
      final callService = FixedStateCallService(const ChatCallState(
        phase: CallPhase.outgoing,
        callId: 'call-private-outgoing',
        chatRoomId: 42,
        mediaKind: CallMediaKind.audio,
        selfUserId: 1,
        participants: [
          CallParticipant(
            userId: 1,
            displayName: '我',
            state: PeerConnectionState.connected,
          ),
          CallParticipant(userId: 7, displayName: '李四'),
        ],
      ));

      await tester.pumpWidget(buildTestWidget(chat, callService: callService));
      await tester.pump();

      expect(find.text('李四 · 正在呼叫'), findsOneWidget);
      expect(find.textContaining('/6'), findsNothing);
      expect(find.textContaining('参与者1&'), findsNothing);
    });

    testWidgets('group call status keeps mesh participant limit',
        (tester) async {
      final chat = createTestChat(
        id: '43',
        name: '项目群',
        type: ChatType.group,
      );
      final callService = FixedStateCallService(const ChatCallState(
        phase: CallPhase.connected,
        callId: 'call-group',
        chatRoomId: 43,
        mediaKind: CallMediaKind.audio,
        selfUserId: 1,
        participants: [
          CallParticipant(userId: 1, displayName: '我'),
          CallParticipant(userId: 2, displayName: '成员二'),
          CallParticipant(userId: 3, displayName: '成员三'),
        ],
      ));

      await tester.pumpWidget(buildTestWidget(chat, callService: callService));
      await tester.pump();

      expect(find.text('3/6 人 · 通话中'), findsOneWidget);
    });

    testWidgets('private ringing call status shows peer name plus label',
        (tester) async {
      final chat = createTestChat(id: '44', participantId: '7');
      final callService = FixedStateCallService(const ChatCallState(
        phase: CallPhase.ringing,
        callId: 'call-private-ringing',
        chatRoomId: 44,
        mediaKind: CallMediaKind.audio,
        selfUserId: 1,
        participants: [
          CallParticipant(userId: 1, displayName: '我'),
          CallParticipant(userId: 7, displayName: '李四'),
        ],
      ));

      await tester.pumpWidget(buildTestWidget(chat, callService: callService));
      await tester.pump();

      expect(find.text('李四 · 等待对方接听'), findsOneWidget);
      expect(find.textContaining('/6'), findsNothing);
    });

    testWidgets('renders add button for input options', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byTooltip('附件'), findsOneWidget);
    });

    testWidgets('shows online status for private chat with online participant',
        (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.text('在线'), findsOneWidget);
    });

    testWidgets('renders participant count for group chats', (tester) async {
      final now = DateTime.now();
      final groupChat = Chat(
        id: 'group1',
        name: '测试群组',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: 'u1',
            username: 'user1',
            email: 'u1@test.com',
            displayName: '用户1',
            createdAt: now,
          ),
          User(
            id: 'u2',
            username: 'user2',
            email: 'u2@test.com',
            displayName: '用户2',
            createdAt: now,
          ),
          User(
            id: 'u3',
            username: 'user3',
            email: 'u3@test.com',
            displayName: '用户3',
            createdAt: now,
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(groupChat));
      await tester.pump();

      expect(find.text('3人'), findsOneWidget);
    });

    testWidgets('desktop members panel can send friend request to group member',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final authService = AuthService();
      await authService.replaceCurrentUser(User(
        id: '1',
        username: 'me',
        email: 'me@test.com',
        displayName: '我',
        createdAt: now,
      ));
      addTearDown(authService.clearLocalSession);

      final friend = User(
        id: '2',
        username: 'friend',
        email: 'friend@test.com',
        displayName: '已好友',
        createdAt: now,
      );
      final stranger = User(
        id: '3',
        username: 'stranger',
        email: 'stranger@test.com',
        displayName: '陌生人',
        createdAt: now,
      );
      final groupChat = Chat(
        id: 'group1',
        name: '群成员加好友',
        type: ChatType.group,
        createdAt: now,
        participants: [
          authService.currentUser!,
          friend,
          stranger,
        ],
      );
      final contactService = FakeContactDataService(friends: [friend]);

      await tester.pumpWidget(buildTestWidget(
        groupChat,
        chatService: FakeChatDataService(messages: const []),
        contactService: contactService,
        authService: authService,
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byTooltip('已是好友'), findsOneWidget);
      expect(find.byTooltip('添加好友'), findsOneWidget);

      await tester.tap(find.byTooltip('添加好友'));
      await tester.pump();
      await tester.pump();

      expect(contactService.sentFriendRequestIds, ['3']);
      expect(find.byTooltip('好友请求已发送'), findsOneWidget);
      expect(find.text('已向 陌生人 发送好友请求'), findsOneWidget);
    });

    testWidgets('desktop members panel opens private chat from group member',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final authService = AuthService();
      await authService.replaceCurrentUser(User(
        id: '1',
        username: 'me',
        email: 'me@test.com',
        displayName: '我',
        createdAt: now,
      ));
      addTearDown(authService.clearLocalSession);

      final peer = User(
        id: '3',
        username: 'peer',
        email: 'peer@test.com',
        displayName: '侧栏成员',
        createdAt: now,
      );
      final groupChat = Chat(
        id: 'group1',
        name: '群成员私聊',
        type: ChatType.group,
        createdAt: now,
        participants: [
          authService.currentUser!,
          peer,
        ],
      );
      final privateChat = Chat(
        id: 'private-3',
        name: '侧栏成员',
        type: ChatType.private,
        createdAt: now,
        participants: [
          authService.currentUser!,
          peer,
        ],
      );
      final contactService = FakeContactDataService(
        privateChatsByUserId: {'3': privateChat},
      );

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name?.startsWith('/chat/') == true) {
              final chat = settings.arguments as Chat;
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => Scaffold(
                  body: Text('opened-private-chat-${chat.id}'),
                ),
              );
            }
            return MaterialPageRoute<void>(
              settings: RouteSettings(arguments: groupChat),
              builder: (_) => ChatScreen(
                chatService: FakeChatDataService(messages: const []),
                contactService: contactService,
                authService: authService,
                webSocketService:
                    WebSocketService.forTesting(authService: authService),
              ),
            );
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('私聊'));
      await tester.pumpAndSettle();

      expect(contactService.createdPrivateChatUserIds, ['3']);
      expect(find.text('opened-private-chat-private-3'), findsOneWidget);
    });

    testWidgets('renders CircleAvatar in app bar', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // The app bar shows a CircleAvatar for the chat.
      expect(find.byType(CircleAvatar), findsWidgets);
    });

    testWidgets('shows ListView for messages', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('can type message and see send button appear', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // Verify initial state has mic button.
      expect(find.byTooltip('录音说话'), findsOneWidget);

      // Enter text.
      await tester.enterText(find.byType(TextField), '新消息');
      await tester.pump();

      // Send button should now be visible.
      expect(find.byTooltip('发送'), findsOneWidget);

      // Clear text.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      // Mic button should come back.
      expect(find.byTooltip('录音说话'), findsOneWidget);
    });

    testWidgets('shows failed message when REST fallback send fails',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(
        messages: const [],
        sendError: Exception('network down'),
      );

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '发送失败消息');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();

      expect(find.text('发送失败消息'), findsOneWidget);
      expect(find.text('发送失败: Exception: network down'), findsOneWidget);
    });

    testWidgets('picks image and sends file message', (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(messages: const []);

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: service,
        imagePicker: () async => const PickedChatFile(
          name: 'photo.png',
          size: 3,
          mimeType: 'image/png',
          bytes: [1, 2, 3],
        ),
      ));
      await tester.pump();

      await tester.tap(find.byTooltip('附件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相册'));
      await tester.pump();

      expect(service.sentFiles.single.name, 'photo.png');
      expect(service.sentFiles.single.mimeType, 'image/png');
      expect(find.byType(MessageBubble), findsOneWidget);
      expect(find.text('photo.png'), findsNothing);
    });

    testWidgets('dragging files over chat shows upload overlay',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(messages: const []);

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      final target = tester.widget<DragTarget<List<PickedChatFile>>>(
        find.byKey(const Key('chat-drop-target')),
      );
      final accepted = target.onWillAcceptWithDetails?.call(
        DragTargetDetails<List<PickedChatFile>>(
          data: [
            const PickedChatFile(
              name: 'drop.png',
              size: 12,
              mimeType: 'image/png',
              bytes: [1, 2, 3],
            ),
            const PickedChatFile(
              name: 'notes.txt',
              size: 8,
              mimeType: 'text/plain',
              bytes: [4, 5],
            ),
          ],
          offset: Offset.zero,
        ),
      );
      await tester.pump();

      expect(accepted, isTrue);
      expect(find.text('释放以发送 2 个文件'), findsOneWidget);
    });

    testWidgets('picks generic file and shows failed file message on error',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(
        messages: const [],
        sendFileError: Exception('upload down'),
      );

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: service,
        filePicker: () async => const PickedChatFile(
          name: 'doc.pdf',
          size: 2048,
          mimeType: 'application/pdf',
          bytes: [1, 2, 3],
        ),
      ));
      await tester.pump();

      await tester.tap(find.byTooltip('附件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件'));
      await tester.pump();

      expect(find.text('[文件] doc.pdf'), findsOneWidget);
      expect(find.text('文件发送失败: Exception: upload down'), findsOneWidget);
    });

    testWidgets('searches chat history from chat options', (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(
        messages: const [],
        searchResults: [
          Message(
            id: 's1',
            content: 'needle result',
            senderId: 'user2',
            senderName: '好友',
            chatRoomId: 'chat1',
            status: MessageStatus.sent,
            timestamp: DateTime.parse('2024-01-01T10:03:00'),
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索聊天记录'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'needle');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();

      expect(service.searchKeywords, ['needle']);
      expect(find.text('needle result'), findsOneWidget);
    });

    testWidgets('long press deletes a message locally after backend success',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(messages: testMessages);

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      await tester.longPress(find.text('后端消息一'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除消息'));
      await tester.pumpAndSettle();

      expect(service.deletedMessageIds, ['1']);
      expect(find.text('[消息已删除]'), findsOneWidget);
    });
  });
}

class FakeChatDataService extends ChatDataService {
  FakeChatDataService({
    required this.messages,
    this.searchResults = const [],
    this.sendError,
    this.sendFileError,
    this.messagePageError,
    this.routeChat,
  }) : super(authenticatedRequest: _unusedRequest);

  final List<Message> messages;
  final List<Message> searchResults;
  final Object? sendError;
  final Object? sendFileError;
  final Object? messagePageError;
  final Chat? routeChat;
  final List<PickedChatFile> sentFiles = [];
  final List<String> sentTexts = [];
  final List<String?> sentReplyIds = [];
  final List<String> searchKeywords = [];
  final List<String> deletedMessageIds = [];
  final List<String> recalledMessageIds = [];
  final List<String> loadedChatRoomIds = [];
  final List<String> readMessageIds = [];
  bool markAllReadCalled = false;

  static Future<http.Response> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Chat> getChatRoom(
    String chatRoomId, {
    bool includeDetails = true,
  }) async {
    loadedChatRoomIds.add(chatRoomId);
    return routeChat ??
        Chat(
          id: chatRoomId,
          name: 'Loaded Room',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
        );
  }

  @override
  Future<MessagePage> getMessagePage(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    if (messagePageError != null) {
      throw messagePageError!;
    }
    return MessagePage(
      messages: messages,
      currentPage: page,
      totalPages: 1,
      totalElements: messages.length,
      hasNext: false,
      hasPrevious: page > 0,
    );
  }

  @override
  Future<List<Message>> getMessageDelta(
    String chatRoomId, {
    required String afterMessageId,
    int size = 50,
  }) async {
    final cursor = int.tryParse(afterMessageId) ?? -1;
    return messages
        .where((message) => (int.tryParse(message.id) ?? -1) > cursor)
        .toList();
  }

  @override
  Future<List<Message>> getMessages(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    return messages;
  }

  @override
  Future<MessagePage> searchMessages(
    String chatRoomId,
    String keyword, {
    int page = 0,
    int size = 20,
  }) async {
    searchKeywords.add(keyword);
    return MessagePage(
      messages: searchResults,
      currentPage: page,
      totalPages: 1,
      totalElements: searchResults.length,
      hasNext: false,
      hasPrevious: false,
    );
  }

  @override
  Future<Message> deleteMessage(String messageId) async {
    deletedMessageIds.add(messageId);
    final message = messages.firstWhere((message) => message.id == messageId);
    return message.copyWith(
      content: '[消息已删除]',
      isDeleted: true,
      chatRoomId: message.chatRoomId,
    );
  }

  @override
  Future<Message> recallMessage(String messageId) async {
    recalledMessageIds.add(messageId);
    final message = messages.firstWhere((message) => message.id == messageId);
    return message.copyWith(
      content: '[消息已撤回]',
      isDeleted: true,
      isRecalled: true,
      chatRoomId: message.chatRoomId,
    );
  }

  @override
  Future<void> markAllRead(String chatRoomId) async {
    markAllReadCalled = true;
  }

  @override
  Future<void> markMessageRead(String messageId) async {
    readMessageIds.add(messageId);
  }

  Message? _findMessage(String? messageId) {
    if (messageId == null) return null;
    for (final message in messages) {
      if (message.id == messageId) return message;
    }
    return null;
  }

  @override
  Future<Message> sendTextMessage(
    String chatRoomId,
    String content, {
    bool isAnonymous = false,
    String? replyToId,
  }) async {
    final error = sendError;
    if (error != null) {
      throw error;
    }
    sentTexts.add(content);
    sentReplyIds.add(replyToId);
    return Message(
      id: 'sent-1',
      content: content,
      senderId: 'user1',
      senderName: isAnonymous ? '匿名用户' : '我',
      chatRoomId: chatRoomId,
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
      replyToId: replyToId,
      replyToMessage: _findMessage(replyToId),
      replyToMessageId: replyToId,
      isAnonymous: isAnonymous,
      anonymousName: isAnonymous ? '匿名用户' : null,
    );
  }

  @override
  Future<Message> sendFileMessage(
    String chatRoomId,
    PickedChatFile file, {
    MessageType? messageType,
    String? encryptedContent,
    int? encryptionVersion,
  }) async {
    sentFiles.add(file);
    final error = sendFileError;
    if (error != null) {
      throw error;
    }
    final isImage = file.mimeType?.startsWith('image/') == true ||
        file.name.toLowerCase().endsWith('.png');
    return Message(
      id: 'file-1',
      content: file.name,
      senderId: 'user1',
      senderName: '我',
      chatRoomId: chatRoomId,
      type: messageType ?? (isImage ? MessageType.image : MessageType.file),
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
      fileUrl: '/api/files/chat/${file.name}',
      fileName: file.name,
      fileSize: file.size,
      fileType: file.mimeType,
    );
  }

  @override
  Future<DownloadedChatFile> downloadFile(Message message) async {
    return DownloadedChatFile(
      name: message.fileName ?? message.content,
      bytes: const [1, 2, 3],
      mimeType: message.fileType,
    );
  }

  @override
  Future<List<StickerPack>> getStickerPacks() async {
    return const <StickerPack>[];
  }

  @override
  Future<List<StickerItem>> getStickers(int packId) async {
    return const <StickerItem>[];
  }
}

class FakeBotService extends BotService {
  FakeBotService({this.roomBots = const []});

  final List<BotConfig> roomBots;

  @override
  Future<List<BotConfig>> getBotsInRoom(int roomId) async => roomBots;
}

class FakeContactDataService extends ContactDataService {
  FakeContactDataService({
    this.friends = const [],
    this.sentRequests = const [],
    this.privateChatsByUserId = const {},
  }) : super(authenticatedRequest: _unusedRequest);

  final List<User> friends;
  final List<FriendshipRequest> sentRequests;
  final Map<String, Chat> privateChatsByUserId;
  final List<String> sentFriendRequestIds = [];
  final List<String> createdPrivateChatUserIds = [];

  static Future<http.Response> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<User>> getFriends() async => friends;

  @override
  Future<List<FriendshipRequest>> getSentFriendRequests() async => sentRequests;

  @override
  Future<FriendshipRequest> sendFriendRequest(String userId) async {
    sentFriendRequestIds.add(userId);
    final target = User(
      id: userId,
      username: 'target$userId',
      email: 'target$userId@test.com',
      displayName: '成员$userId',
      createdAt: DateTime.parse('2024-01-01T10:00:00'),
    );
    return FriendshipRequest(
      id: 'request-$userId',
      status: 'PENDING',
      user: User(
        id: '1',
        username: 'me',
        email: 'me@test.com',
        displayName: '我',
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
      friend: target,
    );
  }

  @override
  Future<Chat> createPrivateChat(String userId) async {
    createdPrivateChatUserIds.add(userId);
    final chat = privateChatsByUserId[userId];
    if (chat != null) return chat;
    final now = DateTime.parse('2024-01-01T10:00:00');
    return Chat(
      id: 'private-$userId',
      name: '成员$userId',
      type: ChatType.private,
      createdAt: now,
      participants: [
        User(
          id: '1',
          username: 'me',
          email: 'me@test.com',
          displayName: '我',
          createdAt: now,
        ),
        User(
          id: userId,
          username: 'target$userId',
          email: 'target$userId@test.com',
          displayName: '成员$userId',
          createdAt: now,
        ),
      ],
    );
  }
}

class _NoSocketAuthService extends AuthService {
  _NoSocketAuthService() : super.test();

  String? _token = 'test-stale-access-token';

  @override
  String? get accessToken => _token;

  @override
  Future<bool> ensureAuthenticated() async => true;

  @override
  Future<bool> refreshAccessToken() async {
    _token = null;
    return false;
  }
}

class _CurrentUserNoSocketAuthService extends AuthService {
  _CurrentUserNoSocketAuthService({required this.userId}) : super.test();

  final String userId;
  String? _token = 'test-stale-access-token';

  @override
  User? get currentUser => User(
        id: userId,
        username: 'me',
        email: 'me@test.com',
        displayName: '我',
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      );

  @override
  String? get accessToken => _token;

  @override
  Future<bool> ensureAuthenticated() async => true;

  @override
  Future<bool> refreshAccessToken() async {
    _token = null;
    return false;
  }
}

class RecordingCallService extends ChatCallService {
  RecordingCallService() : super(webSocketService: WebSocketService());

  int? startedRoomId;
  int? startedPeerUserId;
  CallMediaKind? startedMediaKind;
  String? startedPeerName;

  @override
  Future<void> startOutgoingCall({
    required int chatRoomId,
    required CallMediaKind mediaKind,
    required String peerName,
    int? peerUserId,
  }) async {
    startedRoomId = chatRoomId;
    startedMediaKind = mediaKind;
    startedPeerName = peerName;
    startedPeerUserId = peerUserId;
  }
}

class FixedStateCallService extends ChatCallService {
  FixedStateCallService(this.fixedState)
      : super(webSocketService: WebSocketService());

  final ChatCallState fixedState;

  @override
  ChatCallState get state => fixedState;

  @override
  Future<void> hangUp() async {}
}
