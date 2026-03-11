import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/screens/chat/chat_screen.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/user.dart';
import 'package:chat_app/widgets/message_bubble.dart';

void main() {
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
  Widget buildTestWidget(Chat chat) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          // We use a Navigator with an initial route that passes the Chat
          // as arguments to ChatScreen.
          return Navigator(
            onGenerateRoute: (settings) {
              return MaterialPageRoute(
                settings: RouteSettings(arguments: chat),
                builder: (context) => const ChatScreen(),
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

    testWidgets('renders mock messages as MessageBubble widgets',
        (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // ChatScreen initializes with mock messages (some may be off-screen).
      expect(find.byType(MessageBubble), findsWidgets);
    });

    testWidgets('renders mock message content text', (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      // Verify some of the mock message content appears.
      expect(find.text('你好，今天有空吗？'), findsOneWidget);
      expect(find.text('有空的，什么事？'), findsOneWidget);
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

    testWidgets('renders add_circle_outline button for input options',
        (tester) async {
      final chat = createTestChat();

      await tester.pumpWidget(buildTestWidget(chat));
      await tester.pump();

      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
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
  });
}
