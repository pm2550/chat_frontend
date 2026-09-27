part of '../chat_list_page_test.dart';

void _chatListCases1() {
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

    expect(find.text('暂无聊天'), findsOneWidget);
    // 没有右下角按钮了：空状态指向"发起聊天"和联系人。
    expect(find.textContaining('右下角'), findsNothing);
    expect(find.textContaining('「联系人」'), findsOneWidget);
  });

  testWidgets('sorts loaded rooms by latest known message time',
      (tester) async {
    final service = FakeChatListService(chats: [
      Chat(
        id: 'old',
        name: '旧会话',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
        lastMessage: Message(
          id: 'old-msg',
          content: '旧消息',
          senderId: '2',
          senderName: 'Alice',
          chatRoomId: 'old',
          timestamp: DateTime.parse('2024-01-01T10:01:00'),
        ),
      ),
      Chat(
        id: 'new',
        name: '新会话',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
        lastMessage: Message(
          id: 'new-msg',
          content: '新消息',
          senderId: '3',
          senderName: 'Bob',
          chatRoomId: 'new',
          timestamp: DateTime.parse('2024-01-01T10:09:00'),
        ),
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(service));
    await tester.pump();

    final newTop = tester.getTopLeft(find.text('新会话'));
    final oldTop = tester.getTopLeft(find.text('旧会话'));
    expect(newTop.dy, lessThan(oldTop.dy));
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
      return widget is Image &&
          widget.image is NetworkImage &&
          (widget.image as NetworkImage).url ==
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

  testWidgets('foreground resume forces a fresh room summary request',
      (tester) async {
    final service = FakeChatListService(chats: [
      Chat(
        id: '1',
        name: '恢复测试群聊',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(service));
    await tester.pump();
    expect(service.forceRefreshRequests, [false]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(service.forceRefreshRequests, [false, true]);
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

  testWidgets('global message notification switch off suppresses notices',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(UserSettingsCache.clear);
    addTearDown(() => AuthService().clearLocalSession());
    final realtime = FakeRealtimeService();
    final backend = StubDesktopNotificationBackend(
      supported: true,
      permissionGranted: true,
      visible: false,
    );
    final service = FakeChatListService(chats: [
      Chat(
        id: '1',
        name: '通知群聊',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
    ]);
    final profileService = UserProfileService(
      authService: AuthService(),
      authenticatedRequest: (method, url, {headers, body}) async =>
          http.Response(
        jsonEncode({
          'success': true,
          'data': {'messageNotificationsEnabled': false},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await AuthService().replaceCurrentUser(User(
      id: 'me',
      username: 'me',
      email: 'me@example.com',
      displayName: '我',
      createdAt: DateTime.parse('2024-01-01T00:00:00'),
    ));

    await tester.pumpWidget(MaterialApp(
      home: ChatListPage(
        chatService: service,
        realtimeService: realtime,
        notificationService: DesktopNotificationService(backend: backend),
        profileService: profileService,
        currentUserId: 'me',
      ),
    ));
    await tester.pump();

    realtime.emitMessage(Message(
      id: 'm-quiet',
      content: '不该弹通知',
      senderId: 'alice',
      senderName: 'Alice',
      chatRoomId: '1',
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
    ));
    await tester.pump();

    expect(find.text('不该弹通知'), findsOneWidget);
    expect(backend.lastUnreadCount, 1);
    expect(backend.shownNotifications, isEmpty);
    expect(find.text('通知群聊: 不该弹通知'), findsNothing);
  });

  testWidgets('edits refresh the preview without unread count or notification',
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
        name: '编辑群聊',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
        lastMessage: Message(
          id: 'm1',
          content: '原来的内容',
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
      notificationService: notificationService,
    ));
    await tester.pump();

    realtime.emitMessageUpdate(Message(
      id: 'm1',
      content: '改过的内容',
      senderId: 'alice',
      senderName: 'Alice',
      chatRoomId: '1',
      timestamp: DateTime.parse('2024-01-01T10:01:00'),
    ));
    // 更早的一条被编辑：连预览都不该动。
    realtime.emitMessageUpdate(Message(
      id: 'm0',
      content: '更早的消息被改了',
      senderId: 'alice',
      senderName: 'Alice',
      chatRoomId: '1',
      timestamp: DateTime.parse('2024-01-01T09:00:00'),
    ));
    await tester.pump();

    expect(find.text('改过的内容'), findsOneWidget);
    expect(find.text('更早的消息被改了'), findsNothing);
    expect(backend.lastUnreadCount, 0);
    expect(backend.shownNotifications, isEmpty);
  });

  testWidgets('native desktop notifies from inside a chat with a tap payload',
      (tester) async {
    final realtime = FakeRealtimeService();
    final backend = StubDesktopNotificationBackend(
      supported: true,
      permissionGranted: true,
      visible: false,
      notifiesInsideChat: true,
    );
    final notificationService = DesktopNotificationService(backend: backend);
    final service = FakeChatListService(chats: [
      Chat(
        id: '17',
        name: '后台群聊',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(
      service,
      realtimeService: realtime,
      notificationService: notificationService,
    ));
    await tester.pump();
    // 打开一个聊天页，会话列表不再是当前路由。
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/chat');
    await tester.pumpAndSettle();

    realtime.emitMessage(Message(
      id: 'm-bg',
      content: '窗口在后台时来的消息',
      senderId: 'alice',
      senderName: 'Alice',
      chatRoomId: '17',
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
    ));
    await tester.pump();

    expect(backend.shownNotifications, hasLength(1));
    final shown = backend.shownNotifications.single;
    expect(shown.title, '后台群聊');
    expect(NotificationTapRouter.routeForPayload(shown.payload), '/chat/17');
    // 聊天页上不弹会话列表的 SnackBar。
    expect(find.text('后台群聊: 窗口在后台时来的消息'), findsNothing);
  });

  testWidgets('web keeps notifications to the chat list route', (tester) async {
    final realtime = FakeRealtimeService();
    final backend = StubDesktopNotificationBackend(
      supported: true,
      permissionGranted: true,
      visible: false,
    );
    final notificationService = DesktopNotificationService(backend: backend);
    final service = FakeChatListService(chats: [
      Chat(
        id: '17',
        name: '后台群聊',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(
      service,
      realtimeService: realtime,
      notificationService: notificationService,
    ));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/chat');
    await tester.pumpAndSettle();

    realtime.emitMessage(Message(
      id: 'm-bg',
      content: '窗口在后台时来的消息',
      senderId: 'alice',
      senderName: 'Alice',
      chatRoomId: '17',
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
    ));
    await tester.pump();

    expect(backend.shownNotifications, isEmpty);
  });

  testWidgets('message options hide desktop notifications when unsupported',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pumpWith(bool supported) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildTestWidget(
        FakeChatListService(chats: const []),
        notificationService: DesktopNotificationService(
          backend: StubDesktopNotificationBackend(supported: supported),
        ),
      ));
      await tester.pump();
    }

    await pumpWith(true);
    await tester.tap(find.byTooltip('消息选项'));
    await tester.pumpAndSettle();
    expect(find.text('桌面消息通知'), findsOneWidget);

    await pumpWith(false);
    await tester.tap(find.byTooltip('消息选项'));
    await tester.pumpAndSettle();
    expect(find.text('桌面消息通知'), findsNothing);
  });

  testWidgets('does not count own realtime message as unread notification',
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
      currentUserId: 'me',
    ));
    await tester.pump();

    expect(backend.lastUnreadCount, 2);

    realtime.emitMessage(Message(
      id: 'm-own',
      content: '自己发出的消息',
      senderId: 'me',
      senderName: '我',
      chatRoomId: '1',
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
    ));
    await tester.pump();

    expect(find.text('自己发出的消息'), findsOneWidget);
    expect(backend.lastUnreadCount, 2);
    expect(backend.shownNotifications, isEmpty);
    expect(find.text('通知群聊: 自己发出的消息'), findsNothing);
  });

  testWidgets(
      'own anonymous realtime message (sentByMe, no senderId) is not unread',
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
        name: '匿名群聊',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
        unreadCount: 2,
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(
      service,
      realtimeService: realtime,
      notificationService: notificationService,
      currentUserId: 'me',
    ));
    await tester.pump();

    // 匿名消息对外不带 senderId；本人设备收到的那份靠 sentByMe 认出自己。
    realtime.emitMessage(Message.fromJson({
      'id': 'm-anon',
      'content': '我匿名发的',
      'senderId': null,
      'senderName': '匿名淡定羊驼',
      'chatRoomId': '1',
      'createdAt': '2024-01-01T10:02:00',
      'isAnonymous': true,
      'anonymousName': '匿名淡定羊驼',
      'sentByMe': true,
    }));
    await tester.pump();

    expect(find.text('我匿名发的'), findsOneWidget);
    expect(backend.lastUnreadCount, 2);
    expect(backend.shownNotifications, isEmpty);
  });
}
