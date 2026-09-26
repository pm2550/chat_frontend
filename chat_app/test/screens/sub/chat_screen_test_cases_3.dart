part of '../chat_screen_test.dart';

void _chatScreenCases3() {
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
        timestamp:
            DateTime.parse('2024-01-01T10:00:00').add(Duration(minutes: index)),
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

  testWidgets('re-enter replaces a stale cache with the latest server page',
      (tester) async {
    final chat = createTestChat(id: 'stale-cache-room');
    final cachedMessage = Message(
      id: '100',
      content: '缓存里的旧消息',
      senderId: 'user2',
      senderName: '好友',
      chatRoomId: chat.id,
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:00:00'),
    );

    await tester.pumpWidget(buildTestWidget(
      chat,
      chatService: FakeChatDataService(messages: [cachedMessage]),
    ));
    await tester.pumpAndSettle();
    expect(find.text('缓存里的旧消息'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final latestService = FakeChatDataService(messages: [
      cachedMessage,
      Message(
        id: '101',
        content: '服务端最新消息',
        senderId: 'user2',
        senderName: '好友',
        chatRoomId: chat.id,
        status: MessageStatus.sent,
        timestamp: DateTime.parse('2024-01-01T10:01:00'),
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(
      chat,
      chatService: latestService,
    ));
    await tester.pumpAndSettle();

    expect(latestService.messagePageRequestCount, 1);
    expect(latestService.deltaRequestCount, 0);
    expect(find.text('服务端最新消息'), findsOneWidget);
  });

  testWidgets('re-enter anchors refreshed long history to the latest message',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final chat = createTestChat(id: 'stale-long-room');
    final cachedMessages = List<Message>.generate(
      48,
      (index) => Message(
        id: '${200 + index}',
        content: '缓存历史 $index ${'较长内容 ' * 3}',
        senderId: index.isEven ? 'user2' : 'user1',
        senderName: index.isEven ? '好友' : '我',
        chatRoomId: chat.id,
        status: MessageStatus.sent,
        timestamp:
            DateTime.parse('2024-01-01T10:00:00').add(Duration(minutes: index)),
      ),
    );

    await tester.pumpWidget(buildTestWidget(
      chat,
      chatService: FakeChatDataService(messages: cachedMessages),
    ));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(buildTestWidget(
      chat,
      chatService: FakeChatDataService(messages: [
        ...cachedMessages,
        Message(
          id: '248',
          content: '重新进入后的真正最新消息',
          senderId: 'user2',
          senderName: '好友',
          chatRoomId: chat.id,
          status: MessageStatus.sent,
          timestamp: DateTime.parse('2024-01-01T10:48:00'),
        ),
      ]),
    ));
    await tester.pump();
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('chat-message-list')),
    );
    expect(
      list.controller!.position.maxScrollExtent -
          list.controller!.position.pixels,
      lessThanOrEqualTo(2),
    );
    expect(find.text('重新进入后的真正最新消息'), findsOneWidget);
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

  testWidgets('accepting an incoming call keeps the chat open', (tester) async {
    final chat = createTestChat(id: '42', participantId: '7');
    final callService = AnswerableCallService();
    PendingCallInvite.put(incomingInvite('42'));

    await pumpChatOverBase(tester, chat, callService);
    expect(find.text('好友 的语音来电'), findsOneWidget);

    await tester.tap(find.text('接听'));
    await pumpFrames(tester);

    // 行为约束：接听后聊天页必须还在（通话服务挂在聊天页上，页面没了通话就断）。
    // 注意：线上出现过的"弹窗被关两次、把聊天页也弹掉"在这个测试环境里复现不出来，
    // 那次修复是靠真实浏览器新旧版本对照验证的。
    expect(callService.accepted, isTrue);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('BASE PAGE'), findsNothing);
    expect(find.text('好友 的语音来电'), findsNothing);
  });

  testWidgets('rejecting an incoming call keeps the chat open', (tester) async {
    final chat = createTestChat(id: '43', participantId: '7');
    final callService = AnswerableCallService();
    PendingCallInvite.put(incomingInvite('43'));

    await pumpChatOverBase(tester, chat, callService);
    await tester.tap(find.text('拒绝'));
    await pumpFrames(tester);

    expect(callService.rejected, isTrue);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('BASE PAGE'), findsNothing);
  });

  testWidgets('caller cancelling closes only the dialog', (tester) async {
    final chat = createTestChat(id: '44', participantId: '7');
    final callService = AnswerableCallService();
    PendingCallInvite.put(incomingInvite('44'));

    await pumpChatOverBase(tester, chat, callService);
    callService.cancelByCaller();
    await pumpFrames(tester);

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('BASE PAGE'), findsNothing);
    expect(find.text('好友 的语音来电'), findsNothing);
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

  testWidgets('group call status keeps mesh participant limit', (tester) async {
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
    await tester.tap(find.byTooltip('房间资料'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('已是好友'), findsOneWidget);
    expect(find.byTooltip('添加好友'), findsOneWidget);

    await tester.tap(find.byTooltip('添加好友'));
    await tester.pump();
    await tester.pump();

    expect(contactService.sentFriendRequestIds, ['3']);
    expect(find.byTooltip('好友请求已发送'), findsOneWidget);
    expect(find.text('已向 陌生人 发送好友请求'), findsOneWidget);
  });
}
