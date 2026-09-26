import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_e2ee_server.dart';
import '../support/fake_web_socket_channel.dart';
import 'chat_screen_test.dart'
    show FakeBotService, FakeChatDataService, buildTestWidget;

/// 输入框里的 "/" 快捷命令：面板、键盘、发送时执行或改写成 @、加密私聊里禁用 AI。
void main() {
  setUp(ChatScreen.clearMessageCacheForTesting);

  final agent = BotConfig(id: 1, botName: 'Agent', llmProvider: 'HERMES');
  final deployBot = BotConfig(
    id: 2,
    botName: 'deployer',
    roomNickname: 'Deploy Bot',
    llmProvider: 'OPENAI',
    createdById: 9,
    accessPolicy: 'PUBLIC',
  );
  // 只认关键词 "/chat" 的机器人：@ 它不会回，不该出现在面板里，"/chat …" 也要原样发。
  final keywordBot = BotConfig(
    id: 3,
    botName: '阿雷',
    llmProvider: 'OPENAI',
    createdById: 9,
    accessPolicy: 'PUBLIC',
    triggerMode: 'KEYWORD',
    triggerKeywords: '/chat',
  );
  // 别人的私有机器人：服务器不会让我触发。
  final privateBot = BotConfig(
    id: 4,
    botName: 'Secret Bot',
    llmProvider: 'OPENAI',
    createdById: 9,
  );

  Chat groupChat() {
    final now = DateTime.parse('2024-01-01T10:00:00');
    return Chat(
      id: '42',
      name: 'Slash Room',
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
  }

  final composerShell =
      find.byKey(const ValueKey('chat-composer-text-field-shell'));
  final composer =
      find.descendant(of: composerShell, matching: find.byType(EditableText));
  final composerField =
      find.descendant(of: composerShell, matching: find.byType(TextField));

  Future<_ImageRecordingChatService> pumpGroup(
    WidgetTester tester, {
    List<BotConfig>? bots,
    AuthService? authService,
  }) async {
    final service = _ImageRecordingChatService();
    await tester.pumpWidget(buildTestWidget(
      groupChat(),
      chatService: service,
      authService: authService,
      botService: FakeBotService(
          roomBots: bots ?? [agent, deployBot, keywordBot, privateBot]),
    ));
    await tester.pump();
    await tester.pump();
    await tester.tap(composerField);
    return service;
  }

  String composerText(WidgetTester tester) =>
      tester.widget<EditableText>(composer).controller.text;

  final panel = find.byKey(const ValueKey('slash-command-panel'));
  final drawHint = find.byKey(const ValueKey('slash-draw-hint'));

  testWidgets('typing / opens the command panel and typing more filters it',
      (tester) async {
    await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    expect(panel, findsOneWidget);
    for (final name in ['/画图', '/问', '/Deploy Bot', '/投票', '/位置']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('AI 画图 · 每天免费 3 次，之后每次 10 积分'), findsOneWidget);
    expect(find.text('问 AI 助手（能联网搜索、看本群记录）'), findsOneWidget);
    expect(find.text('召唤机器人'), findsOneWidget);
    // 内置 Agent 由 /问 覆盖；关键词机器人和别人的私有机器人不列。
    expect(find.text('/Agent'), findsNothing);
    expect(find.text('/阿雷'), findsNothing);
    expect(find.text('/Secret Bot'), findsNothing);

    await tester.enterText(find.byType(TextField), '/huat');
    await tester.pump();
    expect(find.text('/画图'), findsOneWidget);
    expect(find.text('/问'), findsNothing);

    await tester.enterText(find.byType(TextField), '/ask');
    await tester.pump();
    expect(find.text('/问'), findsOneWidget);
    expect(find.text('/画图'), findsNothing);

    await tester.enterText(find.byType(TextField), '/depl');
    await tester.pump();
    expect(find.text('/Deploy Bot'), findsOneWidget);
    expect(find.text('/投票'), findsNothing);

    await tester.enterText(find.byType(TextField), '/chat');
    await tester.pump();
    expect(panel, findsNothing);

    // 不在消息开头的 / 不弹。
    await tester.enterText(find.byType(TextField), '你好 /');
    await tester.pump();
    expect(panel, findsNothing);
  });

  testWidgets('desktop input bar shows the panel and sends /画图 too',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final service = await pumpGroup(tester);
    expect(find.text('Enter 发送 · Shift + Enter 换行'), findsOneWidget);
    expect(find.text('输入消息，/ 调用 AI'), findsOneWidget);

    await tester.enterText(composerField, '/dr');
    await tester.pump();
    expect(panel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(composerText(tester), '/画图 ');

    await tester.enterText(composerField, '/画图 山水画');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(service.imagePrompts, ['山水画']);
    expect(service.sentTexts, isEmpty);
  });

  testWidgets('my own private bot gets a command', (tester) async {
    await pumpGroup(tester, authService: SocketAuthService(userId: '9'));

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    expect(find.text('/Secret Bot'), findsOneWidget);
  });

  testWidgets('arrow keys move, Enter chooses, Esc closes', (tester) async {
    await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(panel, findsNothing);
    expect(composerText(tester), '/');

    await tester.enterText(find.byType(TextField), '');
    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    expect(panel, findsOneWidget);
    // ↑ 从第一个绕到最后一个（/位置），再 ↓ 回到第一个（/画图），再 ↓ 到 /问。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(composerText(tester), '@Agent ');
    expect(panel, findsNothing);
  });

  testWidgets('Tab chooses /画图 and shows the drawing hint', (tester) async {
    final service = await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/hua');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(composerText(tester), '/画图 ');
    final selection =
        tester.widget<EditableText>(composer).controller.selection;
    expect(selection.baseOffset, '/画图 '.length);
    expect(panel, findsNothing);
    expect(drawHint, findsOneWidget);
    expect(service.sentTexts, isEmpty);
  });

  testWidgets('tapping /问 inserts the system Agent mention', (tester) async {
    final service = await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/wen');
    await tester.pump();
    await tester.tap(find.text('/问'));
    await tester.pump();

    expect(composerText(tester), '@Agent ');
    expect(service.sentTexts, isEmpty);
  });

  testWidgets('tapping a bot command inserts its mention', (tester) async {
    await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    await tester.tap(find.text('/Deploy Bot'));
    await tester.pump();

    expect(composerText(tester), '@Deploy Bot ');
  });

  testWidgets('typed "/问 …" and "/<bot> …" are sent as mentions',
      (tester) async {
    final service = await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/问 今天天气怎么样');
    await tester.pump();
    expect(panel, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '/Deploy Bot 发布一下');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(service.sentTexts, ['@Agent 今天天气怎么样', '@Deploy Bot 发布一下']);
  });

  testWidgets('"/画图 猫" generates an image and sends no text', (tester) async {
    final service = await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/画图 一只橘猫');
    await tester.pump();
    expect(drawHint, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(service.imagePrompts, ['一只橘猫']);
    expect(service.sentTexts, isEmpty);
    expect(composerText(tester), isEmpty);
    expect(drawHint, findsNothing);
  });

  testWidgets('"/画图" without a prompt asks for one and sends nothing',
      (tester) async {
    final service = await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/画图 ');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();

    expect(find.text('在 /画图 后面写上想画什么'), findsOneWidget);
    expect(service.imagePrompts, isEmpty);
    expect(service.sentTexts, isEmpty);
    expect(composerText(tester), '/画图 ');
  });

  testWidgets('unknown "/chat hi" is sent verbatim for keyword bots',
      (tester) async {
    final service = await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/chat hi');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(service.sentTexts, ['/chat hi']);
    expect(service.imagePrompts, isEmpty);
  });

  testWidgets('/投票 opens the poll sheet and clears the command',
      (tester) async {
    final service = await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '/toupiao');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('发起投票'), findsOneWidget);
    expect(composerText(tester), isEmpty);
    expect(service.sentTexts, isEmpty);
  });

  testWidgets('the @ mention panel still works and never shows with /',
      (tester) async {
    await pumpGroup(tester);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    expect(find.text('Alice'), findsWidgets);
    expect(panel, findsNothing);

    // 两个面板互斥：弹着命令面板时没有成员面板；"/@" 不是命令，只弹成员面板。
    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    expect(panel, findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    await tester.enterText(find.byType(TextField), '/@');
    await tester.pump();
    expect(panel, findsNothing);
    expect(find.text('Alice'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'hi @al');
    await tester.pump();
    expect(panel, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(composerText(tester), 'hi @alice ');
  });

  group('end-to-end encrypted private chat', () {
    late FakeE2eeServer server;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      server = FakeE2eeServer()
        ..passwords['user1'] = 'me-pw'
        ..passwords['user2'] = 'friend-pw'
        ..roomMembers['1'] = ['user1', 'user2'];
    });

    tearDown(() => Message.contentRevealer = null);

    Future<(FakeWebSocketChannel, WebSocketService, _ImageRecordingChatService)>
        pumpEncrypted(WidgetTester tester) async {
      final me = e2eeDevice(server, 'user1');
      await tester.runAsync(() async {
        await me.enable('me-pw');
        await e2eeDevice(server, 'user2').enable('friend-pw');
      });
      Message.contentRevealer = me.reveal;
      final channel = FakeWebSocketChannel();
      final socket = WebSocketService.forTesting(
        authService: SocketAuthService(),
        channelFactory: (_) => channel,
      );
      final service = _ImageRecordingChatService();
      final chat = Chat(
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
            createdAt: DateTime.parse('2024-01-01T09:00:00'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp(
        home: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute(
            settings: RouteSettings(arguments: chat),
            builder: (context) => ChatScreen(
              chatService: service,
              authService: SocketAuthService(),
              webSocketService: socket,
              encryptionService: me,
              botService: FakeBotService(roomBots: [agent]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('e2ee-header-badge')), findsOneWidget);
      return (channel, socket, service);
    }

    Future<void> finish(WidgetTester tester, WebSocketService socket) async {
      socket.disconnect();
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('AI commands are disabled and typed ones are refused',
        (tester) async {
      final (channel, socket, service) = await pumpEncrypted(tester);

      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      expect(panel, findsOneWidget);
      expect(find.text('端到端加密的私聊里不能用 AI'), findsNWidgets(2));
      await tester.tap(find.text('/问'));
      await tester.pump();
      expect(composerText(tester), '/');
      expect(find.text('端到端加密的私聊里不能用 AI'), findsWidgets);

      await tester.enterText(find.byType(TextField), '/画图 我们的秘密');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(service.imagePrompts, isEmpty);
      expect(composerText(tester), '/画图 我们的秘密');

      await tester.enterText(find.byType(TextField), '/问 我们的秘密');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
          channel.sent.where((frame) => frame['type'] == 'message'), isEmpty);
      expect(service.sentTexts, isEmpty);
      expect(composerText(tester), '/问 我们的秘密');
      await finish(tester, socket);
    });

    testWidgets('"更多工具 → AI 图片" is blocked too', (tester) async {
      final (_, socket, service) = await pumpEncrypted(tester);

      await tester.tap(find.byTooltip('更多工具'));
      await tester.pumpAndSettle();
      expect(find.text('端到端加密的私聊里不能用 AI'), findsOneWidget);
      await tester.tap(find.text('AI 图片'));
      await tester.pumpAndSettle();

      expect(find.text('AI 图片生成'), findsNothing);
      expect(find.text('端到端加密的私聊里不能用 AI'), findsOneWidget);
      expect(service.imagePrompts, isEmpty);
      await finish(tester, socket);
    });
  });
}

class _ImageRecordingChatService extends FakeChatDataService {
  _ImageRecordingChatService() : super(messages: const []);

  final List<String> imagePrompts = [];

  @override
  Future<Message> generateImageMessage(
    String chatRoomId, {
    required String prompt,
    String size = '1024*1024',
    bool expand = true,
  }) async {
    imagePrompts.add(prompt);
    return Message(
      id: 'image-gen-1',
      content: prompt,
      senderId: 'user1',
      senderName: '我',
      chatRoomId: chatRoomId,
      type: MessageType.imageGeneration,
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
      imageGenPrompt: prompt,
      imageGenStatus: 'QUEUED',
    );
  }
}
