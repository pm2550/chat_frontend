import 'dart:async';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/constants/app_colors.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/chat_list_page.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/desktop_notification_service.dart';
import 'package:chat_app/services/desktop_notification_stub.dart';
import 'package:chat_app/services/notification_tap_router.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/user_profile_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget buildTestWidget(
    ChatDataService service, {
    FakeRealtimeService? realtimeService,
    DesktopNotificationService? notificationService,
    String currentUserId = 'me',
  }) {
    return MaterialApp(
      routes: {
        '/chat': (context) => const Scaffold(body: Text('Chat Page')),
      },
      home: ChatListPage(
        chatService: service,
        realtimeService: realtimeService ?? FakeRealtimeService(),
        notificationService: notificationService,
        currentUserId: currentUserId,
      ),
    );
  }

  group('ChatListPage', () {
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

      expect(find.text('暂无聊天记录'), findsOneWidget);
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
        return widget is CircleAvatar &&
            widget.backgroundImage is NetworkImage &&
            (widget.backgroundImage as NetworkImage).url ==
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

    testWidgets(
        'edits refresh the preview without unread count or notification',
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

    testWidgets('web keeps notifications to the chat list route',
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

    testWidgets('desktop header hides the notification button when unsupported',
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
      expect(find.text('通知'), findsOneWidget);

      await pumpWith(false);
      expect(find.text('通知'), findsNothing);
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

    testWidgets('updates participant online status from realtime status event',
        (tester) async {
      final realtime = FakeRealtimeService();
      final service = FakeChatListService(chats: [
        Chat(
          id: '1',
          name: '私聊',
          type: ChatType.private,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
          participants: [
            User(
              id: 'alice',
              username: 'alice',
              email: 'alice@test.com',
              displayName: 'Alice',
              onlineStatus: OnlineStatus.offline,
              createdAt: DateTime.parse('2024-01-01T10:00:00'),
            ),
          ],
        ),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        realtimeService: realtime,
      ));
      await tester.pump();

      expect(find.byWidgetPredicate((widget) {
        return widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle &&
            (widget.decoration as BoxDecoration).color == AppColors.online;
      }), findsNothing);

      realtime.emitStatus({
        'type': 'status',
        'userId': 'alice',
        'onlineStatus': 'ONLINE',
      });
      await tester.pump();

      expect(find.byWidgetPredicate((widget) {
        return widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle &&
            (widget.decoration as BoxDecoration).color == AppColors.online;
      }), findsOneWidget);
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
        return widget is CircleAvatar &&
            widget.backgroundImage is NetworkImage &&
            (widget.backgroundImage as NetworkImage).url ==
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

      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      // 直接套用推送里的状态，不用再整页刷新。
      expect(service.forceRefreshRequests.length, loadsBefore);
    });

    testWidgets('room hidden on another device leaves this list',
        (tester) async {
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
  });
}

class FakeChatListService extends ChatDataService {
  FakeChatListService({
    this.chats = const [],
    this.mentionedMessages = const {},
    this.error,
  }) : super(authenticatedRequest: _unusedRequest);

  List<Chat> chats;
  final Map<String, List<Message>> mentionedMessages;
  final Object? error;
  final List<String> loadedMentionRoomIds = [];
  final List<String> clearedRoomIds = [];
  final List<String> hiddenRoomIds = [];
  final List<String> blockedRoomIds = [];
  final List<String> pinnedRoomIds = [];
  final List<bool> forceRefreshRequests = [];

  static Future<dynamic> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
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
    forceRefreshRequests.add(forceRefresh);
    final err = error;
    if (err != null) {
      throw err;
    }
    return chats;
  }

  @override
  Future<MessagePage> getMentionedMessages(
    String chatRoomId, {
    int page = 0,
    int size = 20,
  }) async {
    loadedMentionRoomIds.add(chatRoomId);
    final messages = mentionedMessages[chatRoomId] ?? const <Message>[];
    return MessagePage(
      messages: messages,
      currentPage: page,
      totalPages: messages.isEmpty ? 0 : 1,
      totalElements: messages.length,
      hasNext: false,
      hasPrevious: false,
    );
  }

  @override
  Future<void> clearChatHistory(String chatRoomId) async {
    clearedRoomIds.add(chatRoomId);
  }

  @override
  Future<void> hideChatRoom(String chatRoomId) async {
    hiddenRoomIds.add(chatRoomId);
  }

  @override
  Future<void> blockChatRoom(String chatRoomId) async {
    blockedRoomIds.add(chatRoomId);
  }

  @override
  Future<Map<String, dynamic>> updateNotificationSettings(
    String chatRoomId, {
    bool? muted,
    bool? pinned,
  }) async {
    if (pinned == true) {
      pinnedRoomIds.add(chatRoomId);
    }
    return {'pinned': pinned ?? false, 'muted': muted ?? false};
  }
}

class FakeRealtimeService implements ChatRealtimeService {
  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final StreamController<Message> _messageUpdateController =
      StreamController<Message>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _statusController =
      StreamController<Map<String, dynamic>>.broadcast();

  int connectCalls = 0;
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<Message> get onMessage => _messageController.stream;

  @override
  Stream<Message> get onMessageUpdated => _messageUpdateController.stream;

  @override
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;

  @override
  Stream<Map<String, dynamic>> get onStatusChange => _statusController.stream;

  @override
  Future<void> connect() async {
    connectCalls += 1;
    _isConnected = true;
  }

  @override
  void disconnect() {
    _isConnected = false;
  }

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

  void emitMessage(Message message) {
    _messageController.add(message);
  }

  void emitMessageUpdate(Message message) {
    _messageUpdateController.add(message);
  }

  void emitStatus(Map<String, dynamic> status) {
    _statusController.add(status);
  }
}
