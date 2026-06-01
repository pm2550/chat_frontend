import 'package:flutter/material.dart';

enum AnonymousAvatarGlyphKind { emoji, pattern }

class AnonymousAvatarGlyph {
  const AnonymousAvatarGlyph._({
    required this.kind,
    required this.value,
    required this.seed,
  });

  factory AnonymousAvatarGlyph.emoji(String emoji, int seed) =>
      AnonymousAvatarGlyph._(
        kind: AnonymousAvatarGlyphKind.emoji,
        value: emoji,
        seed: seed,
      );

  factory AnonymousAvatarGlyph.pattern(int seed) => AnonymousAvatarGlyph._(
        kind: AnonymousAvatarGlyphKind.pattern,
        value: 'pattern-$seed',
        seed: seed,
      );

  final AnonymousAvatarGlyphKind kind;
  final String value;
  final int seed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnonymousAvatarGlyph &&
          kind == other.kind &&
          value == other.value &&
          seed == other.seed;

  @override
  int get hashCode => Object.hash(kind, value, seed);
}

class AnonymousAvatar extends StatelessWidget {
  const AnonymousAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 24,
  });

  final String name;
  final Color color;
  final double size;

  static const Map<String, String> animalEmoji = {
    '海豚': '🐬',
    '白兔': '🐰',
    '熊猫': '🐼',
    '狐狸': '🦊',
    '猫头鹰': '🦉',
    '企鹅': '🐧',
    '考拉': '🐨',
    '柴犬': '🐕',
    '仓鼠': '🐹',
    '松鼠': '🐿️',
    '水獭': '🦦',
    '羊驼': '🦙',
    '猫咪': '🐱',
    '小鹿': '🦌',
    '刺猬': '🦔',
    '海龟': '🐢',
    '鹦鹉': '🦜',
    '蝴蝶': '🦋',
    '独角兽': '🦄',
    '龙猫': '🐭',
    '小象': '🐘',
    '树懒': '🦥',
    '浣熊': '🦝',
    '白鸽': '🕊️',
    '金鱼': '🐟',
    '萤火虫': '✨',
    '雪狐': '❄️',
    '蜜蜂': '🐝',
    '青蛙': '🐸',
    '天鹅': '🦢',
    '孔雀': '🦚',
    '麋鹿': '🦬',
  };

  static AnonymousAvatarGlyph resolveGlyph(String name) {
    final normalized = name.trim();
    final animal = _animalToken(normalized);
    final seed = stableSeed(normalized);
    if (animal != null) {
      return AnonymousAvatarGlyph.emoji(animalEmoji[animal]!, seed);
    }
    return AnonymousAvatarGlyph.pattern(seed);
  }

  static int stableSeed(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  static Color? parseColor(String? value) {
    if (value == null || !value.startsWith('#')) return null;
    final hex = value.substring(1);
    final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  static String? _animalToken(String name) {
    final animals = animalEmoji.keys.toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final animal in animals) {
      if (name.endsWith(animal)) {
        return animal;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final glyph = resolveGlyph(name);
    return Semantics(
      label: '匿名头像 $name',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.86),
            width: (size * 0.065).clamp(1.0, 2.0),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.22),
              blurRadius: size * 0.18,
              offset: Offset(0, size * 0.04),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: glyph.kind == AnonymousAvatarGlyphKind.emoji
            ? Center(
                child: Text(
                  glyph.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: size * 0.58,
                    height: 1,
                  ),
                ),
              )
            : Padding(
                padding: EdgeInsets.all(size * 0.18),
                child: CustomPaint(
                  painter: AnonymousAvatarPatternPainter(
                    seed: glyph.seed,
                    color: color,
                  ),
                ),
              ),
      ),
    );
  }
}

class AnonymousAvatarPatternPainter extends CustomPainter {
  const AnonymousAvatarPatternPainter({
    required this.seed,
    required this.color,
  });

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 4;
    final primary = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    final secondary = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;

    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 2; x++) {
        final bitIndex = y * 2 + x;
        final active = ((seed >> bitIndex) & 1) == 1;
        final paint = active ? primary : secondary;
        final inset = active ? cell * 0.13 : cell * 0.28;
        final left = x * cell + inset;
        final mirroredLeft = (3 - x) * cell + inset;
        final top = y * cell + inset;
        final rectSize = cell - inset * 2;
        final radius = Radius.circular(cell * (active ? 0.24 : 0.5));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, rectSize, rectSize),
            radius,
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(mirroredLeft, top, rectSize, rectSize),
            radius,
          ),
          paint,
        );
      }
    }

    final accent = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * 0.16,
        size.height * 0.16,
        size.width * 0.68,
        size.height * 0.68,
      ),
      (seed % 360) * 0.0174533,
      1.7,
      false,
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant AnonymousAvatarPatternPainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.color != color;
  }
}
