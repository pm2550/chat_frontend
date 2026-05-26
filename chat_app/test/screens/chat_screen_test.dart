import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/widgets/message_bubble.dart';

void main() {
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

  // Create a test Chat object with participants.
  Chat createTestChat({
    String name = '测试聊天',
    ChatType type = ChatType.private,
  }) {
    final now = DateTime.now();
    return Chat(
      id: 'chat1',
      name: name,
      type: type,
      createdAt: now,
      participants: [
        User(
          id: 'user2',
          username: 'friend',
          email: 'friend@example.com',
          displayName: '好友',
          onlineStatus: OnlineStatus.online,
          createdAt: now,
        ),
      ],
    );
  }

  /// Builds the ChatScreen inside a MaterialApp, passing the Chat object
  /// via route settings arguments (as ChatScreen reads it from ModalRoute).
  Widget buildTestWidget(
    Chat chat, {
    ChatDataService? chatService,
    ChatAttachmentPicker? imagePicker,
    ChatAttachmentPicker? filePicker,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          // We use a Navigator with an initial route that passes the Chat
          // as arguments to ChatScreen.
          return Navigator(
            onGenerateRoute: (settings) {
              return MaterialPageRoute(
                settings: RouteSettings(arguments: chat),
                builder: (context) => ChatScreen(
                  chatService: chatService ??
                      FakeChatDataService(messages: testMessages),
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

  group('ChatScreen', () {
    testWidgets('renders chat name in app bar', (tester) async {
      final chat = createTestChat(name: '李四');

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.text('李四'), findsOneWidget);
    });

    testWidgets('renders message input hint text', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.text('输入消息...'), findsOneWidget);
    });

    testWidgets('renders a TextField for message input', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders mic button initially (no text typed)', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // When no text is entered, should show mic button instead of send.
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('shows send button when text is typed', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // Type some text in the input field.
      await tester.enterText(find.byType(TextField), '你好');
      await tester.pump();

      // Now the send icon should appear.
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
    });

    testWidgets('renders loaded messages as MessageBubble widgets',
        (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byType(MessageBubble), findsWidgets);
    });

    testWidgets('renders loaded message content text', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.text('后端消息一'), findsOneWidget);
      expect(find.text('后端消息二'), findsOneWidget);
    });

    testWidgets('renders app bar action buttons (call, video, more)',
        (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byIcon(Icons.call), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('renders add button for input options', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows online status for private chat with online participant',
        (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.text('在线'), findsOneWidget);
    });

    testWidgets('renders participant count for group chats', (tester) async {
      final now = DateTime.now();
      final groupChat = Chat(
        id: 'group1',
        name: '测试群组',
        type: ChatType.group,
        createdAt: now,
        participants: [
          User(
            id: 'u1',
            username: 'user1',
            email: 'u1@test.com',
            displayName: '用户1',
            createdAt: now,
          ),
          User(
            id: 'u2',
            username: 'user2',
            email: 'u2@test.com',
            displayName: '用户2',
            createdAt: now,
          ),
          User(
            id: 'u3',
            username: 'user3',
            email: 'u3@test.com',
            displayName: '用户3',
            createdAt: now,
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(groupChat));
      await tester.pump();

      expect(find.text('3人'), findsOneWidget);
    });

    testWidgets('renders CircleAvatar in app bar', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // The app bar shows a CircleAvatar for the chat.
      expect(find.byType(CircleAvatar), findsWidgets);
    });

    testWidgets('shows ListView for messages', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('can type message and see send button appear', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // Verify initial state has mic button.
      expect(find.byIcon(Icons.mic), findsOneWidget);

      // Enter text.
      await tester.enterText(find.byType(TextField), '新消息');
      await tester.pump();

      // Send button should now be visible.
      expect(find.byIcon(Icons.send), findsOneWidget);

      // Clear text.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      // Mic button should come back.
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('shows failed message when REST fallback send fails',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(
        messages: const [],
        sendError: Exception('network down'),
      );

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '发送失败消息');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(find.text('发送失败消息'), findsOneWidget);
      expect(find.text('发送失败: Exception: network down'), findsOneWidget);
    });

    testWidgets('picks image and sends file message', (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(messages: const []);

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: service,
        imagePicker: () async => const PickedChatFile(
          name: 'photo.png',
          size: 3,
          mimeType: 'image/png',
          bytes: [1, 2, 3],
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相册'));
      await tester.pump();

      expect(service.sentFiles.single.name, 'photo.png');
      expect(find.text('photo.png'), findsOneWidget);
    });

    testWidgets('picks generic file and shows failed file message on error',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(
        messages: const [],
        sendFileError: Exception('upload down'),
      );

      await tester.pumpWidget(buildTestWidget(
        chat,
        chatService: service,
        filePicker: () async => const PickedChatFile(
          name: 'doc.pdf',
          size: 2048,
          mimeType: 'application/pdf',
          bytes: [1, 2, 3],
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件'));
      await tester.pump();

      expect(find.text('[文件] doc.pdf'), findsOneWidget);
      expect(find.text('文件发送失败: Exception: upload down'), findsOneWidget);
    });

    testWidgets('searches chat history from chat options', (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(
        messages: const [],
        searchResults: [
          Message(
            id: 's1',
            content: 'needle result',
            senderId: 'user2',
            senderName: '好友',
            chatRoomId: 'chat1',
            status: MessageStatus.sent,
            timestamp: DateTime.parse('2024-01-01T10:03:00'),
          ),
        ],
      );

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索聊天记录'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'needle');
      await tester.tap(find.byIcon(Icons.arrow_forward));
      await tester.pumpAndSettle();

      expect(service.searchKeywords, ['needle']);
      expect(find.text('needle result'), findsOneWidget);
    });

    testWidgets('long press deletes a message locally after backend success',
        (tester) async {
      final chat = createTestChat();
      final service = FakeChatDataService(messages: testMessages);

      await tester.pumpWidget(buildTestWidget(chat, chatService: service));
      await tester.pump();

      await tester.longPress(find.text('后端消息一'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除消息'));
      await tester.pumpAndSettle();

      expect(service.deletedMessageIds, ['1']);
      expect(find.text('[消息已删除]'), findsOneWidget);
    });
  });
}

class FakeChatDataService extends ChatDataService {
  FakeChatDataService({
    required this.messages,
    this.searchResults = const [],
    this.sendError,
    this.sendFileError,
  }) : super(authenticatedRequest: _unusedRequest);

  final List<Message> messages;
  final List<Message> searchResults;
  final Object? sendError;
  final Object? sendFileError;
  final List<PickedChatFile> sentFiles = [];
  final List<String> searchKeywords = [];
  final List<String> deletedMessageIds = [];
  final List<String> recalledMessageIds = [];
  bool markAllReadCalled = false;

  static Future<dynamic> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MessagePage> getMessagePage(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    return MessagePage(
      messages: messages,
      currentPage: page,
      totalPages: 1,
      totalElements: messages.length,
      hasNext: false,
      hasPrevious: page > 0,
    );
  }

  @override
  Future<List<Message>> getMessages(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    return messages;
  }

  @override
  Future<MessagePage> searchMessages(
    String chatRoomId,
    String keyword, {
    int page = 0,
    int size = 20,
  }) async {
    searchKeywords.add(keyword);
    return MessagePage(
      messages: searchResults,
      currentPage: page,
      totalPages: 1,
      totalElements: searchResults.length,
      hasNext: false,
      hasPrevious: false,
    );
  }

  @override
  Future<Message> deleteMessage(String messageId) async {
    deletedMessageIds.add(messageId);
    final message = messages.firstWhere((message) => message.id == messageId);
    return message.copyWith(
      content: '[消息已删除]',
      isDeleted: true,
      chatRoomId: message.chatRoomId,
    );
  }

  @override
  Future<Message> recallMessage(String messageId) async {
    recalledMessageIds.add(messageId);
    final message = messages.firstWhere((message) => message.id == messageId);
    return message.copyWith(
      content: '[消息已撤回]',
      isDeleted: true,
      isRecalled: true,
      chatRoomId: message.chatRoomId,
    );
  }

  @override
  Future<void> markAllRead(String chatRoomId) async {
    markAllReadCalled = true;
  }

  @override
  Future<Message> sendTextMessage(
    String chatRoomId,
    String content, {
    bool isAnonymous = false,
  }) async {
    final error = sendError;
    if (error != null) {
      throw error;
    }
    return Message(
      id: 'sent-1',
      content: content,
      senderId: 'user1',
      senderName: isAnonymous ? '匿名用户' : '我',
      chatRoomId: chatRoomId,
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
      isAnonymous: isAnonymous,
      anonymousName: isAnonymous ? '匿名用户' : null,
    );
  }

  @override
  Future<Message> sendFileMessage(
    String chatRoomId,
    PickedChatFile file, {
    MessageType? messageType,
    String? encryptedContent,
    int? encryptionVersion,
  }) async {
    sentFiles.add(file);
    final error = sendFileError;
    if (error != null) {
      throw error;
    }
    final isImage = file.mimeType?.startsWith('image/') == true ||
        file.name.toLowerCase().endsWith('.png');
    return Message(
      id: 'file-1',
      content: file.name,
      senderId: 'user1',
      senderName: '我',
      chatRoomId: chatRoomId,
      type: messageType ?? (isImage ? MessageType.image : MessageType.file),
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
      fileUrl: '/api/files/chat/${file.name}',
      fileName: file.name,
      fileSize: file.size,
      fileType: file.mimeType,
    );
  }

  @override
  Future<DownloadedChatFile> downloadFile(Message message) async {
    return DownloadedChatFile(
      name: message.fileName ?? message.content,
      bytes: const [1, 2, 3],
      mimeType: message.fileType,
    );
  }
}
