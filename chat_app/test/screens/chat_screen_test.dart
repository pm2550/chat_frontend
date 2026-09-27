import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:chat_app/design/design.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/models/call_state.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/sticker.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/chat_upload.dart';
import 'package:chat_app/services/chat_call_service.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/bot_service.dart';
import 'package:chat_app/services/pending_call_invite.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

part 'sub/chat_screen_test_cases_1.dart';
part 'sub/chat_screen_test_cases_2.dart';
part 'sub/chat_screen_test_cases_3.dart';
part 'sub/chat_screen_test_cases_4.dart';
part 'sub/chat_screen_test_fixtures_1.dart';

final testMessages = [
  Message(
    id: '1',
    content: '后端消息一',
    senderId: 'user2',
    senderName: '好友',
    chatRoomId: 'chat1',
    status: MessageStatus.sent,
    timestamp: DateTime.parse('2024-01-01T10:00:00'),
  ),
  Message(
    id: '2',
    content: '后端消息二',
    senderId: 'user1',
    senderName: '我',
    chatRoomId: 'chat1',
    status: MessageStatus.sent,
    timestamp: DateTime.parse('2024-01-01T10:01:00'),
  ),
];

Chat createTestChat({
  String id = 'chat1',
  String name = '测试聊天',
  ChatType type = ChatType.private,
  String participantId = 'user2',
}) {
  final now = DateTime.now();
  return Chat(
    id: id,
    name: name,
    type: type,
    createdAt: now,
    participants: [
      User(
        id: participantId,
        username: 'friend',
        email: 'friend@example.com',
        displayName: '好友',
        onlineStatus: OnlineStatus.online,
        createdAt: now,
      ),
    ],
  );
}

Widget buildTestWidget(
  Chat chat, {
  ChatDataService? chatService,
  ChatCallService? callService,
  ContactDataService? contactService,
  AuthService? authService,
  BotService? botService,
  WebSocketService? webSocketService,
  ChatAttachmentPicker? imagePicker,
  ChatAttachmentPicker? filePicker,
  Object? routeArguments,
}) {
  final effectiveWebSocketService = webSocketService ??
      WebSocketService.forTesting(authService: _NoSocketAuthService());
  return MaterialApp(
    home: Builder(
      builder: (context) {
        // We use a Navigator with an initial route that passes the Chat
        // as arguments to ChatScreen.
        return Navigator(
          onGenerateRoute: (settings) {
            return MaterialPageRoute(
              settings: RouteSettings(arguments: routeArguments ?? chat),
              builder: (context) => ChatScreen(
                chatService:
                    chatService ?? FakeChatDataService(messages: testMessages),
                callService: callService,
                contactService: contactService,
                authService: authService,
                botService: botService,
                webSocketService: effectiveWebSocketService,
                imagePicker: imagePicker,
                filePicker: filePicker,
              ),
            );
          },
        );
      },
    ),
  );
}

Widget buildRouteOnlyWidget(
  String routeName, {
  required ChatDataService chatService,
}) {
  return MaterialApp(
    home: Navigator(
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        MaterialPageRoute(
          settings: RouteSettings(name: routeName),
          builder: (context) => ChatScreen(chatService: chatService),
        ),
      ],
    ),
  );
}

Future<void> pumpChatOverBase(
  WidgetTester tester,
  Chat chat,
  ChatCallService callService,
) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    home: const Scaffold(body: Text('BASE PAGE')),
  ));
  navigatorKey.currentState!.push(MaterialPageRoute<void>(
    settings: RouteSettings(arguments: chat),
    builder: (_) => ChatScreen(
      chatService: FakeChatDataService(messages: testMessages),
      callService: callService,
      webSocketService:
          WebSocketService.forTesting(authService: _NoSocketAuthService()),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> pumpFrames(WidgetTester tester, {int frames = 40}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Map<String, dynamic> incomingInvite(String roomId) => {
      'type': 'call',
      'action': 'invite',
      'chatRoomId': int.parse(roomId),
      'callId': 'call-dialog',
      'fromUserId': 7,
      'fromName': '好友',
      'mediaType': 'AUDIO',
    };

void main() {
  setUp(ChatScreen.clearMessageCacheForTesting);
  group('ChatScreen', () {
    _chatScreenCases1();
    _chatScreenCases2();
    _chatScreenCases3();
    _chatScreenCases4();
  });
}
