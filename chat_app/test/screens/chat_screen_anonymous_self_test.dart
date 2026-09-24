import 'dart:convert';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/chat_room_member.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/sticker.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 匿名消息对别人不再带真实 senderId，"是不是我发的"只能看服务器按人算的 sentByMe。
final _now = DateTime.parse('2024-01-01T10:00:00');

User _user(String id, String name) => User(
      id: id,
      username: 'u$id',
      email: '',
      displayName: name,
      createdAt: _now,
    );

/// 服务器下发的匿名消息：发送者本人拿到 sentByMe=true；别人拿到的没有任何真实身份。
Map<String, dynamic> _anonymousJson(
  int id,
  String content, {
  required bool sentByMe,
  String anonymousName = '匿名淡定羊驼',
}) =>
    {
      'id': id,
      'content': content,
      'senderId': null,
      'sender': null,
      'senderName': anonymousName,
      'chatRoomId': 10,
      'messageType': 'TEXT',
      'messageStatus': 'SENT',
      'createdAt': _now.add(Duration(minutes: id)).toIso8601String(),
      'isAnonymous': true,
      'anonymousIdentityId': 900 + id,
      'anonymousName': anonymousName,
      'anonymousAvatar': '#8B5CF6',
      'sentByMe': sentByMe,
    };

void main() {
  setUp(() {
    ChatScreen.clearMessageCacheForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  late AuthService auth;

  Future<void> signIn() async {
    auth = AuthService();
    await auth.replaceCurrentUser(_user('1', '我'));
    addTearDown(auth.clearLocalSession);
  }

  Chat groupChat() => Chat(
        id: '10',
        name: '匿名群',
        type: ChatType.group,
        createdAt: _now,
        createdBy: '2',
        participants: [_user('1', '我'), _user('2', '群主'), _user('3', '同事')],
      );

  Widget buildScreen(_FakeChatService service, WebSocketService socket) {
    return MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: RouteSettings(arguments: groupChat()),
        builder: (_) => ChatScreen(
          chatService: service,
          authService: auth,
          botService: _NoBotService(),
          contactService: _FakeContactService(),
          webSocketService: socket,
        ),
      ),
    );
  }

  MessageBubble bubbleOf(WidgetTester tester, String text) =>
      tester.widget<MessageBubble>(find.ancestor(
        of: find.text(text),
        matching: find.byType(MessageBubble),
      ));

  testWidgets(
      'my own anonymous message sits on the right with edit and recall, '
      'others\' anonymous messages stay on the left', (tester) async {
    await signIn();
    final service = _FakeChatService(messages: [
      Message.fromJson(_anonymousJson(1, '别人匿名说的', sentByMe: false,
          anonymousName: '匿名好奇海豹')),
      Message.fromJson(_anonymousJson(2, '我匿名说的', sentByMe: true)),
    ]);
    final socket = WebSocketService.forTesting(authService: auth);

    await tester.pumpWidget(buildScreen(service, socket));
    await tester.pumpAndSettle();

    expect(bubbleOf(tester, '我匿名说的').isMe, isTrue);
    expect(bubbleOf(tester, '别人匿名说的').isMe, isFalse);
    expect(find.text('匿名好奇海豹'), findsWidgets);

    await tester.longPress(find.text('我匿名说的'));
    await tester.pumpAndSettle();
    expect(find.text('撤回消息'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('别人匿名说的'));
    await tester.pumpAndSettle();
    expect(find.text('撤回消息'), findsNothing);
    expect(find.text('编辑'), findsNothing);
  });

  testWidgets('realtime anonymous frames align by sentByMe, not senderId',
      (tester) async {
    await signIn();
    final service = _FakeChatService(messages: const []);
    final socket = WebSocketService.forTesting(authService: auth);

    await tester.pumpWidget(buildScreen(service, socket));
    await tester.pumpAndSettle();

    // 本人会话收到的"本人版"：没有 senderId 也要认出是自己发的。
    socket.handleMessageForTest(jsonEncode({
      'type': 'message',
      'event': 'created',
      'message': _anonymousJson(5, '本人设备收到的匿名消息', sentByMe: true),
    }));
    // 其他成员收到的"公开版"。
    socket.handleMessageForTest(jsonEncode({
      'type': 'message',
      'event': 'created',
      'message': _anonymousJson(6, '其他人的匿名消息', sentByMe: false,
          anonymousName: '匿名好奇海豹'),
    }));
    await tester.pumpAndSettle();

    expect(bubbleOf(tester, '本人设备收到的匿名消息').isMe, isTrue);
    expect(bubbleOf(tester, '其他人的匿名消息').isMe, isFalse);
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

class _FakeChatService extends ChatDataService {
  _FakeChatService({required List<Message> messages})
      : messages = List<Message>.from(messages),
        super(authenticatedRequest: _unusedRequest);

  final List<Message> messages;

  @override
  Future<MessagePage> getMessagePage(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async =>
      MessagePage(
        messages: List<Message>.from(messages),
        currentPage: page,
        totalPages: 1,
        totalElements: messages.length,
        hasNext: false,
        hasPrevious: false,
      );

  @override
  Future<List<Message>> getMessageDelta(
    String chatRoomId, {
    required String afterMessageId,
    int size = 50,
  }) async =>
      const [];

  @override
  Future<List<ChatRoomMember>> getChatRoomMembers(String chatRoomId) async =>
      const [];

  @override
  Future<List<Message>> getPinnedMessages(String chatRoomId) async => const [];

  @override
  Future<void> markAllRead(String chatRoomId) async {}

  @override
  Future<void> markMessageRead(String messageId) async {}

  @override
  Future<List<StickerPack>> getStickerPacks() async => const [];
}

class _NoBotService extends BotService {
  @override
  Future<List<BotConfig>> getBotsInRoom(int roomId) async => const [];
}

class _FakeContactService extends ContactDataService {
  _FakeContactService() : super(authenticatedRequest: _unusedRequest);

  @override
  Future<List<User>> getFriends() async => const [];

  @override
  Future<List<FriendshipRequest>> getSentFriendRequests() async => const [];
}
