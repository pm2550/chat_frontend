import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/contact_group.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/contacts_page.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget buildTestWidget(
    ContactDataService service, {
    ChatDataService? chatService,
  }) {
    return MaterialApp(
      onGenerateRoute: (settings) {
        if ((settings.name ?? '').startsWith('/chat')) {
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
      ),
    );
  }

  group('ContactsPage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
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
      expect(find.text('alice@example.com'), findsOneWidget);
    });

    testWidgets('renders empty state when there are no contacts',
        (tester) async {
      final service = FakeContactService();

      await tester.pumpWidget(buildTestWidget(service));
      await tester.pump();

      expect(find.text('暂无联系人'), findsOneWidget);
    });

    testWidgets(
        'renders joined group and private chats including blocked rooms',
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
        privateChats: [
          Chat(
            id: '11',
            name: 'Blocked DM',
            type: ChatType.private,
            isBlocked: true,
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
      expect(find.text('私聊'), findsWidgets);
      expect(find.text('Blocked DM'), findsOneWidget);
      expect(find.text('已屏蔽'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('解除屏蔽'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -140));
      await tester.pumpAndSettle();
      await tester.tap(find.text('解除屏蔽'));
      await tester.pumpAndSettle();

      expect(chatService.unblockedRoomIds, ['11']);
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
      expect(find.text('移动到分组'), findsOneWidget);

      await tester.tap(find.text('核心').last);
      await tester.pumpAndSettle();

      expect(service.assignmentCalls, ['FRIEND:2:7']);
      expect(find.text('Bob'), findsOneWidget);
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
    this.privateChats = const [],
  }) : super(authenticatedRequest: FakeContactService._unusedRequest);

  final List<Chat> groupChats;
  final List<Chat> privateChats;
  final List<String> unblockedRoomIds = [];

  @override
  Future<List<Chat>> getChatRooms({
    int page = 0,
    int size = 30,
    bool includeDetails = true,
    int detailLimit = 8,
    bool includeHidden = false,
    bool includeBlocked = false,
    ChatType? type,
  }) async {
    expect(includeHidden, isTrue);
    expect(includeBlocked, isTrue);
    if (type == ChatType.group) {
      return groupChats;
    }
    if (type == ChatType.private) {
      return privateChats;
    }
    return const [];
  }

  @override
  Future<void> unblockChatRoom(String chatRoomId) async {
    unblockedRoomIds.add(chatRoomId);
  }
}
