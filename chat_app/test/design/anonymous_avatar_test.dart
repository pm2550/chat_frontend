import 'package:chat_app/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnonymousAvatar', () {
    test('same anonymous name resolves to same glyph', () {
      final first = AnonymousAvatar.resolveGlyph('神秘小象');
      final second = AnonymousAvatar.resolveGlyph('神秘小象');

      expect(second, first);
    });

    test('different names with same color can resolve to different glyphs', () {
      final first = AnonymousAvatar.resolveGlyph('神秘小象');
      final second = AnonymousAvatar.resolveGlyph('快乐企鹅');

      expect(second, isNot(first));
    });

    test('parseable animal name uses emoji branch', () {
      final glyph = AnonymousAvatar.resolveGlyph('神秘小象');

      expect(glyph.kind, AnonymousAvatarGlyphKind.emoji);
      expect(glyph.value, '🐘');
    });

    test('all built-in animal emoji mappings are distinct', () {
      final values = AnonymousAvatar.animalEmoji.values.toList();

      expect(values.toSet(), hasLength(values.length));
      for (final animal in AnonymousAvatar.animalEmoji.keys) {
        final glyph = AnonymousAvatar.resolveGlyph('神秘$animal');
        expect(glyph.kind, AnonymousAvatarGlyphKind.emoji);
        expect(glyph.value, AnonymousAvatar.animalEmoji[animal]);
      }
    });

    test('non-parseable name uses geometric pattern branch', () {
      final glyph = AnonymousAvatar.resolveGlyph('abc123');

      expect(glyph.kind, AnonymousAvatarGlyphKind.pattern);
      expect(glyph.value, startsWith('pattern-'));
    });

    testWidgets('renders multiple identities side-by-side', (tester) async {
      const names = [
        '神秘小象',
        '快乐企鹅',
        '勇敢狐狸',
        '智慧猫头鹰',
        'abc123',
        '低调青蛙',
        '清新海豚',
        '霸气孔雀',
        '温柔白兔',
        '硬核蜜蜂',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (final name in names)
                  AnonymousAvatar(
                    name: name,
                    color: const Color(0xFF7C3AED),
                    size: 32,
                  ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(AnonymousAvatar), findsNWidgets(names.length));
      expect(find.text('🐘'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
