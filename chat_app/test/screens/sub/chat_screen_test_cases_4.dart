part of '../chat_screen_test.dart';

void _chatScreenCases4() {
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
    await tester.tap(find.byTooltip('房间资料'));
    await tester.pumpAndSettle();

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

  testWidgets('picked image waits in the send strip until 发送 is pressed',
      (tester) async {
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
    await tester.pump();

    // 和微信一样：选好的图先停在发送栏，按发送键才发。
    expect(service.sentFiles, isEmpty);
    expect(find.byKey(const ValueKey('chat-pending-attachment-0')),
        findsOneWidget);
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump();

    expect(service.sentFiles.single.name, 'photo.png');
    expect(service.sentFiles.single.mimeType, 'image/png');
    expect(find.byType(MessageBubble), findsOneWidget);
    expect(find.text('photo.png'), findsNothing);
  });

  testWidgets('dragging files over chat shows upload overlay', (tester) async {
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

  testWidgets(
      'desktop Ctrl+V queues a clipboard image and plain text still pastes',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    );
    Uint8List? clipboardImage = png;
    var clipboardText = '';
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'),
        (call) async {
      if (call.method == 'files') return <String>[];
      if (call.method == 'image') return clipboardImage;
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': clipboardText};
      }
      if (call.method == 'Clipboard.hasStrings') {
        return {'value': clipboardText.isNotEmpty};
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel('pasteboard'), null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final chat = createTestChat();
    final service = FakeChatDataService(messages: const []);
    await tester.pumpWidget(buildTestWidget(chat, chatService: service));
    await tester.pump();
    await tester.tap(find.byType(TextField).last);
    await tester.pump();

    Future<void> pressPaste() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await pressPaste();
    // 图片进待发送栏，不直接发出去，输入框里也没多出文字。
    expect(find.byKey(const ValueKey('chat-pending-attachment-0')),
        findsOneWidget);
    expect(service.sentFiles, isEmpty);

    clipboardImage = null;
    clipboardText = '一段普通文字';
    await pressPaste();
    expect(
        find.byKey(const ValueKey('chat-pending-attachment-1')), findsNothing);
    expect(find.text('一段普通文字'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
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

    // 失败的附件留在发送端的上传气泡里：写明原因，可以重试或移除。
    expect(find.text('doc.pdf'), findsOneWidget);
    expect(find.text('发送失败：upload down'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);
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
}
