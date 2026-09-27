import 'dart:ui' show SemanticsAction;

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/screens/home/chat_list_page.dart';
import 'package:chat_app/screens/home/contacts_page.dart';
import 'package:chat_app/widgets/pm_navigation_rail.dart';
import 'package:chat_app/screens/home/profile_page.dart';
import 'package:chat_app/screens/settings/chat_preferences_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen_test.dart' show buildTestWidget, createTestChat;
import 'chat_list_page_test.dart' show FakeChatListService, FakeRealtimeService;
import 'profile_page_test.dart' show FakeUserProfileService, testUser;
import 'contacts_page_test.dart' as contacts show FakeContactService;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [1024.0, 1440.0]) {
    testWidgets('conversation list keeps its width when opening chat at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: ChatListPage(
        chatService: FakeChatListService(chats: []),
        realtimeService: FakeRealtimeService(),
      )));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('desktop-conversation-list'));
      final before = tester.getSize(list);
      await tester.pumpWidget(buildTestWidget(createTestChat()));
      await tester.pumpAndSettle();
      expect(tester.getSize(list).width, before.width);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop middle column follows where a private chat was opened',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final middle = find.byKey(const ValueKey('desktop-conversation-list'));
    int railIndex() =>
        tester.widget<PMNavigationRail>(find.byType(PMNavigationRail))
            .selectedIndex;

    // 从联系人打开的私聊：中间栏是联系人，导航高亮联系人。
    await tester.pumpWidget(buildTestWidget(
      createTestChat(),
      contactService: contacts.FakeContactService(),
      routeArguments: ChatScreenArguments(
        chat: createTestChat(),
        openedFromContacts: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: middle, matching: find.byType(ContactsPage)),
        findsOneWidget);
    expect(find.byType(ChatListPage), findsNothing);
    final contactsPage =
        tester.widget<ContactsPage>(find.byType(ContactsPage));
    expect(contactsPage.compact, isTrue);
    expect(contactsPage.selectedChatId, 'chat1');
    expect(railIndex(), 1);

    // 从消息页（或通知、链接）打开的私聊：中间栏是消息列表。
    for (final chat in [
      createTestChat(),
      createTestChat(id: 'group1', type: ChatType.group),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildTestWidget(
        chat,
        contactService: contacts.FakeContactService(),
      ));
      await tester.pumpAndSettle();
      expect(
          find.descendant(of: middle, matching: find.byType(ChatListPage)),
          findsOneWidget);
      expect(find.byType(ContactsPage), findsNothing);
      expect(railIndex(), 0);
    }
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('composer separates files from tools at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestWidget(createTestChat()));
      await tester.pumpAndSettle();
      for (final name in ['表情', '贴纸', '插入 AI 助手', '附件', '更多工具']) {
        expect(find.byTooltip(name), findsOneWidget);
      }
      await tester.tap(find.byTooltip('附件'));
      await tester.pumpAndSettle();
      for (final name in ['相册', '文件', '语音文件']) {
        expect(find.text(name), findsOneWidget);
      }
      for (final name in ['AI 图片', '位置', '投票']) {
        expect(find.text(name), findsNothing);
      }
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多工具'));
      await tester.pumpAndSettle();
      for (final name in ['AI 图片', '位置', '投票']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('文件'), findsNothing);
      await tester.tap(find.text('投票'));
      await tester.pumpAndSettle();
      expect(find.text('发起投票'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320px chat keeps peer title readable and names composer actions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(buildTestWidget(createTestChat()));
      await tester.pumpAndSettle();
      final title =
          find.descendant(of: find.byType(AppBar), matching: find.text('好友'));
      expect(tester.getSize(title).width, greaterThanOrEqualTo(32));
      expect(find.byTooltip('语音通话'), findsOneWidget);
      expect(find.byTooltip('视频通话'), findsOneWidget);
      final record =
          tester.getSemantics(find.byTooltip('录音说话')).getSemanticsData();
      expect(record.tooltip, '录音说话');
      expect(record.hasAction(SemanticsAction.tap), isTrue);
      await tester.enterText(find.byType(TextField), '窄屏输入');
      await tester.pumpAndSettle();
      final send = tester.getSemantics(find.byTooltip('发送')).getSemanticsData();
      expect(send.tooltip, '发送');
      expect(send.hasAction(SemanticsAction.tap), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('unread filter hides read rooms and All restores them at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rooms = [
      Chat(
          id: 'read',
          name: '已读会话',
          type: ChatType.group,
          createdAt: DateTime(2026),
          unreadCount: 0),
      Chat(
          id: 'unread',
          name: '未读会话',
          type: ChatType.group,
          createdAt: DateTime(2026),
          unreadCount: 3),
    ];
    await tester.pumpWidget(MaterialApp(
        home: ChatListPage(
      chatService: FakeChatListService(chats: rooms),
      realtimeService: FakeRealtimeService(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('已读会话'), findsOneWidget);
    await tester.tap(find.text('未读 3'));
    await tester.pumpAndSettle();
    expect(find.text('已读会话'), findsNothing);
    expect(find.text('未读会话'), findsOneWidget);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('已读会话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'compact conversation list opens selected room through its callback',
      (tester) async {
    ChatScreenArguments? opened;
    final room = Chat(
        id: 'next',
        name: '继续聊天',
        type: ChatType.group,
        createdAt: DateTime(2026));
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            width: 340,
            child: ChatListPage(
              compact: true,
              selectedChatId: 'current',
              chatService: FakeChatListService(chats: [room]),
              realtimeService: FakeRealtimeService(),
              onOpenChat: (args) async {
                opened = args;
              },
            ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续聊天'));
    await tester.pumpAndSettle();
    expect(opened?.chat.id, 'next');
    expect(find.text('继续聊天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personalization is directly available on the mobile profile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = FakeUserProfileService(profile: testUser('me', '小满'));
    await tester
        .pumpWidget(MaterialApp(home: ProfilePage(profileService: service)));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('聊天装扮')).dy, lessThan(500));
    expect(find.text('我的收藏'), findsOneWidget);
    await tester.tap(find.text('聊天装扮'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPreferencesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
