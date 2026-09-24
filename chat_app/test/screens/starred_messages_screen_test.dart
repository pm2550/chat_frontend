import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/screens/home/profile_page.dart';
import 'package:chat_app/screens/profile/starred_messages_screen.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/user_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final _now = DateTime.now().subtract(const Duration(hours: 2));

Message _starred(String id, String content, String roomId) => Message(
      id: id,
      content: content,
      senderId: '2',
      senderName: '好友',
      chatRoomId: roomId,
      status: MessageStatus.sent,
      timestamp: _now,
      starredByMe: true,
    );

void main() {
  test('Message.fromJson reads starredByMe', () {
    final message = Message.fromJson({
      'id': 5,
      'content': 'x',
      'chatRoomId': 1,
      'starredByMe': true,
    });
    expect(message.starredByMe, isTrue);
    expect(Message.fromJson({'id': 6, 'content': 'y'}).starredByMe, isFalse);
    expect(message.toJson()['starredByMe'], isTrue);
  });

  testWidgets('lists starred messages with their chat names and unstars',
      (tester) async {
    final service = _FakeStarService(pages: [
      [_starred('11', '周五发版', '7'), _starred('12', '密码在群公告里', '8')],
    ]);

    await tester.pumpWidget(
      MaterialApp(home: StarredMessagesScreen(chatService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('周五发版'), findsOneWidget);
    expect(find.textContaining('项目群'), findsOneWidget);
    expect(find.textContaining('聊天'), findsWidgets); // unknown room 8

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('starred-message-11')),
      matching: find.byTooltip('取消收藏'),
    ));
    await tester.pumpAndSettle();

    expect(service.unstarredIds, ['11']);
    expect(find.text('周五发版'), findsNothing);
    expect(find.text('密码在群公告里'), findsOneWidget);
  });

  testWidgets('tapping a starred message opens its chat focused on it',
      (tester) async {
    final service = _FakeStarService(pages: [
      [_starred('11', '周五发版', '7')],
    ]);
    RouteSettings? opened;

    await tester.pumpWidget(MaterialApp(
      home: StarredMessagesScreen(chatService: service),
      onGenerateRoute: (settings) {
        opened = settings;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('chat-opened')),
        );
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('周五发版'));
    await tester.pumpAndSettle();

    expect(find.text('chat-opened'), findsOneWidget);
    expect(opened?.name, '/chat/7');
    final args = opened?.arguments as ChatScreenArguments;
    expect(args.chat.name, '项目群');
    expect(args.focusMessage?.id, '11');
  });

  testWidgets('pages through starred messages and shows an empty state',
      (tester) async {
    final service = _FakeStarService(pages: [
      [_starred('11', '第一页', '7')],
      [_starred('12', '第二页', '7')],
    ]);
    await tester.pumpWidget(
      MaterialApp(home: StarredMessagesScreen(chatService: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing);

    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: StarredMessagesScreen(
        key: const ValueKey('empty'),
        chatService: _FakeStarService(pages: [[]]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('还没有收藏的消息'), findsOneWidget);
  });

  testWidgets('profile page has a 我的收藏 entry', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: ProfilePage(profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('我的收藏'), 200);
    expect(find.text('我的收藏'), findsOneWidget);
  });
}

Future<http.Response> _unusedRequest(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  throw UnimplementedError('$method $url');
}

class _FakeStarService extends ChatDataService {
  _FakeStarService({required this.pages})
      : super(authenticatedRequest: _unusedRequest);

  final List<List<Message>> pages;
  final List<String> unstarredIds = [];

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
  }) async =>
      [
        Chat(
          id: '7',
          name: '项目群',
          type: ChatType.group,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

  @override
  Future<MessagePage> getStarredMessages({int page = 0, int size = 20}) async {
    final messages = page < pages.length ? pages[page] : const <Message>[];
    return MessagePage(
      messages: messages,
      currentPage: page,
      totalPages: pages.length,
      totalElements: pages.fold(0, (sum, p) => sum + p.length),
      hasNext: page < pages.length - 1,
      hasPrevious: page > 0,
    );
  }

  @override
  Future<Message> unstarMessage(String messageId) async {
    unstarredIds.add(messageId);
    return pages.expand((p) => p).firstWhere((m) => m.id == messageId);
  }
}

class _FakeProfileService extends UserProfileService {
  _FakeProfileService() : super(authenticatedRequest: _unusedRequest);

  @override
  Future<User> getProfile() async => User(
        id: '1',
        username: 'me',
        email: 'me@example.com',
        displayName: '我',
        createdAt: DateTime(2026, 1, 1),
      );
}
