import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/widgets/typing_indicator.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  // TypingIndicator uses repeating AnimationControllers and Future.delayed,
  // which create persistent timers. We must replace the widget before the
  // test ends so that dispose() is called, and use pump() instead of
  // pumpAndSettle() since the animations never settle.

  Future<void> disposeWidget(WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget(const SizedBox()));
    await tester.pump(const Duration(milliseconds: 700));
  }

  group('TypingIndicator', () {
    testWidgets('shows user name followed by "正在输入"', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TypingIndicator(userName: '张三'),
      ));
      await tester.pump();

      expect(find.text('张三 正在输入'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('shows "正在输入" without user name when userName is null',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TypingIndicator(),
      ));
      await tester.pump();

      expect(find.text('正在输入'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('shows edit icon for non-bot typing indicator', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TypingIndicator(userName: 'User'),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('shows smart_toy icon for bot typing indicator',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TypingIndicator(userName: 'Bot', isBot: true),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('renders three animated dots', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TypingIndicator(userName: 'Test'),
      ));
      await tester.pump();

      expect(find.text('.'), findsNWidgets(3));

      await disposeWidget(tester);
    });

    testWidgets('bot typing text color is blue', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TypingIndicator(userName: 'BotHelper', isBot: true),
      ));
      await tester.pump();

      final textWidget = tester.widget<Text>(find.text('BotHelper 正在输入'));
      expect(textWidget.style?.color, Colors.blue);

      await disposeWidget(tester);
    });

    testWidgets('non-bot typing text color is grey', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TypingIndicator(userName: 'Human'),
      ));
      await tester.pump();

      final textWidget = tester.widget<Text>(find.text('Human 正在输入'));
      expect(textWidget.style?.color, Colors.grey);

      await disposeWidget(tester);
    });

    testWidgets('disposes animation controllers without error', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        const TypingIndicator(userName: 'Test'),
      ));
      await tester.pump(const Duration(milliseconds: 500));

      // Removing the widget triggers dispose; verify no exceptions.
      await disposeWidget(tester);
    });
  });
}
