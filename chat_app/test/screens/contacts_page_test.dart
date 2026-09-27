import 'package:chat_app/constants/app_colors.dart';
import 'package:chat_app/design/design.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/contact_group.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart' show ChatScreenArguments;
import 'package:chat_app/screens/home/contacts_page.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_list_page_test.dart' show FakeRealtimeService;

void main() {
  RouteSettings? openedRoute;

  Widget buildTestWidget(
    ContactDataService service, {
    ChatDataService? chatService,
    FakeRealtimeService? realtimeService,
  }) {
    return MaterialApp(
      onGenerateRoute: (settings) {
        if ((settings.name ?? '').startsWith('/chat')) {
          openedRoute = settings;
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const Scaffold(body: Text('Chat Page')),
          );
        }
        return null;
      },
      home: ContactsPage(
        contactService: service,
        chatService: chatService ?? FakeChatDirectoryService(),
        realtimeService: realtimeService,
        currentUserId: 'me',
      ),
    );
  }

  double rowTop(WidgetTester tester, String userId) =>
      tester.getTopLeft(find.byKey(ValueKey('contact-$userId'))).dy;

  Finder inRow(String userId, Finder matching) => find.descendant(
        of: find.byKey(ValueKey('contact-$userId')),
        matching: matching,
      );

  group('ContactsPage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      openedRoute = null;
    });

    testWidgets('renders friends and received requests from service',
        (tester) async {
      final requester = testUser('2', 'Requester');
      final service = FakeContactService(
        friends: [testUser('1', 'Alice', email: 'alice@example.com')],
        receivedRequests: [
          FriendshipRequest(
            id: '10',
            status: 'PENDING',
            user: requester,
            friend: testUser('9', 'Me'),
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.text('新的好友请求'), findsOneWidget);
      expect(find.text('Requester'), findsOneWidget);
      expect(find.text('联系人'), findsWidgets);
      expect(find.text('Alice'), findsOneWidget);
      // 还没聊过：副标题显示在线状态。邮箱只属于本人，不展示。
      expect(inRow('1', find.text('离线')), findsOneWidget);
      expect(find.text('alice@example.com'), findsNothing);
    });

    testWidgets('renders empty state when there are no contacts',
        (tester) async {
      final service = FakeContactService();

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.text('暂无联系人'), findsOneWidget);
    });

    testWidgets(
        'merges friends and all private chats into one ordered contact list',
        (tester) async {
      tester.view.physicalSize = const Size(600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final alice = testUser('1', 'Alice');
      final bob = testUser('2', 'Bob');
      final carol = testUser('3', 'Carol');
      final dave = testUser('4', 'Dave');
      final service = FakeContactService(friends: [alice, bob]);
      final chatService = FakeChatDirectoryService(
        groupChats: [
          Chat(
            id: '10',
            name: 'Project Group',
            type: ChatType.group,
            isPrivate: false,
            createdAt: DateTime.parse('2024-01-01T10:00:00'),
          ),
        ],
        privateChats: [
          // 好友，有聊天：最后一条消息、未读、免打扰。
          privateChat('p1', alice,
              lastMessage: '明天见',
              at: DateTime.parse('2024-01-01T10:05:00'),
              unreadCount: 3,
              isMuted: true),
          // 非好友，已屏蔽，没有消息。
          privateChat('p3', carol,
              isBlocked: true, hiddenAt: DateTime.parse('2024-01-01T10:00:00')),
          // 非好友，被"移出列表"过、置顶：联系人里照样出现，排在最前。
          privateChat('p4', dave,
              lastMessage: '收到',
              at: DateTime.parse('2024-01-01T10:01:00'),
              isPinned: true,
              hiddenAt: DateTime.parse('2024-01-01T10:02:00')),
        ],
      );

      await tester.pumpWidget(buildTestWidget(
        service,
        chatService: chatService,
      ));
      await tester.pumpAndSettle();

      expect(find.text('我的群聊'), findsOneWidget);
      expect(find.text('Project Group'), findsOneWidget);
      // 私聊不再单独成段，也不显示服务器拼的 "A & B"。
      expect(find.text('私聊'), findsNothing);
      expect(find.textContaining(' & '), findsNothing);
      for (final id in ['1', '2', '3', '4']) {
        expect(find.byKey(ValueKey('contact-$id')), findsOneWidget);
      }

      expect(inRow('1', find.text('明天见')), findsOneWidget);
      expect(inRow('1', find.text('3')), findsOneWidget);
      expect(inRow('1', find.byIcon(Icons.volume_off_outlined)), findsOneWidget);
      expect(inRow('2', find.text('离线')), findsOneWidget);
      expect(inRow('3', find.text('非好友')), findsOneWidget);
      expect(inRow('3', find.text('已屏蔽')), findsOneWidget);
      expect(inRow('4', find.text('非好友')), findsOneWidget);
      expect(inRow('1', find.text('非好友')), findsNothing);

      // 置顶在前，然后按最后消息时间，没聊过的按名字。
      expect(rowTop(tester, '4'), lessThan(rowTop(tester, '1')));
      expect(rowTop(tester, '1'), lessThan(rowTop(tester, '2')));
      expect(rowTop(tester, '2'), lessThan(rowTop(tester, '3')));

      // 屏蔽的人从菜单解除屏蔽。
      await tester.longPress(find.text('Carol'));
      await tester.pumpAndSettle();
      expect(find.text('移出列表'), findsNothing);
      expect(find.text('加好友'), findsOneWidget);
      await tester.tap(find.text('解除屏蔽'));
      await tester.pumpAndSettle();

      expect(chatService.unblockedRoomIds, ['p3']);
      expect(inRow('3', find.text('已屏蔽')), findsNothing);
    });

    testWidgets('loads every page of private chats', (tester) async {
      final peers = [
        for (var i = 0; i < 130; i++) testUser('u$i', 'Peer $i'),
      ];
      final chatService = FakeChatDirectoryService(privateChats: [
        for (var i = 0; i < peers.length; i++) privateChat('p$i', peers[i]),
      ]);

      await tester.pumpWidget(buildTestWidget(
        FakeContactService(),
        chatService: chatService,
      ));
      await tester.pumpAndSettle();

      expect(chatService.privatePagesRequested, [0, 1]);
      await tester.enterText(find.byType(TextField).first, 'Peer 129');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('contact-u129')), findsOneWidget);
    });

    testWidgets('collapses a top-level contact section and persists it',
        (tester) async {
      final service = FakeContactService();
      final chatService = FakeChatDirectoryService(
        groupChats: [
          Chat(
            id: '10',
            name: 'Project Group',
            type: ChatType.group,
            isPrivate: false,
            createdAt: DateTime.parse('2024-01-01T10:00:00'),
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(
        service,
        chatService: chatService,
      ));
      await tester.pump();

      expect(find.text('我的群聊'), findsOneWidget);
      expect(find.text('Project Group'), findsOneWidget);

      await tester.tap(find.text('我的群聊'));
      await tester.pumpAndSettle();

      expect(find.text('我的群聊'), findsOneWidget);
      expect(find.text('Project Group'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('pmchat.contacts.section.collapsed.groups'),
        isTrue,
      );
    });

    testWidgets('restores persisted top-level section collapse state',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'pmchat.contacts.section.collapsed.groups': true,
      });
      final service = FakeContactService();
      final chatService = FakeChatDirectoryService(
        groupChats: [
          Chat(
            id: '10',
            name: 'Project Group',
            type: ChatType.group,
            isPrivate: false,
            createdAt: DateTime.parse('2024-01-01T10:00:00'),
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(
        service,
        chatService: chatService,
      ));
      await tester.pumpAndSettle();

      expect(find.text('我的群聊'), findsOneWidget);
      expect(find.text('Project Group'), findsNothing);
    });

    testWidgets('renders grouped contacts and moves an item to a group',
        (tester) async {
      final service = FakeContactService(
        friends: [
          testUser('1', 'Alice', email: 'alice@example.com'),
          testUser('2', 'Bob', email: 'bob@example.com'),
        ],
        groupBundle: const ContactGroupBundle(
          groups: [
            ContactGroup(id: '7', name: '核心', sortOrder: 0),
          ],
          assignments: [
            ContactGroupAssignment(
              groupId: '7',
              targetType: ContactGroupTargetType.friend,
              targetId: '1',
            ),
          ],
        ),
      );

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pumpAndSettle();

      expect(find.text('核心'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('未分组'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      await tester.longPress(find.text('Bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动到分组'));
      await tester.pumpAndSettle();
      expect(find.text('移动到分组'), findsOneWidget);

      await tester.tap(find.text('核心').last);
      await tester.pumpAndSettle();

      expect(service.assignmentCalls, ['FRIEND:2:7']);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets(
        'non-friends and old private-chat folders follow the room assignment',
        (tester) async {
      final alice = testUser('1', 'Alice');
      final stranger = testUser('5', 'Stranger');
      final service = FakeContactService(
        friends: [alice],
        groupBundle: const ContactGroupBundle(
          groups: [
            ContactGroup(id: '7', name: '核心', sortOrder: 0),
            ContactGroup(id: '8', name: '工作', sortOrder: 1),
          ],
          assignments: [
            // 旧版本里私聊单独分过组。
            ContactGroupAssignment(
              groupId: '7',
              targetType: ContactGroupTargetType.room,
              targetId: 'p1',
            ),
            ContactGroupAssignment(
              groupId: '8',
              targetType: ContactGroupTargetType.room,
              targetId: 'p5',
            ),
          ],
        ),
      );
      final chatService = FakeChatDirectoryService(privateChats: [
        privateChat('p1', alice, lastMessage: 'hi'),
        privateChat('p5', stranger, lastMessage: 'hello'),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        chatService: chatService,
      ));
      await tester.pumpAndSettle();

      final coreTop = tester.getTopLeft(find.text('核心')).dy;
      final workTop = tester.getTopLeft(find.text('工作')).dy;
      expect(find.text('未分组'), findsNothing);
      expect(rowTop(tester, '1'), inExclusiveRange(coreTop, workTop));
      expect(rowTop(tester, '5'), greaterThan(workTop));

      // 好友移到"未分组"：好友分组和旧的私聊分组都要清掉，否则还会留在旧组。
      await tester.longPress(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动到分组'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('未分组').last);
      await tester.pumpAndSettle();
      expect(service.assignmentCalls, ['FRIEND:1:null', 'ROOM:p1:null']);
      expect(find.text('未分组'), findsOneWidget);

      // 非好友按私聊会话归组。
      await tester.longPress(find.text('Stranger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动到分组'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('核心').last);
      await tester.pumpAndSettle();
      expect(service.assignmentCalls.last, 'ROOM:p5:7');
    });

    testWidgets('opens group management and creates a group', (tester) async {
      final service = FakeContactService();

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理分组'));
      await tester.pumpAndSettle();

      expect(find.text('分组管理'), findsOneWidget);
      expect(find.text('暂无自定义分组'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '新建'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, '项目组');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(service.createdGroupNames, ['项目组']);
    });

    testWidgets('renders retry state when service fails', (tester) async {
      final service = FakeContactService(error: Exception('offline'));

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.text('联系人加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('accepts a friend request and refreshes contacts',
        (tester) async {
      final requester = testUser('2', 'Requester');
      final service = FakeContactService(
        receivedRequests: [
          FriendshipRequest(
            id: '10',
            status: 'PENDING',
            user: requester,
            friend: testUser('9', 'Me'),
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();
      await tester.tap(find.byTooltip('接受'));
      await tester.pumpAndSettle();

      expect(service.acceptedUserIds, ['2']);
      expect(find.text('Requester'), findsOneWidget);
      expect(find.text('请求添加你为好友'), findsNothing);
    });

    testWidgets('searches users and sends friend request from add sheet',
        (tester) async {
      final service = FakeContactService(
        searchResults: [testUser('3', 'Search Hit', email: 'hit@example.com')],
      );

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.person_add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'hit');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();

      expect(service.searchKeywords, ['hit']);
      expect(find.text('Search Hit'), findsOneWidget);
      expect(find.text('hit@example.com'), findsNothing);

      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(service.sentRequestUserIds, ['3']);
      expect(find.text('已发送'), findsOneWidget);
    });

    testWidgets('tapping a contact without a chat creates and opens it',
        (tester) async {
      final service = FakeContactService(
        friends: [testUser('4', 'Bob')],
        createdChat: Chat(
          id: '42',
          name: 'Alice & Bob',
          type: ChatType.private,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
        ),
      );

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      expect(service.privateChatUserIds, ['4']);
      expect(find.text('Chat Page'), findsOneWidget);
      expect(openedRoute?.name, '/chat/42');
    });

    testWidgets('tapping a contact with a chat opens that chat directly',
        (tester) async {
      final alice = testUser('1', 'Alice');
      final stranger = testUser('5', 'Stranger');
      final service = FakeContactService(friends: [alice]);
      final chatService = FakeChatDirectoryService(privateChats: [
        privateChat('p1', alice, lastMessage: 'hi'),
        privateChat('p5', stranger, lastMessage: 'hello'),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        chatService: chatService,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(service.privateChatUserIds, isEmpty);
      expect(openedRoute?.name, '/chat/p1');
      final arguments = openedRoute?.arguments as ChatScreenArguments;
      expect(arguments.chat.id, 'p1');
      // 从联系人打开：桌面中间栏留在联系人列表。
      expect(arguments.openedFromContacts, isTrue);

      Navigator.of(tester.element(find.text('Chat Page'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stranger'));
      await tester.pumpAndSettle();
      expect(service.privateChatUserIds, isEmpty);
      expect(openedRoute?.name, '/chat/p5');
    });

    testWidgets('menu starts calls, pins, mutes, clears and blocks the chat',
        (tester) async {
      final alice = testUser('1', 'Alice');
      final service = FakeContactService(friends: [alice]);
      final chatService = FakeChatDirectoryService(privateChats: [
        privateChat('p1', alice, lastMessage: 'hi'),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        chatService: chatService,
      ));
      await tester.pumpAndSettle();

      Future<void> pick(String label) async {
        await tester.tap(find.byTooltip('联系人操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await pick('置顶');
      await pick('消息免打扰');
      expect(chatService.settingsCalls,
          ['p1:pinned=true:muted=null', 'p1:pinned=null:muted=true']);
      expect(inRow('1', find.byIcon(Icons.push_pin_rounded)), findsOneWidget);
      expect(inRow('1', find.byIcon(Icons.volume_off_outlined)), findsOneWidget);

      await pick('清空聊天记录');
      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();
      expect(chatService.clearedRoomIds, ['p1']);

      await pick('屏蔽');
      await tester.tap(find.widgetWithText(FilledButton, '屏蔽'));
      await tester.pumpAndSettle();
      expect(chatService.blockedRoomIds, ['p1']);
      expect(inRow('1', find.text('已屏蔽')), findsOneWidget);

      await pick('语音通话');
      expect(openedRoute?.name, '/chat/p1');
      final arguments = openedRoute?.arguments as ChatScreenArguments;
      expect(arguments.chat.id, 'p1');
      expect(arguments.startCall?.label, '语音');
    });

    testWidgets('non-friend menu offers 加好友 instead of 删除好友',
        (tester) async {
      final stranger = testUser('5', 'Stranger');
      final service = FakeContactService(searchResults: [stranger]);
      final chatService = FakeChatDirectoryService(privateChats: [
        privateChat('p5', stranger, lastMessage: 'hello'),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        chatService: chatService,
      ));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Stranger'));
      await tester.pumpAndSettle();

      expect(find.text('删除好友'), findsNothing);
      await tester.tap(find.text('加好友'));
      await tester.pumpAndSettle();
      expect(service.sentRequestUserIds, ['5']);
    });

    testWidgets('realtime updates move the contact row and its unread badge',
        (tester) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final alice = testUser('1', 'Alice');
      final bob = testUser('2', 'Bob');
      final realtime = FakeRealtimeService();
      final service = FakeContactService(friends: [alice, bob]);
      final chatService = FakeChatDirectoryService(privateChats: [
        privateChat('p1', alice,
            lastMessage: '早', at: DateTime.parse('2024-01-01T10:05:00')),
        privateChat('p2', bob,
            lastMessage: '好', at: DateTime.parse('2024-01-01T10:00:00')),
      ]);

      await tester.pumpWidget(buildTestWidget(
        service,
        chatService: chatService,
        realtimeService: realtime,
      ));
      await tester.pumpAndSettle();
      expect(realtime.connectCalls, 1);
      expect(rowTop(tester, '1'), lessThan(rowTop(tester, '2')));

      realtime.emitMessage(Message(
        id: 'm-new',
        content: '在吗',
        senderId: '2',
        senderName: 'Bob',
        chatRoomId: 'p2',
        timestamp: DateTime.parse('2024-01-01T10:10:00'),
      ));
      await tester.pumpAndSettle();

      expect(inRow('2', find.text('在吗')), findsOneWidget);
      expect(inRow('2', find.text('1')), findsOneWidget);
      expect(rowTop(tester, '2'), lessThan(rowTop(tester, '1')));

      // 在另一台设备上读完了。
      realtime.emitStatus({
        'type': 'read_receipt',
        'chatRoomId': 'p2',
        'userId': 'me',
        'lastReadMessageId': 'm-new',
      });
      await tester.pumpAndSettle();
      expect(inRow('2', find.text('1')), findsNothing);

      // 在另一台设备上置顶了 Alice。
      realtime.emitStatus({
        'type': 'room_display_state_changed',
        'chatRoomId': 'p1',
        'state': {'pinned': true, 'muted': false, 'unreadCount': 0},
      });
      await tester.pumpAndSettle();
      expect(rowTop(tester, '1'), lessThan(rowTop(tester, '2')));
      expect(inRow('1', find.byIcon(Icons.push_pin_rounded)), findsOneWidget);

      // 在线状态实时变化（没有私聊的好友也一样）。
      realtime.emitStatus({
        'type': 'status',
        'userId': '2',
        'onlineStatus': 'ONLINE',
      });
      await tester.pumpAndSettle();
      expect(
        inRow(
            '2',
            find.byWidgetPredicate((widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).color ==
                    AppColors.online)),
        findsOneWidget,
      );

      // 新的私聊（别人第一次找我）：服务器发 room_membership_added，列表重新拉取。
      final carol = testUser('3', 'Carol');
      chatService.privateChats = [
        ...chatService.privateChats,
        privateChat('p3', carol,
            lastMessage: '你好', at: DateTime.parse('2024-01-01T10:20:00')),
      ];
      realtime.emitStatus({
        'type': 'room_membership_added',
        'chatRoomId': 'p3',
      });
      await tester.pumpAndSettle();
      expect(inRow('3', find.text('你好')), findsOneWidget);
      expect(inRow('3', find.text('非好友')), findsOneWidget);
    });

    testWidgets('compact list highlights the open chat and switches contacts',
        (tester) async {
      final alice = testUser('1', 'Alice');
      final bob = testUser('2', 'Bob');
      final opened = <ChatScreenArguments>[];
      final service = FakeContactService(
        friends: [alice, bob],
        receivedRequests: [
          FriendshipRequest(
            id: '10',
            status: 'PENDING',
            user: testUser('9', 'Requester'),
            friend: _me,
          ),
        ],
      );
      final chatService = FakeChatDirectoryService(
        groupChats: [
          Chat(
            id: '10',
            name: 'Project Group',
            type: ChatType.group,
            createdAt: DateTime.parse('2024-01-01T10:00:00'),
          ),
        ],
        privateChats: [
          privateChat('p1', alice, lastMessage: 'hi'),
          privateChat('p2', bob, lastMessage: 'yo'),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 340,
          child: ContactsPage(
            compact: true,
            selectedChatId: 'p1',
            contactService: service,
            chatService: chatService,
            currentUserId: 'me',
            onOpenChat: (arguments) async => opened.add(arguments),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 中间栏只有联系人。
      expect(find.text('Project Group'), findsNothing);
      expect(find.text('新的好友请求'), findsNothing);
      final selectedCard = tester.widget<PMCard>(find
          .ancestor(
              of: find.byKey(const ValueKey('contact-1')),
              matching: find.byType(PMCard))
          .first);
      expect(selectedCard.background, AppColors.pixelBlue);

      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      expect(opened.single.chat.id, 'p2');
      expect(find.text('Chat Page'), findsNothing);
    });

    testWidgets('shows contact details and removes a friend', (tester) async {
      final service = FakeContactService(
        friends: [
          testUser(
            '5',
            'Carol',
            email: 'carol@example.com',
            phone: '555-0101',
            bio: 'Design lead',
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();
      await tester.longPress(find.text('Carol'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看资料'));
      await tester.pumpAndSettle();

      // 别人的邮箱、手机号不展示（服务器也不再下发）。
      expect(find.text('手机号'), findsNothing);
      expect(find.text('555-0101'), findsNothing);
      expect(find.text('邮箱'), findsNothing);
      expect(find.text('carol@example.com'), findsNothing);
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('简介'), findsOneWidget);
      expect(find.text('Design lead'), findsOneWidget);

      await tester.tap(find.text('删除好友').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();

      expect(service.removedUserIds, ['5']);
      expect(find.text('暂无联系人'), findsOneWidget);
    });
  });
}

User testUser(
  String id,
  String displayName, {
  String? email,
  String? phone,
  String? bio,
}) {
  return User(
    id: id,
    username: displayName.toLowerCase().replaceAll(' ', '_'),
    email: email ?? '${displayName.toLowerCase()}@example.com',
    phone: phone,
    displayName: displayName,
    bio: bio,
    createdAt: DateTime.parse('2024-01-01T10:00:00'),
  );
}

class FakeContactService extends ContactDataService {
  FakeContactService({
    List<User>? friends,
    List<FriendshipRequest>? receivedRequests,
    ContactGroupBundle? groupBundle,
    this.searchResults = const [],
    this.createdChat,
    this.error,
  })  : friends = friends ?? [],
        receivedRequests = receivedRequests ?? [],
        groupBundle = groupBundle ?? const ContactGroupBundle(),
        super(authenticatedRequest: _unusedRequest);

  List<User> friends;
  List<FriendshipRequest> receivedRequests;
  ContactGroupBundle groupBundle;
  final List<User> searchResults;
  final Chat? createdChat;
  final Object? error;
  final List<String> acceptedUserIds = [];
  final List<String> declinedUserIds = [];
  final List<String> sentRequestUserIds = [];
  final List<String> privateChatUserIds = [];
  final List<String> searchKeywords = [];
  final List<String> removedUserIds = [];
  final List<String> createdGroupNames = [];
  final List<String> deletedGroupIds = [];
  final List<List<String>> reorderCalls = [];
  final List<String> assignmentCalls = [];

  static Future<http.Response> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<User>> getFriends() async {
    final err = error;
    if (err != null) {
      throw err;
    }
    return friends;
  }

  @override
  Future<List<FriendshipRequest>> getReceivedFriendRequests() async {
    final err = error;
    if (err != null) {
      throw err;
    }
    return receivedRequests;
  }

  @override
  Future<ContactGroupBundle> getContactGroups() async {
    final err = error;
    if (err != null) {
      throw err;
    }
    return groupBundle;
  }

  @override
  Future<List<User>> searchUsers(String keyword, {int limit = 20}) async {
    searchKeywords.add(keyword);
    return searchResults;
  }

  @override
  Future<FriendshipRequest> sendFriendRequest(String userId) async {
    sentRequestUserIds.add(userId);
    return FriendshipRequest(
      id: 'sent-$userId',
      status: 'PENDING',
      user: testUser('9', 'Me'),
      friend: searchResults.firstWhere((user) => user.id == userId),
    );
  }

  @override
  Future<FriendshipRequest> acceptFriendRequest(String userId) async {
    acceptedUserIds.add(userId);
    final request = receivedRequests.firstWhere(
      (request) => request.user.id == userId,
    );
    receivedRequests =
        receivedRequests.where((request) => request.user.id != userId).toList();
    friends = [...friends, request.user];
    return request;
  }

  @override
  Future<void> declineFriendRequest(String userId) async {
    declinedUserIds.add(userId);
    receivedRequests =
        receivedRequests.where((request) => request.user.id != userId).toList();
  }

  @override
  Future<Chat> createPrivateChat(String userId) async {
    privateChatUserIds.add(userId);
    return createdChat ??
        Chat(
          id: 'chat-$userId',
          name: 'Private',
          type: ChatType.private,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
        );
  }

  @override
  Future<void> removeFriend(String userId) async {
    removedUserIds.add(userId);
    friends = friends.where((user) => user.id != userId).toList();
  }

  @override
  Future<ContactGroup> createContactGroup(String name) async {
    createdGroupNames.add(name);
    final group = ContactGroup(
      id: 'created-${createdGroupNames.length}',
      name: name,
      sortOrder: groupBundle.groups.length,
    );
    groupBundle = ContactGroupBundle(
      groups: [...groupBundle.groups, group],
      assignments: groupBundle.assignments,
    );
    return group;
  }

  @override
  Future<ContactGroup> updateContactGroup(
    String groupId, {
    required String name,
    int? sortOrder,
  }) async {
    final group = ContactGroup(
      id: groupId,
      name: name,
      sortOrder: sortOrder ?? 0,
    );
    groupBundle = ContactGroupBundle(
      groups: [
        for (final existing in groupBundle.groups)
          existing.id == groupId ? group : existing,
      ],
      assignments: groupBundle.assignments,
    );
    return group;
  }

  @override
  Future<void> deleteContactGroup(String groupId) async {
    deletedGroupIds.add(groupId);
    groupBundle = ContactGroupBundle(
      groups: groupBundle.groups.where((group) => group.id != groupId).toList(),
      assignments: groupBundle.assignments
          .where((assignment) => assignment.groupId != groupId)
          .toList(),
    );
  }

  @override
  Future<List<ContactGroup>> reorderContactGroups(List<String> groupIds) async {
    reorderCalls.add(groupIds);
    final byId = {for (final group in groupBundle.groups) group.id: group};
    final reordered = <ContactGroup>[
      for (var i = 0; i < groupIds.length; i++)
        ContactGroup(
          id: groupIds[i],
          name: byId[groupIds[i]]?.name ?? groupIds[i],
          sortOrder: i,
        ),
    ];
    groupBundle = ContactGroupBundle(
      groups: reordered,
      assignments: groupBundle.assignments,
    );
    return reordered;
  }

  @override
  Future<ContactGroupAssignment?> assignContactGroupItem({
    required ContactGroupTargetType targetType,
    required String targetId,
    String? groupId,
  }) async {
    assignmentCalls
        .add('${targetType.wireName}:$targetId:${groupId ?? 'null'}');
    final retained = groupBundle.assignments
        .where((assignment) =>
            assignment.targetKey !=
            ContactGroupTargetKey.build(targetType, targetId))
        .toList();
    ContactGroupAssignment? next;
    if (groupId != null) {
      next = ContactGroupAssignment(
        groupId: groupId,
        targetType: targetType,
        targetId: targetId,
      );
      retained.add(next);
    }
    groupBundle = ContactGroupBundle(
      groups: groupBundle.groups,
      assignments: retained,
    );
    return next;
  }
}

class FakeChatDirectoryService extends ChatDataService {
  FakeChatDirectoryService({
    this.groupChats = const [],
    List<Chat> privateChats = const [],
  })  : privateChats = List<Chat>.from(privateChats),
        super(authenticatedRequest: FakeContactService._unusedRequest);

  final List<Chat> groupChats;
  List<Chat> privateChats;
  final List<String> unblockedRoomIds = [];
  final List<String> blockedRoomIds = [];
  final List<String> clearedRoomIds = [];
  final List<String> settingsCalls = [];
  final List<int> privatePagesRequested = [];

  @override
  Future<List<Chat>> getChatRooms({
    int page = 0,
    int size = 30,
    bool includeDetails = true,
    int detailLimit = 8,
    bool includeHidden = false,
    bool includeBlocked = false,
    ChatType? type,
    ChatType? excludeType,
    bool forceRefresh = false,
  }) async {
    if (type == ChatType.group) {
      expect(includeHidden, isTrue);
      expect(includeBlocked, isTrue);
      return page == 0 ? groupChats : const [];
    }
    if (type == ChatType.private) {
      // 联系人里要有全部私聊：包括已移出和已屏蔽的。
      expect(includeHidden, isTrue);
      expect(includeBlocked, isTrue);
      privatePagesRequested.add(page);
      return privateChats.skip(page * size).take(size).toList();
    }
    return const [];
  }

  @override
  Future<void> unblockChatRoom(String chatRoomId) async {
    unblockedRoomIds.add(chatRoomId);
  }

  @override
  Future<void> blockChatRoom(String chatRoomId) async {
    blockedRoomIds.add(chatRoomId);
  }

  @override
  Future<void> clearChatHistory(String chatRoomId) async {
    clearedRoomIds.add(chatRoomId);
  }

  @override
  Future<Map<String, dynamic>> updateNotificationSettings(
    String chatRoomId, {
    bool? muted,
    bool? pinned,
  }) async {
    settingsCalls.add('$chatRoomId:pinned=$pinned:muted=$muted');
    return {'pinned': pinned ?? false, 'muted': muted ?? false};
  }
}

final _me = testUser('me', 'Me');

/// 和 [peer] 的私聊（参与者里有我和对方，和服务器摘要一致）。
Chat privateChat(
  String id,
  User peer, {
  String? lastMessage,
  DateTime? at,
  int unreadCount = 0,
  bool isPinned = false,
  bool isMuted = false,
  bool isBlocked = false,
  DateTime? hiddenAt,
}) {
  final created = DateTime.parse('2024-01-01T09:00:00');
  return Chat(
    id: id,
    name: 'Me & ${peer.displayName}',
    type: ChatType.private,
    createdAt: created,
    participants: [_me, peer],
    unreadCount: unreadCount,
    isPinned: isPinned,
    isMuted: isMuted,
    isBlocked: isBlocked,
    hiddenAt: hiddenAt,
    lastMessage: lastMessage == null
        ? null
        : Message(
            id: 'last-$id',
            content: lastMessage,
            senderId: peer.id,
            senderName: peer.displayName,
            chatRoomId: id,
            timestamp: at ?? created,
          ),
  );
}
