import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/design/design.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:chat_app/models/message.dart';

void main() {
  // Helper to create a Message for testing.
  Message createMessage({
    String id = '1',
    String content = 'Hello, world!',
    String senderId = 'user1',
    String senderName = 'Alice',
    String? senderAvatar,
    String chatRoomId = 'room1',
    MessageType type = MessageType.text,
    MessageStatus status = MessageStatus.sent,
    DateTime? timestamp,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? fileType,
    Message? replyToMessage,
    String? replyToId,
    bool isAnonymous = false,
    String? anonymousName,
    String? anonymousAvatar,
    LinkPreview? linkPreview,
  }) {
    return Message(
      id: id,
      content: content,
      senderId: senderId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      chatRoomId: chatRoomId,
      type: type,
      status: status,
      timestamp: timestamp ?? DateTime.now(),
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      fileType: fileType,
      replyToMessage: replyToMessage,
      replyToId: replyToId,
      replyToMessageId: replyToId,
      isAnonymous: isAnonymous,
      anonymousName: anonymousName,
      anonymousAvatar: anonymousAvatar,
      linkPreview: linkPreview,
    );
  }

  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('MessageBubble', () {
    testWidgets('renders message content text', (tester) async {
      final message = createMessage(content: '你好，世界！');

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false),
      ));

      expect(find.text('你好，世界！'), findsOneWidget);
    });

    testWidgets('loads and renders link preview for text messages',
        (tester) async {
      final message = createMessage(
        content: '看看 https://example.com/post',
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(
          message: message,
          isMe: false,
          linkPreviewLoader: (url) async {
            expect(url, 'https://example.com/post');
            return const LinkPreview(
              url: 'https://example.com/post',
              title: 'Example title',
              description: 'Example description',
              siteName: 'example.com',
            );
          },
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('看看 https://example.com/post'), findsOneWidget);
      expect(find.text('Example title'), findsOneWidget);
      expect(find.text('Example description'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('renders stored link preview without loader', (tester) async {
      final message = createMessage(
        content: '链接 https://example.com',
        linkPreview: const LinkPreview(
          url: 'https://example.com',
          title: 'Stored preview',
          siteName: 'example.com',
        ),
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false),
      ));

      expect(find.text('Stored preview'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('renders quoted reply block when replyToMessage is present',
        (tester) async {
      final quoted = createMessage(
        id: 'quoted-1',
        content: '这是被引用的原消息内容',
        senderName: '原作者',
      );
      final message = createMessage(
        content: '这是回复',
        replyToId: quoted.id,
        replyToMessage: quoted,
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false),
      ));

      expect(find.text('原作者'), findsOneWidget);
      expect(find.text('这是被引用的原消息内容'), findsOneWidget);
      expect(find.text('这是回复'), findsOneWidget);
    });

    testWidgets('highlights mentions and taps profile callback',
        (tester) async {
      String? tappedMention;
      final message = createMessage(content: '请看 @Alice 的更新');

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(
          message: message,
          isMe: false,
          onMentionTap: (label) => tappedMention = label,
        ),
      ));

      expect(find.text('@Alice'), findsOneWidget);
      await tester.tap(find.text('@Alice'));

      expect(tappedMention, 'Alice');
    });

    testWidgets('renders sent message (isMe=true) aligned to the right',
        (tester) async {
      final message = createMessage(content: 'My message');

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: true),
      ));

      // The outer Row should have MainAxisAlignment.end for sent messages.
      final row = tester.widget<Row>(find.byType(Row).first);
      expect(row.mainAxisAlignment, MainAxisAlignment.end);
    });

    testWidgets('renders received message (isMe=false) aligned to the left',
        (tester) async {
      final message = createMessage(content: 'Their message');

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false),
      ));

      final row = tester.widget<Row>(find.byType(Row).first);
      expect(row.mainAxisAlignment, MainAxisAlignment.start);
    });

    testWidgets('shows status icon for sent messages (isMe=true)',
        (tester) async {
      final message = createMessage(
        content: 'Sent message',
        status: MessageStatus.sent,
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: true),
      ));

      // MessageStatus.sent -> Icons.check
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('does not show status icon for received messages (isMe=false)',
        (tester) async {
      final message = createMessage(
        content: 'Received message',
        status: MessageStatus.sent,
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false),
      ));

      // No status icon should appear for received messages.
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('shows PMUserAvatar when showAvatar is true and isMe is false',
        (tester) async {
      final message = createMessage(
        content: 'Group message',
        senderName: 'Bob',
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false, showAvatar: true),
      ));

      // Non-anonymous avatars use the PM design-system avatar so frame
      // overlays can be applied consistently across the app.
      expect(find.byType(PMUserAvatar), findsOneWidget);
      // The avatar fallback shows first letter of senderName uppercased.
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('shows sender name when showAvatar is true and isMe is false',
        (tester) async {
      final message = createMessage(
        content: 'Group message',
        senderName: 'Charlie',
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false, showAvatar: true),
      ));

      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('does not show CircleAvatar when showAvatar is false',
        (tester) async {
      final message = createMessage(content: 'No avatar');

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false, showAvatar: false),
      ));

      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('shows PMUserAvatar for sent messages when showAvatar is true',
        (tester) async {
      final message = createMessage(
        content: 'My message',
        senderName: 'Me',
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: true, showAvatar: true),
      ));

      expect(find.byType(PMUserAvatar), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
    });

    testWidgets('shows anonymous avatar for sent anonymous messages',
        (tester) async {
      final message = createMessage(
        content: 'Anonymous message',
        senderName: '匿名鹿',
        isAnonymous: true,
        anonymousName: '匿名鹿',
        anonymousAvatar: '#7C3AED',
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: true, showAvatar: true),
      ));

      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.text('匿'), findsOneWidget);
      expect(find.byIcon(Icons.masks), findsWidgets);
    });

    testWidgets('displays formatted timestamp for today', (tester) async {
      final now = DateTime.now();
      final message = createMessage(
        content: 'Timed message',
        timestamp: DateTime(now.year, now.month, now.day, 14, 30),
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false),
      ));

      expect(find.text('14:30'), findsOneWidget);
    });

    testWidgets('displays date and time for messages not from today',
        (tester) async {
      // Use a date far in the past to guarantee it is not today.
      final pastDate = DateTime(2024, 3, 15, 9, 5);
      final message = createMessage(
        content: 'Old message',
        timestamp: pastDate,
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false),
      ));

      // Format: month/day HH:MM -> "3/15 09:05"
      expect(find.text('3/15 09:05'), findsOneWidget);
    });

    group('message status icons', () {
      testWidgets('sending status shows access_time icon', (tester) async {
        final message = createMessage(
          content: 'Sending...',
          status: MessageStatus.sending,
        );

        await tester.pumpWidget(buildTestWidget(
          MessageBubble(message: message, isMe: true),
        ));

        expect(find.byIcon(Icons.access_time), findsOneWidget);
      });

      testWidgets('sent status shows check icon', (tester) async {
        final message = createMessage(
          content: 'Sent',
          status: MessageStatus.sent,
        );

        await tester.pumpWidget(buildTestWidget(
          MessageBubble(message: message, isMe: true),
        ));

        expect(find.byIcon(Icons.check), findsOneWidget);
      });

      testWidgets('delivered status shows done_all icon', (tester) async {
        final message = createMessage(
          content: 'Delivered',
          status: MessageStatus.delivered,
        );

        await tester.pumpWidget(buildTestWidget(
          MessageBubble(message: message, isMe: true),
        ));

        expect(find.byIcon(Icons.done_all), findsOneWidget);
      });

      testWidgets('read status shows done_all icon', (tester) async {
        final message = createMessage(
          content: 'Read',
          status: MessageStatus.read,
        );

        await tester.pumpWidget(buildTestWidget(
          MessageBubble(message: message, isMe: true),
        ));

        expect(find.byIcon(Icons.done_all), findsOneWidget);
      });

      testWidgets('failed status shows error_outline icon', (tester) async {
        final message = createMessage(
          content: 'Failed',
          status: MessageStatus.failed,
        );

        await tester.pumpWidget(buildTestWidget(
          MessageBubble(message: message, isMe: true),
        ));

        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      });
    });

    testWidgets('sent message text color is white', (tester) async {
      final message = createMessage(content: 'White text');

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: true),
      ));

      final textWidget = tester.widget<Text>(find.text('White text'));
      expect(textWidget.style?.color, Colors.white);
    });

    testWidgets('avatar shows "?" when senderName is empty', (tester) async {
      final message = createMessage(
        content: 'No name',
        senderName: '',
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false, showAvatar: true),
      ));

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders image attachment preview and filename',
        (tester) async {
      final message = createMessage(
        content: 'photo.png',
        type: MessageType.image,
        fileUrl: '/api/files/chat/photo.png',
        fileName: 'photo.png',
        fileSize: 2048,
        fileType: 'image/png',
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(
          message: message,
          isMe: false,
          imageLoader: (_) async => Uint8List.fromList([
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
            0,
            0,
            0,
            13,
            73,
            72,
            68,
            82,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            1,
            8,
            6,
            0,
            0,
            0,
            31,
            21,
            196,
            137,
            0,
            0,
            0,
            13,
            73,
            68,
            65,
            84,
            120,
            156,
            99,
            248,
            207,
            192,
            80,
            15,
            0,
            5,
            131,
            2,
            127,
            150,
            236,
            250,
            87,
            0,
            0,
            0,
            0,
            73,
            69,
            78,
            68,
            174,
            66,
            96,
            130,
          ]),
        ),
      ));
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('photo.png'), findsOneWidget);
    });

    testWidgets('tapping image attachment opens attachment action',
        (tester) async {
      final message = createMessage(
        content: 'photo.png',
        type: MessageType.image,
        fileUrl: '/api/files/chat/photo.png',
        fileName: 'photo.png',
        fileType: 'image/png',
      );
      Message? opened;

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(
          message: message,
          isMe: false,
          imageLoader: (_) async => Uint8List.fromList([
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
            0,
            0,
            0,
            13,
            73,
            72,
            68,
            82,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            1,
            8,
            6,
            0,
            0,
            0,
            31,
            21,
            196,
            137,
            0,
            0,
            0,
            13,
            73,
            68,
            65,
            84,
            120,
            156,
            99,
            248,
            207,
            192,
            80,
            15,
            0,
            5,
            131,
            2,
            127,
            150,
            236,
            250,
            87,
            0,
            0,
            0,
            0,
            73,
            69,
            78,
            68,
            174,
            66,
            96,
            130,
          ]),
          onOpenAttachment: (message) async {
            opened = message;
          },
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
      await tester.tap(find.byType(Image));
      await tester.pump();

      expect(opened, message);
    });

    testWidgets('renders file attachment card with size and download icon',
        (tester) async {
      final message = createMessage(
        content: 'doc.pdf',
        type: MessageType.file,
        fileUrl: '/api/files/chat/doc.pdf',
        fileName: 'doc.pdf',
        fileSize: 2048,
        fileType: 'application/pdf',
      );

      await tester.pumpWidget(buildTestWidget(
        MessageBubble(message: message, isMe: false),
      ));

      expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(find.text('[文件] doc.pdf'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
    });
  });
}
