import 'package:chat_app/design/design.dart';
import 'package:chat_app/models/chat_customization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bubble style presets', () {
    for (final option in ChatCustomizationCatalog.bubbleStyles) {
      testWidgets('${option.id} resolves and paints without throwing',
          (tester) async {
        expect(ChatCustomizationCatalog.isValidBubbleStyle(option.id), isTrue);
        final visual = PMBubbleStyles.resolve(
          preset: option.id,
          isMe: true,
          isAnonymous: false,
          anonymousColor: const Color(0xFF7C3AED),
        );

        expect(visual.decoration.borderRadius, isNotNull);
        expect(visual.textColor, isNotNull);
        expect(visual.secondaryTextColor, isNotNull);
        expect(
          visual.decoration.color != null || visual.decoration.gradient != null,
          isTrue,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: PMBubbleStylePreview(preset: option.id),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(PMBubbleStylePreview), findsOneWidget);
      });
    }

    testWidgets('unknown bubble style preset resolves to a safe default',
        (tester) async {
      expect(ChatCustomizationCatalog.isValidBubbleStyle('unknown-bubble'),
          isFalse);
      final visual = PMBubbleStyles.resolve(
        preset: 'unknown-bubble',
        isMe: true,
        isAnonymous: false,
        anonymousColor: const Color(0xFF7C3AED),
      );

      expect(visual.decoration.gradient, isNotNull);
      expect(visual.textColor, Colors.white);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: Center(
                child: PMBubbleStylePreview(preset: 'unknown-bubble'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(PMBubbleStylePreview), findsOneWidget);
    });
  });
}
