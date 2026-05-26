import 'package:chat_app/models/chat_room_member.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_room_settings_screen.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatRoomSettingsScreen', () {
    testWidgets('renders members and invite action for admin', (tester) async {
      final chatService = FakeChatDataService();
      final contactService = FakeContactDataService();

      await tester.pumpWidget(buildWidget(
        chatService: chatService,
        contactService: contactService,
      ));
      await tester.pumpAndSettle();

      expect(find.text('成员管理'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('邀请好友'), findsOneWidget);
    });

    testWidgets('invites a friend from the invite sheet', (tester) async {
      final chatService = FakeChatDataService();
      final contactService = FakeContactDataService();

      await tester.pumpWidget(buildWidget(
        chatService: chatService,
        contactService: contactService,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('邀请好友'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carol'));
      await tester.pumpAndSettle();

      expect(chatService.invitedUserIds, ['3']);
      expect(find.text('Carol'), findsOneWidget);
    });

    testWidgets('admin can toggle and kick a member', (tester) async {
      final chatService = FakeChatDataService();

      await tester.pumpWidget(buildWidget(chatService: chatService));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('设为管理员'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出群聊'));
      await tester.pumpAndSettle();

      expect(chatService.adminToggles, ['2']);
      expect(chatService.kickedUserIds, ['2']);
    });

    testWidgets('leave group calls service and pops settings', (tester) async {
      final chatService = FakeChatDataService();

      await tester.pumpWidget(buildWidget(chatService: chatService));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('退出群聊'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('退出群聊'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出').last);
      await tester.pumpAndSettle();

      expect(chatService.leftRooms, ['42']);
    });

    testWidgets('adds and removes room bots', (tester) async {
      final botService = FakeBotService();

      await tester.pumpWidget(buildWidget(
        botService: botService,
        enableBotLoading: true,
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('RoomBot'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('RoomBot'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('添加机器人'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('添加机器人'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AvailableBot'));
      await tester.pumpAndSettle();

      expect(botService.addedBotIds, [2]);
      expect(find.text('AvailableBot'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove_circle).first);
      await tester.pumpAndSettle();

      expect(botService.removedBotIds, [1]);
    });
  });
}

Widget buildWidget({
  FakeChatDataService? chatService,
  FakeContactDataService? contactService,
  FakeBotService? botService,
  bool enableBotLoading = false,
}) {
  return MaterialApp(
    home: ChatRoomSettingsScreen(
      chatRoomId: 42,
      chatRoomName: 'Project Room',
      isGroup: true,
      currentUserId: '1',
      chatService: chatService ?? FakeChatDataService(),
      contactService: contactService ?? FakeContactDataService(),
      botService: botService,
      enableBotLoading: enableBotLoading,
    ),
  );
}

class FakeChatDataService extends ChatDataService {
  final invitedUserIds = <String>[];
  final kickedUserIds = <String>[];
  final adminToggles = <String>[];
  final mutedUserIds = <String>[];
  final leftRooms = <String>[];

  List<ChatRoomMember> members = [
    member('1', 'alice', 'Alice', isAdmin: true),
    member('2', 'bob', 'Bob'),
  ];

  @override
  Future<List<ChatRoomMember>> getChatRoomMembers(String chatRoomId) async {
    return members;
  }

  @override
  Future<List<ChatRoomMember>> addChatRoomMember(
    String chatRoomId,
    String userId,
  ) async {
    invitedUserIds.add(userId);
    members = [...members, member(userId, 'carol', 'Carol')];
    return members;
  }

  @override
  Future<void> kickChatRoomMember(String chatRoomId, String userId) async {
    kickedUserIds.add(userId);
    members = members.where((member) => member.userId != userId).toList();
  }

  @override
  Future<void> toggleChatRoomAdmin(String chatRoomId, String userId) async {
    adminToggles.add(userId);
  }

  @override
  Future<void> toggleChatRoomMute(String chatRoomId, String userId) async {
    mutedUserIds.add(userId);
  }

  @override
  Future<void> leaveChatRoom(String chatRoomId) async {
    leftRooms.add(chatRoomId);
  }
}

class FakeContactDataService extends ContactDataService {
  @override
  Future<List<User>> getFriends() async {
    return [
      user('2', 'bob', 'Bob'),
      user('3', 'carol', 'Carol'),
    ];
  }
}

class FakeBotService extends BotService {
  final addedBotIds = <int>[];
  final removedBotIds = <int>[];
  final roomBots = <BotConfig>[
    BotConfig(id: 1, botName: 'RoomBot', llmProvider: 'OPENAI'),
  ];
  final myBots = <BotConfig>[
    BotConfig(id: 1, botName: 'RoomBot', llmProvider: 'OPENAI'),
    BotConfig(id: 2, botName: 'AvailableBot', llmProvider: 'OLLAMA'),
  ];

  @override
  Future<List<BotConfig>> getBotsInRoom(int roomId) async {
    return roomBots;
  }

  @override
  Future<List<BotConfig>> getMyBots() async {
    return myBots;
  }

  @override
  Future<bool> addBotToRoom(
    int roomId,
    int botId, {
    String? triggerMode,
    String? keywords,
  }) async {
    addedBotIds.add(botId);
    final bot = myBots.firstWhere((bot) => bot.id == botId);
    roomBots.add(bot);
    return true;
  }

  @override
  Future<bool> removeBotFromRoom(int roomId, int botId) async {
    removedBotIds.add(botId);
    roomBots.removeWhere((bot) => bot.id == botId);
    return true;
  }
}

ChatRoomMember member(
  String id,
  String username,
  String displayName, {
  bool isAdmin = false,
}) {
  return ChatRoomMember(
    id: 'member-$id',
    userId: id,
    user: user(id, username, displayName),
    role: isAdmin ? 'ADMIN' : 'MEMBER',
    roleDescription: isAdmin ? '管理员' : '普通成员',
    isAdmin: isAdmin,
  );
}

User user(String id, String username, String displayName) {
  return User(
    id: id,
    username: username,
    email: '$username@test.com',
    displayName: displayName,
    createdAt: DateTime(2024),
  );
}
