part of '../chat_screen_test.dart';

void _chatScreenCases2() {
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
    await tester.tap(find.byTooltip('房间资料'));
    await tester.pumpAndSettle();

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

    final editable = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('chat-composer-text-field-shell')),
        matching: find.byType(EditableText)));
    expect(editable.controller.text, '@alice ');
  });

  testWidgets('member panel shows presence in Chinese with last seen',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final groupChat = Chat(
      id: 'group1',
      name: 'Presence Room',
      type: ChatType.group,
      createdAt: now,
      participants: [
        User(
          id: '2',
          username: 'alice',
          email: 'alice@test.com',
          displayName: 'Alice',
          onlineStatus: OnlineStatus.away,
          createdAt: now,
        ),
        User(
          id: '3',
          username: 'bob',
          email: 'bob@test.com',
          displayName: 'Bob',
          lastSeen: now.subtract(const Duration(hours: 2)),
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
    await tester.tap(find.byTooltip('房间资料'));
    await tester.pumpAndSettle();

    expect(find.text('离开'), findsOneWidget);
    expect(find.textContaining('最后在线'), findsOneWidget);
    expect(find.text('away'), findsNothing);
    expect(find.text('offline'), findsNothing);
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

  testWidgets('pressing Enter sends message and clears input', (tester) async {
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

  testWidgets('desktop secondary click opens message actions', (tester) async {
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
}
