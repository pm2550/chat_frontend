import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/home_screen.dart';
import 'package:chat_app/services/chat_room_directory.dart';
import 'package:chat_app/widgets/pm_navigation_rail.dart';
import 'package:chat_app/widgets/pm_section_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_list_page_test.dart' show FakeChatListService, FakeRealtimeService;

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('child return preserves selected profile and URL at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final navigation = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (call) async {
          navigation.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.navigation, null));
      await tester.pumpWidget(MaterialApp(
        initialRoute: '/home/contacts',
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => HomeScreen(
            cacheWarmer: () async {},
            pageBuilder: (context, index, _) => Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: Text('child-page')),
                  ),
                )),
                child: Text('tab-$index'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('tab-1'), findsOneWidget);
      await tester.tap(find.text('我'));
      await tester.pumpAndSettle();
      expect(find.text('tab-4'), findsOneWidget);
      // Repeated nested visits used to re-read the original contacts route.
      for (var visit = 0; visit < 2; visit++) {
        await tester.tap(find.text('tab-4'));
        await tester.pumpAndSettle();
        expect(find.text('child-page'), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        expect(find.text('tab-4'), findsOneWidget);
        expect(find.text('tab-1'), findsNothing);
        final updates = navigation
            .where((call) => call.method == 'routeInformationUpdated');
        expect(updates.last.arguments['uri'], '/home/me');
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('iOS edge swipe reveals cached chats after leaving profile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    final initCounts = <int, int>{};
    final disposeCounts = <int, int>{};
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      theme: ThemeData(platform: TargetPlatform.iOS),
      initialRoute: '/home/me',
      onGenerateRoute: (_) => null,
      onGenerateInitialRoutes: (route) => [
        PMSectionRoute<void>(
          stationary: false,
          settings: RouteSettings(name: route),
          builder: (_) => HomeScreen(
            cacheWarmer: () async {},
            pageBuilder: (_, index, __) => _CountingTabPage(
              index: index,
              initCounts: initCounts,
              disposeCounts: disposeCounts,
            ),
          ),
        )
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('tab-4'), findsOneWidget);
    await tester.tap(find.text('消息'));
    await tester.pumpAndSettle();
    final listBounds = tester.getRect(find.text('tab-0'));
    final chat = PMSectionRoute<void>(
      stationary: false,
      settings: const RouteSettings(name: '/chat/1'),
      builder: (_) => const Scaffold(body: Center(child: Text('chat-page'))),
    );
    navigator.currentState!.push(chat);
    await tester.pumpAndSettle();
    // Cancel a slow partial swipe, then complete the next swipe.
    var gesture = await tester.startGesture(const Offset(2, 400));
    await gesture.moveBy(const Offset(95, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('tab-0'), findsOneWidget);
    expect(find.text('tab-4'), findsNothing);
    expect(tester.getRect(find.text('tab-0')).right, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('chat-page'), findsOneWidget);
    gesture = await tester.startGesture(const Offset(2, 400));
    await gesture.moveBy(const Offset(280, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('tab-0'), findsOneWidget);
    expect(find.text('tab-4'), findsNothing);
    await gesture.up();
    // Check every return frame rather than hiding a blank behind pumpAndSettle.
    for (var frame = 0; frame < 35; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('tab-0'), findsOneWidget);
      expect(find.text('tab-4'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('chat-page'), findsNothing);
    expect(tester.getRect(find.text('tab-0')), listBounds);
    expect(initCounts[0], 1);
    expect(disposeCounts[0], isNull);
  });

  group('HomeScreen unread badges', () {
    Future<(ChatRoomDirectory, FakeRealtimeService)> loadedDirectory() async {
      final realtime = FakeRealtimeService();
      final created = DateTime.parse('2024-01-01T10:00:00');
      final directory = ChatRoomDirectory(
        chatService: FakeChatListService(chats: [
          Chat(
            id: 'g1',
            name: '群',
            type: ChatType.group,
            createdAt: created,
            unreadCount: 2,
          ),
          Chat(
            id: 'p1',
            name: 'Me & Alice',
            type: ChatType.private,
            createdAt: created,
            unreadCount: 3,
            participants: [
              User(
                id: 'alice',
                username: 'alice',
                email: 'alice@test.com',
                displayName: 'Alice',
                createdAt: created,
              ),
            ],
          ),
          // 屏蔽的私聊不计未读。
          Chat(
            id: 'p2',
            name: 'Me & Spam',
            type: ChatType.private,
            createdAt: created,
            unreadCount: 7,
            isBlocked: true,
          ),
        ]),
        realtimeService: realtime,
        currentUserId: () => 'me',
      );
      await directory.conversations.load();
      await directory.privateChats.load();
      return (directory, realtime);
    }

    Finder badge(String label) =>
        find.descendant(of: find.byType(Badge), matching: find.text(label));

    testWidgets('mobile tabs split group and private unread and stay live',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (directory, realtime) = await loadedDirectory();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          directory: directory,
          cacheWarmer: () async {},
          pageBuilder: (_, index, __) => Text('tab-$index'),
        ),
      ));
      await tester.pump();

      expect(directory.totalUnread, 5);
      expect(badge('2'), findsOneWidget);
      expect(badge('3'), findsOneWidget);
      final contactsTab = find.ancestor(
          of: find.text('联系人'), matching: find.byType(NavigationDestination));
      expect(
          find.descendant(of: contactsTab, matching: badge('3')), findsOneWidget);

      realtime.emitMessage(Message(
        id: 'pm',
        content: '私聊',
        senderId: 'alice',
        senderName: 'Alice',
        chatRoomId: 'p1',
        timestamp: DateTime.parse('2024-01-01T10:05:00'),
      ));
      await tester.pump();
      await tester.pump();

      expect(badge('4'), findsOneWidget);
      expect(badge('2'), findsOneWidget);
      expect(directory.totalUnread, 6);
    });

    testWidgets('desktop rail and tablet chips show the same badges',
        (tester) async {
      final (directory, _) = await loadedDirectory();
      for (final width in [1440.0, 800.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: HomeScreen(
            key: ValueKey(width),
            directory: directory,
            cacheWarmer: () async {},
            pageBuilder: (_, index, __) => Text('tab-$index'),
          ),
        ));
        await tester.pump();
        if (width == 1440) {
          expect(
              tester.widget<PMNavigationRail>(find.byType(PMNavigationRail))
                  .badgeCounts,
              [2, 3]);
        }
        expect(badge('2'), findsOneWidget);
        expect(badge('3'), findsOneWidget);
      }
    });
  });

  group('HomeScreen tab cache', () {
    testWidgets('defers hidden cache warming until after the first frame',
        (tester) async {
      var warmCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            cacheWarmupDelay: const Duration(milliseconds: 500),
            cacheWarmer: () async => warmCalls += 1,
            pageBuilder: (_, index, __) => Text('tab-$index'),
          ),
        ),
      );

      expect(warmCalls, 0);
      await tester.pump(const Duration(milliseconds: 499));
      expect(warmCalls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(warmCalls, 1);
    });

    testWidgets('keeps visited tabs alive when switching on mobile',
        (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(390, 844);
      view.devicePixelRatio = 1;
      addTearDown(() {
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });

      final initCounts = <int, int>{};
      final disposeCounts = <int, int>{};

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            pageBuilder: (context, index, aiSection) {
              return _CountingTabPage(
                index: index,
                initCounts: initCounts,
                disposeCounts: disposeCounts,
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(initCounts, {0: 1});
      expect(disposeCounts, isEmpty);
      expect(find.text('tab-0'), findsOneWidget);

      await tester.tap(find.text('联系人'));
      await tester.pumpAndSettle();

      expect(initCounts[0], 1);
      expect(initCounts[1], 1);
      expect(disposeCounts[0], isNull);
      expect(find.text('tab-1'), findsOneWidget);

      await tester.tap(find.text('消息'));
      await tester.pumpAndSettle();

      expect(initCounts[0], 1);
      expect(initCounts[1], 1);
      expect(disposeCounts[0], isNull);
      expect(disposeCounts[1], isNull);
      expect(find.text('tab-0'), findsOneWidget);
    });
  });
}

class _CountingTabPage extends StatefulWidget {
  const _CountingTabPage({
    required this.index,
    required this.initCounts,
    required this.disposeCounts,
  });

  final int index;
  final Map<int, int> initCounts;
  final Map<int, int> disposeCounts;

  @override
  State<_CountingTabPage> createState() => _CountingTabPageState();
}

class _CountingTabPageState extends State<_CountingTabPage> {
  @override
  void initState() {
    super.initState();
    widget.initCounts
        .update(widget.index, (count) => count + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    widget.disposeCounts
        .update(widget.index, (count) => count + 1, ifAbsent: () => 1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('tab-${widget.index}'));
  }
}
