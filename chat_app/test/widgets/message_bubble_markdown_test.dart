import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:chat_app/models/message.dart';

void main() {
  Message botMessage({
    required String content,
    MessageContentFormat contentFormat = MessageContentFormat.plain,
  }) {
    return Message(
      id: '1',
      content: content,
      senderId: 'user1',
      senderName: 'owner',
      botConfigId: '7',
      botSenderId: '7',
      botName: 'Searcher',
      chatRoomId: 'room1',
      type: MessageType.text,
      contentFormat: contentFormat,
      status: MessageStatus.sent,
      timestamp: DateTime(2026, 1, 1),
    );
  }

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders a GFM table for a MARKDOWN bot message', (tester) async {
    final message = botMessage(
      content: '| a | b |\n|---|---|\n| 1 | 2 |',
      contentFormat: MessageContentFormat.markdown,
    );

    await tester.pumpWidget(wrap(MessageBubble(message: message, isMe: false)));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(Table), findsWidgets);
  });

  testWidgets('plain bot message does NOT use the markdown renderer',
      (tester) async {
    final message = botMessage(content: 'just plain text');

    await tester.pumpWidget(wrap(MessageBubble(message: message, isMe: false)));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsNothing);
    expect(find.textContaining('just plain text'), findsWidgets);
  });
}
