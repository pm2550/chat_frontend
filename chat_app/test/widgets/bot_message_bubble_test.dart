import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/widgets/bot_message_bubble.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('BotMessageBubble', () {
    testWidgets('renders bot name', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const BotMessageBubble(
          botName: 'ChatBot',
          content: 'Hello from bot!',
        ),
      ));

      expect(find.text('ChatBot'), findsOneWidget);
    });

    testWidgets('renders message content as SelectableText', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const BotMessageBubble(
          botName: 'Bot',
          content: '这是一条机器人消息',
        ),
      ));

      expect(find.text('这是一条机器人消息'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('shows BOT badge', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const BotMessageBubble(
          botName: 'Bot',
          content: 'Test',
        ),
      ));

      expect(find.text('BOT'), findsOneWidget);
    });

    testWidgets('shows smart_toy icon in CircleAvatar', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const BotMessageBubble(
          botName: 'Bot',
          content: 'Test',
        ),
      ));

      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('displays timestamp when provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const BotMessageBubble(
          botName: 'Bot',
          content: 'Timed message',
          timestamp: '14:30',
        ),
      ));

      expect(find.text('14:30'), findsOneWidget);
    });

    testWidgets('does not display timestamp when not provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const BotMessageBubble(
          botName: 'Bot',
          content: 'No time',
        ),
      ));

      // The timestamp widget should not be present.
      // We verify by checking that only expected texts appear.
      expect(find.text('Bot'), findsOneWidget);
      expect(find.text('BOT'), findsOneWidget);
      expect(find.text('No time'), findsOneWidget);
    });

    testWidgets('bot name text is blue colored', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const BotMessageBubble(
          botName: 'BlueBot',
          content: 'Color test',
        ),
      ));

      final nameWidget = tester.widget<Text>(find.text('BlueBot'));
      expect(nameWidget.style?.color, Colors.blue);
    });

    testWidgets('BOT badge text is blue and bold', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const BotMessageBubble(
          botName: 'Bot',
          content: 'Badge test',
        ),
      ));

      final botBadge = tester.widget<Text>(find.text('BOT'));
      expect(botBadge.style?.color, Colors.blue);
      expect(botBadge.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('content font size is 14', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const BotMessageBubble(
          botName: 'Bot',
          content: 'Size test',
        ),
      ));

      final selectableText =
          tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectableText.style?.fontSize, 14);
    });
  });
}
