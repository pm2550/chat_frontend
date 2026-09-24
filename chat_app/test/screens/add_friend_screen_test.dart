import 'dart:convert';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/design/design.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/contact_group.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/add_friend_screen.dart';
import 'package:chat_app/screens/home/contacts_page.dart';
import 'package:chat_app/screens/splash_screen.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:chat_app/services/friend_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

User _user(
  String id,
  String username,
  String name, {
  String? title,
  String frame = 'none',
}) =>
    User(
      id: id,
      username: username,
      email: '$username@test.com',
      displayName: name,
      title: title,
      titleColor: title == null ? null : '#FF6600',
      avatarFramePreset: frame,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('FriendCode', () {
    test('link is a web deep link that round-trips through parse', () {
      final link = FriendCode.linkFor('alice');
      expect(link, '${ApiConstants.webAppUrl}/#/add/alice');
      expect(FriendCode.parse(link)?.username, 'alice');
      expect(FriendCode.parse(FriendCode.linkFor('小明'))?.username, '小明');
      expect(FriendCode.usernameFromRoute('/add/alice'), 'alice');
      expect(FriendCode.usernameFromRoute('/chat/1'), isNull);
    });

    test('plain text is an exact username; digits may also be an id', () {
      expect(FriendCode.parse(' alice ')?.username, 'alice');
      expect(FriendCode.parse('@alice')?.username, 'alice');
      final numeric = FriendCode.parse('42');
      expect(numeric?.username, '42');
      expect(numeric?.id, '42');
      expect(FriendCode.parse('alice')?.id, isNull);
    });

    test('rejects text that is not a friend code', () {
      expect(FriendCode.parse(''), isNull);
      expect(FriendCode.parse('two words'), isNull);
      expect(FriendCode.parse('https://example.com/page'), isNull);
      expect(FriendCode.parse('weixin://dl/business'), isNull);
    });

    test('web cold start accepts the /add deep link', () {
      expect(ColdStartRoute.resolve('/add/alice'), '/add/alice');
      expect(ColdStartRoute.resolve('add/alice'), '/add/alice');
    });
  });

  group('ContactDataService.lookupUser', () {
    test('asks the exact-lookup endpoint and parses the user', () async {
      Uri? requested;
      final service = ContactDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          requested = Uri.parse(url);
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'user': {'id': 5, 'username': 'alice', 'displayName': '爱丽丝'},
            })),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );

      final user = await service.lookupUser(username: 'alice');

      expect(requested?.path, '/api/v1/users/lookup');
      expect(requested?.queryParameters, {'username': 'alice'});
      expect(user?.id, '5');
      expect(user?.displayName, '爱丽丝');
    });

    test('404 means no such user', () async {
      final service = ContactDataService(
        authenticatedRequest: (method, url, {headers, body}) async =>
            http.Response.bytes(utf8.encode('{"error":"用户不存在"}'), 404),
      );
      expect(await service.lookupUser(username: 'ali'), isNull);
    });
  });

  group('AddFriendScreen', () {
    testWidgets('deep link looks up the exact user and asks before sending',
        (tester) async {
      final service = _Contacts(users: [_user('5', 'alice', '爱丽丝')]);

      await tester.pumpWidget(MaterialApp(
        home: AddFriendScreen(initialCode: 'alice', contactService: service),
      ));
      await tester.pumpAndSettle();

      expect(service.lookups, ['username:alice']);
      expect(find.text('爱丽丝'), findsOneWidget);
      expect(find.text('@alice'), findsOneWidget);
      // Nothing is sent until the user confirms.
      expect(service.sentTo, isEmpty);

      await tester.tap(find.byKey(const ValueKey('add-friend-send-request')));
      await tester.pumpAndSettle();

      expect(service.sentTo, ['5']);
      expect(find.text('已发送好友请求'), findsOneWidget);
    });

    testWidgets('a partial username finds nobody and sends nothing',
        (tester) async {
      final service = _Contacts(users: [_user('5', 'alice', '爱丽丝')]);

      await tester.pumpWidget(MaterialApp(
        home: AddFriendScreen(contactService: service),
      ));
      await tester.enterText(find.byType(TextField), 'ali');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(service.lookups, ['username:ali']);
      expect(find.text('没有找到用户名为“ali”的用户'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-friend-result')), findsNothing);
      expect(service.fuzzySearches, isEmpty);
      expect(service.sentTo, isEmpty);
    });

    testWidgets('a numeric entry falls back to an exact user id',
        (tester) async {
      final service = _Contacts(users: [_user('42', 'bob', '鲍勃')]);

      await tester.pumpWidget(MaterialApp(
        home: AddFriendScreen(contactService: service),
      ));
      await tester.enterText(find.byType(TextField), '42');
      await tester.tap(find.byTooltip('查找'));
      await tester.pumpAndSettle();

      expect(service.lookups, ['username:42', 'id:42']);
      expect(find.text('鲍勃'), findsOneWidget);
    });

    testWidgets('scanning a friend code looks up that user', (tester) async {
      final service = _Contacts(users: [_user('5', 'alice', '爱丽丝')]);

      await tester.pumpWidget(MaterialApp(
        home: AddFriendScreen(
          contactService: service,
          scanner: (_) async => FriendCode.linkFor('alice'),
        ),
      ));
      await tester.tap(find.text('扫一扫好友的二维码'));
      await tester.pumpAndSettle();

      expect(service.lookups, ['username:alice']);
      expect(find.text('爱丽丝'), findsOneWidget);
    });

    testWidgets('an unrelated QR code is rejected without any lookup',
        (tester) async {
      final service = _Contacts(users: const []);

      await tester.pumpWidget(MaterialApp(
        home: AddFriendScreen(
          contactService: service,
          scanner: (_) async => 'https://example.com/promo',
        ),
      ));
      await tester.tap(find.text('扫一扫好友的二维码'));
      await tester.pumpAndSettle();

      expect(service.lookups, isEmpty);
      expect(find.textContaining('无法识别'), findsOneWidget);
    });

    testWidgets('existing friends are not offered another request',
        (tester) async {
      final alice = _user('5', 'alice', '爱丽丝');
      final service = _Contacts(users: [alice], friends: [alice]);

      await tester.pumpWidget(MaterialApp(
        home: AddFriendScreen(initialCode: 'alice', contactService: service),
      ));
      await tester.pumpAndSettle();

      expect(find.text('已是好友'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-friend-send-request')),
          findsNothing);
    });
  });

  testWidgets('my QR code encodes the add-friend link', (tester) async {
    final me = _user('1', 'me_user', '我');
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showMyFriendCode(context, me),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    final link = tester
        .widget<SelectableText>(find.byKey(const ValueKey('my-friend-link')))
        .data!;
    expect(link, FriendCode.linkFor('me_user'));
    expect(FriendCode.parse(link)?.username, 'me_user');
    expect(find.text('复制链接'), findsOneWidget);
  });

  group('ContactsPage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('扫一扫 opens the exact add-friend screen', (tester) async {
      final service = _Contacts(users: const []);
      await tester.pumpWidget(MaterialApp(
        home: ContactsPage(
          contactService: service,
          chatService: _EmptyChats(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('扫一扫'));
      await tester.pumpAndSettle();

      expect(find.byType(AddFriendScreen), findsOneWidget);
      expect(service.fuzzySearches, isEmpty);
    });

    testWidgets('friend list renders titles and avatar frames',
        (tester) async {
      final service = _Contacts(
        users: const [],
        friends: [_user('7', 'carol', '卡罗', title: '版主', frame: 'golden_ring')],
      );
      await tester.pumpWidget(MaterialApp(
        home: ContactsPage(
          contactService: service,
          chatService: _EmptyChats(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('卡罗'), findsOneWidget);
      final badge = tester.widget<PMTitleBadge>(find.byType(PMTitleBadge));
      expect(badge.title, '版主');
      expect(
        tester
            .widgetList<PMAvatarFrame>(find.byType(PMAvatarFrame))
            .map((frame) => frame.preset),
        contains('golden_ring'),
      );
    });
  });
}

Future<http.Response> _unused(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  throw UnimplementedError('$method $url');
}

class _Contacts extends ContactDataService {
  _Contacts({required this.users, this.friends = const []})
      : super(authenticatedRequest: _unused);

  final List<User> users;
  final List<User> friends;
  final List<String> lookups = [];
  final List<String> sentTo = [];
  final List<String> fuzzySearches = [];

  @override
  Future<User?> lookupUser({String? username, String? id}) async {
    if (username != null) {
      lookups.add('username:$username');
      for (final user in users) {
        if (user.username == username) return user;
      }
      return null;
    }
    lookups.add('id:$id');
    for (final user in users) {
      if (user.id == id) return user;
    }
    return null;
  }

  @override
  Future<List<User>> searchUsers(String keyword, {int limit = 20}) async {
    fuzzySearches.add(keyword);
    return users;
  }

  @override
  Future<List<User>> getFriends() async => friends;

  @override
  Future<List<FriendshipRequest>> getSentFriendRequests() async => const [];

  @override
  Future<List<FriendshipRequest>> getReceivedFriendRequests() async =>
      const [];

  @override
  Future<ContactGroupBundle> getContactGroups() async =>
      const ContactGroupBundle();

  @override
  Future<FriendshipRequest> sendFriendRequest(String userId) async {
    sentTo.add(userId);
    final target = users.firstWhere((user) => user.id == userId);
    return FriendshipRequest(
      id: 'r$userId',
      status: 'PENDING',
      user: _user('1', 'me', '我'),
      friend: target,
    );
  }
}

class _EmptyChats extends ChatDataService {
  _EmptyChats() : super(authenticatedRequest: _unused);

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
      const [];
}
