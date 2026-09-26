part of '../chat_screen_test.dart';

void _chatScreenCases1() {
  testWidgets('renders private peer display name in app bar', (tester) async {
    final chat = createTestChat(name: '李四');

    await tester.pumpWidget(buildTestWidget(chat));
    await tester.pump();

    expect(find.descendant(of: find.byType(AppBar), matching: find.text('好友')),
        findsOneWidget);
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
        timestamp:
            DateTime.parse('2024-01-01T10:00:00').add(Duration(minutes: index)),
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
        timestamp:
            DateTime.parse('2024-01-01T10:00:00').add(Duration(minutes: index)),
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

  testWidgets('resume reconnects and fetches messages missed while suspended',
      (tester) async {
    final messages = <Message>[...testMessages];
    final service = FakeChatDataService(messages: messages);

    await tester.pumpWidget(buildTestWidget(
      createTestChat(),
      chatService: service,
    ));
    await tester.pumpAndSettle();
    expect(find.text('后台期间的新消息'), findsNothing);

    messages.add(Message(
      id: '3',
      content: '后台期间的新消息',
      senderId: 'user2',
      senderName: '好友',
      chatRoomId: 'chat1',
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
    ));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(service.deltaRequestCount, 1);
    expect(find.text('后台期间的新消息'), findsOneWidget);
  });

  testWidgets('visible chat periodically reconciles a missed websocket frame',
      (tester) async {
    final messages = <Message>[...testMessages];
    final service = FakeChatDataService(messages: messages);

    await tester.pumpWidget(buildTestWidget(
      createTestChat(),
      chatService: service,
    ));
    await tester.pumpAndSettle();
    messages.add(Message(
      id: '3',
      content: '校准补回的新消息',
      senderId: 'user2',
      senderName: '好友',
      chatRoomId: 'chat1',
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
    ));

    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();

    expect(service.deltaRequestCount, 1);
    expect(find.text('校准补回的新消息'), findsOneWidget);
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

  testWidgets('first composer focus remains visible when keyboard opens',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(buildTestWidget(
      createTestChat(id: '42'),
      chatService: FakeChatDataService(messages: const []),
    ));
    await tester.pump();

    await tester.tap(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();

    final shellFinder =
        find.byKey(const ValueKey('chat-composer-text-field-shell'));
    final shellRect = tester.getRect(shellFinder);
    const keyboardTop = 844 - 250;
    expect(shellRect.top, greaterThanOrEqualTo(0));
    expect(shellRect.bottom, lessThanOrEqualTo(keyboardTop + 4));
    expect(shellRect.height, greaterThan(36));
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

  testWidgets('375px composer exposes primary tools and separates attachments',
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

    expect(find.byTooltip('更多工具'), findsOneWidget);
    expect(find.byTooltip('表情'), findsOneWidget);
    expect(find.byTooltip('贴纸'), findsOneWidget);
    expect(find.byTooltip('插入 AI 助手'), findsOneWidget);

    await tester.tap(find.byTooltip('附件'));
    await tester.pumpAndSettle();

    for (final label in [
      '拍照',
      '相册',
      '文件',
      '语音文件',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    final shellWidth = tester
        .getSize(find.byKey(const ValueKey('chat-composer-text-field-shell')))
        .width;
    expect(shellWidth, greaterThanOrEqualTo(180));
  });

  testWidgets('375px toolbar launches emoji panel', (tester) async {
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

    await tester.tap(find.byTooltip('表情'));
    await tester.pumpAndSettle();

    expect(find.byType(EmojiPicker), findsOneWidget);
  });

  testWidgets('375px toolbar launches sticker panel', (tester) async {
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

    await tester.tap(find.byTooltip('贴纸'));
    await tester.pumpAndSettle();

    expect(find.text('暂无贴纸包'), findsOneWidget);
  });

  testWidgets('375px toolbar inserts system Agent mention without sending',
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

    await tester.tap(find.byTooltip('插入 AI 助手'));
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

    expect(find.byTooltip('更多工具'), findsOneWidget);

    await tester.tap(find.byTooltip('更多工具'));
    await tester.pumpAndSettle();

    for (final label in [
      'AI 图片',
      '位置',
      '投票',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets(
      '414px composer keeps emoji accessible when usable width is tight',
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

    expect(find.byTooltip('更多工具'), findsOneWidget);
    expect(find.byTooltip('表情'), findsOneWidget);
    expect(find.byTooltip('贴纸'), findsOneWidget);
    expect(find.byTooltip('插入 AI 助手'), findsOneWidget);

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
    expect(find.textContaining('没有找到这段对话'), findsOneWidget);
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
}
