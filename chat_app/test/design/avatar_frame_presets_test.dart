import 'package:chat_app/design/design.dart';
import 'package:chat_app/models/chat_customization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('avatar frame presets', () {
    for (final option in ChatCustomizationCatalog.avatarFrames) {
      testWidgets('${option.id} resolves and paints without throwing',
          (tester) async {
        expect(ChatCustomizationCatalog.isValidAvatarFrame(option.id), isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: PMAvatarFramePreview(preset: option.id),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(PMAvatarFramePreview), findsOneWidget);
      });
    }

    testWidgets('unknown avatar frame preset falls back without throwing',
        (tester) async {
      expect(ChatCustomizationCatalog.isValidAvatarFrame('unknown-frame'),
          isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: Center(
                child: PMAvatarFramePreview(preset: 'unknown-frame'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(PMAvatarFramePreview), findsOneWidget);
    });
  });
}
