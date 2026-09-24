import 'dart:convert';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/services/encryption_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:chat_app/widgets/e2ee_widgets.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_e2ee_server.dart';
import '../support/fake_web_socket_channel.dart';
import 'chat_screen_test.dart' show FakeChatDataService;

/// 私聊端到端加密在聊天页上：头部的锁、提示条、发送只发密文、收到的密文能显示成明文。
void main() {
  late FakeE2eeServer server;

  setUp(() {
    ChatScreen.clearMessageCacheForTesting();
    SharedPreferences.setMockInitialValues({});
    server = FakeE2eeServer()
      ..passwords['user1'] = 'me-pw'
      ..passwords['user2'] = 'friend-pw'
      ..roomMembers['1'] = ['user1', 'user2'];
  });

  tearDown(() => Message.contentRevealer = null);

  Chat room() => Chat(
        id: '1',
        name: '测试聊天',
        type: ChatType.private,
        createdAt: DateTime.parse('2024-01-01T09:00:00'),
        participants: [
          User(
            id: 'user2',
            username: 'friend',
            email: 'friend@example.com',
            displayName: '好友',
            createdAt: DateTime.parse('2024-01-01T09:00:00'),
          ),
        ],
      );

  Future<(FakeWebSocketChannel, WebSocketService)> pumpChat(
    WidgetTester tester,
    EncryptionService me, {
    FakeChatDataService? chatService,
  }) async {
    final channel = FakeWebSocketChannel();
    final socket = WebSocketService.forTesting(
      authService: SocketAuthService(),
      channelFactory: (_) => channel,
    );
    final chat = room();
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: RouteSettings(arguments: chat),
          builder: (context) => ChatScreen(
            chatService: chatService ?? FakeChatDataService(messages: const []),
            authService: SocketAuthService(),
            webSocketService: socket,
            encryptionService: me,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (channel, socket);
  }

  Future<void> finish(WidgetTester tester, WebSocketService socket) async {
    socket.disconnect();
    await tester.pumpWidget(const SizedBox());
  }

  Map<String, dynamic> serverMessage(
    String id, {
    required String senderId,
    required String envelope,
  }) =>
      {
        'id': id,
        'content': kE2eeServerPlaceholder,
        'senderId': senderId,
        'senderName': senderId == 'user1' ? '我' : '好友',
        'chatRoomId': 1,
        'messageType': 'TEXT',
        'messageStatus': 'SENT',
        'encryptedContent': envelope,
        'encryptionVersion': kE2eeEncryptionVersion,
        'createdAt': '2024-01-01T10:05:00',
      };

  testWidgets(
      'both sides enabled: lock in the header, only ciphertext leaves the device, replies decrypt',
      (tester) async {
    final me = e2eeDevice(server, 'user1');
    final friend = e2eeDevice(server, 'user2');
    await tester.runAsync(() async {
      await me.enable('me-pw');
      await friend.enable('friend-pw');
      await friend.roomState(room(), refresh: true);
    });
    Message.contentRevealer = me.reveal;

    final (channel, socket) = await pumpChat(tester, me);
    expect(find.byKey(const ValueKey('e2ee-header-badge')), findsOneWidget);
    expect(find.text('端到端加密'), findsOneWidget);
    expect(find.byKey(const ValueKey('e2ee-room-notice')), findsNothing);

    await tester.enterText(find.byType(TextField), '周五老地方见');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final frame = channel.sent.lastWhere((f) => f['type'] == 'message');
    expect(frame['content'], kE2eeServerPlaceholder);
    expect(frame['encryptionVersion'], kE2eeEncryptionVersion);
    final envelope = frame['encryptedContent'] as String;
    expect(utf8.decode(base64Decode(envelope)), isNot(contains('老地方')));
    expect(jsonEncode(frame), isNot(contains('老地方')));

    // 服务器回显（只有密文）：本机解开后显示明文，并带锁。
    channel.serverSends({
      'type': 'message',
      'event': 'created',
      'clientMessageId': frame['clientMessageId'],
      'message': serverMessage('100', senderId: 'user1', envelope: envelope),
    });
    await tester.pumpAndSettle();
    expect(find.text('周五老地方见'), findsOneWidget);
    expect(find.text(kE2eeServerPlaceholder), findsNothing);
    expect(find.byKey(const ValueKey('message-e2ee-lock')), findsOneWidget);

    // 对方用自己的设备回一条。
    final reply = await tester.runAsync(
      () => friend.sealText(room(), '收到，不见不散'),
    );
    channel.serverSends({
      'type': 'message',
      'event': 'created',
      'message': serverMessage('101', senderId: 'user2', envelope: reply!),
    });
    await tester.pumpAndSettle();
    expect(find.text('收到，不见不散'), findsOneWidget);
    expect(find.byKey(const ValueKey('message-e2ee-lock')), findsNWidgets(2));
    await finish(tester, socket);
  });

  testWidgets(
      'peer has not enabled encryption: notice shown, message goes out as plaintext',
      (tester) async {
    final me = e2eeDevice(server, 'user1');
    await tester.runAsync(() => me.enable('me-pw'));

    final (channel, socket) = await pumpChat(tester, me);
    expect(find.text('对方尚未启用端到端加密，消息未加密'), findsOneWidget);
    expect(find.byKey(const ValueKey('e2ee-header-badge')), findsNothing);

    await tester.enterText(find.byType(TextField), '普通消息');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final frame = channel.sent.lastWhere((f) => f['type'] == 'message');
    expect(frame['content'], '普通消息');
    expect(frame.containsKey('encryptedContent'), isFalse);
    await finish(tester, socket);
  });

  testWidgets(
      'a device that has not unlocked its key refuses to send plaintext',
      (tester) async {
    final myPhone = e2eeDevice(server, 'user1');
    await tester.runAsync(() async {
      await myPhone.enable('me-pw');
      await e2eeDevice(server, 'user2').enable('friend-pw');
    });
    final myLaptop = e2eeDevice(server, 'user1'); // 这台还没输过密码

    final (channel, socket) = await pumpChat(tester, myLaptop);
    expect(find.byKey(const ValueKey('e2ee-room-notice')), findsOneWidget);
    expect(find.widgetWithText(TextButton, '解锁'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '不能明文发出去');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(channel.sent.where((f) => f['type'] == 'message'), isEmpty);
    expect(find.textContaining('尚未解锁端到端加密'), findsWidgets);
    await finish(tester, socket);
  });

  testWidgets(
      'editing an encrypted message re-encrypts it; forwarding re-sends instead of copying ciphertext',
      (tester) async {
    final me = e2eeDevice(server, 'user1');
    final friend = e2eeDevice(server, 'user2');
    final original = await tester.runAsync(() async {
      await me.enable('me-pw');
      await friend.enable('friend-pw');
      await friend.roomState(room(), refresh: true);
      await me.roomState(room(), refresh: true);
      return me.sealText(room(), '原来的话');
    });
    Message.contentRevealer = me.reveal;
    final mine = Message.fromJson(
        serverMessage('50', senderId: 'user1', envelope: original!));
    expect(mine.content, '原来的话');

    final group = Chat(
      id: '9',
      name: '项目群',
      type: ChatType.group,
      createdAt: DateTime.parse('2024-01-01T09:00:00'),
    );
    final service = _RecordingChatService(messages: [mine], rooms: [group]);
    final (_, socket) = await pumpChat(tester, me, chatService: service);
    expect(find.text('原来的话'), findsOneWidget);

    // 编辑：发出去的是重新加密的密文，对方能解出新内容。
    await tester.longPress(find.text('原来的话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '改过的话');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final edit = service.edits.single;
    expect(edit.encryptedContent, isNotNull);
    expect(utf8.decode(base64Decode(edit.encryptedContent!)),
        isNot(contains('改过')));
    final forFriend = Message.fromJson(serverMessage('50',
        senderId: 'user1', envelope: edit.encryptedContent!));
    expect(friend.reveal(forFriend).content, '改过的话');

    // 转发到群聊：不让服务器照搬密文（谁也解不开），而是用本机明文重新发一条。
    await tester.longPress(find.text('改过的话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('转发'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目群'));
    await tester.pumpAndSettle();

    expect(service.serverForwards, isEmpty);
    expect(service.sentTexts, ['改过的话']);
    expect(service.sentEncryptedContents, [null]);
    await finish(tester, socket);
  });

  testWidgets('links inside encrypted messages are never sent to the server for a preview',
      (tester) async {
    final me = e2eeDevice(server, 'user1');
    final friend = e2eeDevice(server, 'user2');
    final sealed = await tester.runAsync(() async {
      await me.enable('me-pw');
      await friend.enable('friend-pw');
      await friend.roomState(room(), refresh: true);
      await me.roomState(room(), refresh: true);
      return friend.sealText(room(), '看这个 https://example.com/private-doc');
    });
    Message.contentRevealer = me.reveal;
    final incoming = Message.fromJson(
        serverMessage('60', senderId: 'user2', envelope: sealed!));
    final service = _RecordingChatService(messages: [incoming], rooms: const []);

    final (_, socket) = await pumpChat(tester, me, chatService: service);
    expect(find.textContaining('private-doc'), findsOneWidget);
    expect(service.previewRequests, isEmpty);
    await finish(tester, socket);
  });

  testWidgets('old clients see the server placeholder instead of ciphertext',
      (tester) async {
    // 老版本没有解密钩子：直接显示服务器写在 content 里的那句话。
    final message = Message.fromJson(serverMessage(
      '9',
      senderId: 'user2',
      envelope: base64Encode(utf8.encode('{"v":2}')),
    ));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MessageBubble(message: message, isMe: false)),
    ));
    expect(find.text('[加密消息，请更新到最新版本查看]'), findsOneWidget);
  });

  testWidgets('notice bar offers unlock only when the device is locked',
      (tester) async {
    var unlockTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            E2eeRoomNoticeBar(
              state: const E2eeRoomState(E2eeRoomMode.needsUnlock),
              onUnlock: () => unlockTaps++,
            ),
            const E2eeRoomNoticeBar(state: E2eeRoomState(E2eeRoomMode.active)),
            const E2eeHeaderBadge(state: E2eeRoomState(E2eeRoomMode.peerOff)),
          ],
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('e2ee-room-notice')), findsOneWidget);
    expect(find.byKey(const ValueKey('e2ee-header-badge')), findsNothing);
    await tester.tap(find.text('解锁'));
    expect(unlockTaps, 1);
  });
}

class _RecordingChatService extends FakeChatDataService {
  _RecordingChatService({required super.messages, required this.rooms});

  final List<Chat> rooms;
  final List<({String id, String content, String? encryptedContent})> edits =
      [];
  final List<String> serverForwards = [];
  final List<String> previewRequests = [];

  @override
  Future<LinkPreview> fetchUrlPreview(String url) async {
    previewRequests.add(url);
    return LinkPreview(url: url, title: 'leaked');
  }

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
      rooms;

  @override
  Future<Message> editMessage(
    String messageId,
    String content, {
    String? encryptedContent,
  }) async {
    edits.add((
      id: messageId,
      content: content,
      encryptedContent: encryptedContent,
    ));
    return Message.fromJson({
      'id': messageId,
      'content': kE2eeServerPlaceholder,
      'senderId': 'user1',
      'chatRoomId': 1,
      'messageType': 'TEXT',
      'encryptedContent': encryptedContent,
      'encryptionVersion': kE2eeEncryptionVersion,
      'isEdited': true,
      'editedAt': '2024-01-01T10:06:00',
      'createdAt': '2024-01-01T10:05:00',
    });
  }

  @override
  Future<Message> forwardMessage(
    String messageId,
    String targetChatRoomId,
  ) async {
    serverForwards.add(messageId);
    throw UnimplementedError();
  }
}
