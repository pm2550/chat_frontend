part of '../chat_list_page_test.dart';

void _chatListCases2() {
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

  testWidgets(
      'lists only group chats; private unread and notices still count',
      (tester) async {
    final realtime = FakeRealtimeService();
    final backend = StubDesktopNotificationBackend(
      supported: true,
      permissionGranted: true,
      visible: false,
    );
    final alice = User(
      id: 'alice',
      username: 'alice',
      email: 'alice@test.com',
      displayName: 'Alice',
      createdAt: DateTime.parse('2024-01-01T10:00:00'),
    );
    final service = FakeChatListService(chats: [
      Chat(
        id: 'g1',
        name: '项目群',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
        unreadCount: 2,
      ),
      Chat(
        id: 'c1',
        name: '公告频道',
        type: ChatType.channel,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
      Chat(
        id: 'p1',
        name: 'Me & Alice',
        type: ChatType.private,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
        participants: [alice],
        unreadCount: 3,
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(
      service,
      realtimeService: realtime,
      notificationService: DesktopNotificationService(backend: backend),
    ));
    await tester.pumpAndSettle();

    expect(find.text('项目群'), findsOneWidget);
    expect(find.text('公告频道'), findsOneWidget);
    expect(find.text('Me & Alice'), findsNothing);
    expect(find.text('Alice'), findsNothing);
    // "未读"只数消息页里的群聊 / 频道。
    expect(find.text('未读 2'), findsOneWidget);
    // 系统 / 桌面角标两边都算。
    expect(backend.lastUnreadCount, 5);

    realtime.emitMessage(Message(
      id: 'pm-1',
      content: '私聊新消息',
      senderId: 'alice',
      senderName: 'Alice',
      chatRoomId: 'p1',
      timestamp: DateTime.parse('2024-01-01T10:05:00'),
    ));
    await tester.pump();

    expect(backend.lastUnreadCount, 6);
    expect(find.text('未读 2'), findsOneWidget);
    expect(find.text('私聊新消息'), findsNothing);
    // 私聊的提醒标题是对方的名字，不是 "A & B"。
    expect(backend.shownNotifications.single.title, 'Alice');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Alice: 私聊新消息'), findsOneWidget);
    // 认识的私聊来消息不会让消息页整页重拉。
    expect(service.forceRefreshRequests, [false]);
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
      return widget is Image &&
          widget.image is NetworkImage &&
          (widget.image as NetworkImage).url ==
              ApiConstants.resolveFileUrl('/api/files/avatar/new-group.png');
    }), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
  });

  testWidgets(
      'room_display_state_changed from another device applies pin and mute',
      (tester) async {
    final realtime = FakeRealtimeService();
    final service = FakeChatListService(chats: [
      Chat(
        id: '1',
        name: '多端会话',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(
      service,
      realtimeService: realtime,
    ));
    await tester.pump();
    expect(find.byIcon(Icons.volume_off), findsNothing);
    final loadsBefore = service.forceRefreshRequests.length;

    realtime.emitStatus({
      'type': 'room_display_state_changed',
      'chatRoomId': 1,
      'state': {
        'roomId': 1,
        'pinned': true,
        'muted': true,
        'isHidden': false,
        'isBlocked': false,
        'unreadCount': 0,
      },
    });
    await tester.pump();

    expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);
    // 直接套用推送里的状态，不用再整页刷新。
    expect(service.forceRefreshRequests.length, loadsBefore);
  });

  testWidgets('room hidden on another device leaves this list', (tester) async {
    final realtime = FakeRealtimeService();
    final service = FakeChatListService(chats: [
      Chat(
        id: '1',
        name: '别处隐藏',
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
      'type': 'room_display_state_changed',
      'chatRoomId': 1,
      'state': {'roomId': 1, 'isHidden': true, 'hiddenAt': '2024-01-02'},
    });
    await tester.pump();

    expect(find.text('别处隐藏'), findsNothing);
  });

  testWidgets('reading a room on another device clears its unread badge',
      (tester) async {
    final realtime = FakeRealtimeService();
    final service = FakeChatListService(chats: [
      Chat(
        id: '1',
        name: '未读会话',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
        unreadCount: 7,
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(
      service,
      realtimeService: realtime,
    ));
    await tester.pump();
    expect(find.text('7'), findsOneWidget);

    // 别人读了不影响我的未读数。
    realtime.emitStatus({
      'type': 'read_receipt',
      'chatRoomId': 1,
      'userId': 'someone-else',
      'lastReadMessageId': 99,
    });
    await tester.pump();
    expect(find.text('7'), findsOneWidget);

    realtime.emitStatus({
      'type': 'read_receipt',
      'chatRoomId': 1,
      'userId': 'me',
      'lastReadMessageId': 99,
      'unreadCount': 0,
    });
    await tester.pump();
    await tester.pump();

    expect(find.text('7'), findsNothing);
  });

  testWidgets('being removed from a room drops it from the list',
      (tester) async {
    final realtime = FakeRealtimeService();
    final service = FakeChatListService(chats: [
      Chat(
        id: '1',
        name: '被踢的群',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
      Chat(
        id: '2',
        name: '还在的群',
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
      'type': 'room_membership_removed',
      'chatRoomId': 1,
      'reason': 'kicked',
    });
    await tester.pump();

    expect(find.text('被踢的群'), findsNothing);
    expect(find.text('还在的群'), findsOneWidget);
  });

  testWidgets('being added to a room reloads the list from the server',
      (tester) async {
    final realtime = FakeRealtimeService();
    final service = FakeChatListService(chats: [
      Chat(
        id: '1',
        name: '旧群',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
    ]);

    await tester.pumpWidget(buildTestWidget(
      service,
      realtimeService: realtime,
    ));
    await tester.pump();

    service.chats = [
      ...service.chats,
      Chat(
        id: '2',
        name: '新拉进的群',
        type: ChatType.group,
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
    ];
    realtime.emitStatus({
      'type': 'room_membership_added',
      'chatRoomId': 2,
    });
    await tester.pump();
    await tester.pump();

    expect(service.forceRefreshRequests.last, isTrue);
    expect(find.text('新拉进的群'), findsOneWidget);
  });

  testWidgets('room_updated applies renamed title and member count',
      (tester) async {
    final realtime = FakeRealtimeService();
    final service = FakeChatListService(chats: [
      Chat(
        id: '1',
        name: '旧群名',
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
        'name': '新群名',
        'roomType': 'GROUP',
        'memberCount': 3,
      },
    });
    await tester.pump();

    expect(find.text('新群名'), findsOneWidget);
    expect(find.text('旧群名'), findsNothing);
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
}
