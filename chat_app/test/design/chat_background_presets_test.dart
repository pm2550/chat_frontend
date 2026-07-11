import 'package:chat_app/design/design.dart';
import 'package:chat_app/models/chat_customization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat background presets', () {
    for (final option in ChatCustomizationCatalog.backgrounds) {
      testWidgets('${option.id} resolves and paints without throwing',
          (tester) async {
        expect(ChatCustomizationCatalog.isValidBackground(option.id), isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 200,
                child: PMBackgroundPreview(preset: option.id),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(PMBackgroundPreview), findsOneWidget);
      });
    }

    testWidgets('unknown background preset falls back without throwing',
        (tester) async {
      expect(ChatCustomizationCatalog.isValidBackground('unknown-bg'), isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: PMBackgroundPreview(preset: 'unknown-bg'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(PMBackgroundPreview), findsOneWidget);
    });

    testWidgets('custom wallpaper keeps preset visible while cache resolves',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: PMChatBackgroundLayer(
                preset: 'mint_grid',
                customUrl: '/api/files/background/personal.png',
                child: Text('messages'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.text('messages'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
