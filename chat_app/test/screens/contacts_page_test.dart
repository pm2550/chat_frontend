import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/contacts_page.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  Widget buildTestWidget(ContactDataService service) {
    return MaterialApp(
      routes: {
        '/chat': (context) => const Scaffold(body: Text('Chat Page')),
      },
      home: ContactsPage(contactService: service),
    );
  }

  group('ContactsPage', () {
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
      expect(find.text('alice@example.com'), findsOneWidget);
    });

    testWidgets('renders empty state when there are no contacts',
        (tester) async {
      final service = FakeContactService();

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.text('暂无联系人'), findsOneWidget);
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

      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(service.sentRequestUserIds, ['3']);
      expect(find.text('已发送'), findsOneWidget);
    });

    testWidgets('starts private chat from contact options', (tester) async {
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
      await tester.tap(find.byIcon(Icons.chat));
      await tester.pumpAndSettle();

      expect(service.privateChatUserIds, ['4']);
      expect(find.text('Chat Page'), findsOneWidget);
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
      await tester.tap(find.text('Carol'));
      await tester.pumpAndSettle();

      expect(find.text('手机号'), findsOneWidget);
      expect(find.text('555-0101'), findsWidgets);
      expect(find.text('简介'), findsOneWidget);
      expect(find.text('Design lead'), findsOneWidget);

      await tester.tap(find.text('删除好友'));
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
    this.searchResults = const [],
    this.createdChat,
    this.error,
  })  : friends = friends ?? [],
        receivedRequests = receivedRequests ?? [],
        super(authenticatedRequest: _unusedRequest);

  List<User> friends;
  List<FriendshipRequest> receivedRequests;
  final List<User> searchResults;
  final Chat? createdChat;
  final Object? error;
  final List<String> acceptedUserIds = [];
  final List<String> declinedUserIds = [];
  final List<String> sentRequestUserIds = [];
  final List<String> privateChatUserIds = [];
  final List<String> searchKeywords = [];
  final List<String> removedUserIds = [];

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
}
