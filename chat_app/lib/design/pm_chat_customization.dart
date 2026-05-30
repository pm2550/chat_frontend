import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/api_constants.dart';
import '../constants/app_colors.dart';
import '../models/chat_customization.dart';
import 'tokens.dart';

class PMChatBackgroundLayer extends StatelessWidget {
  const PMChatBackgroundLayer({
    super.key,
    required this.child,
    this.preset,
    this.customUrl,
  });

  final Widget child;
  final String? preset;
  final String? customUrl;

  @override
  Widget build(BuildContext context) {
    final url = customUrl?.trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url.isNotEmpty)
          Image.network(
            ApiConstants.resolveFileUrl(url),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _PresetBackground(preset: preset),
          )
        else
          _PresetBackground(preset: preset),
        Container(color: Colors.white.withValues(alpha: 0.30)),
        child,
      ],
    );
  }
}

class PMBackgroundPreview extends StatelessWidget {
  const PMBackgroundPreview({
    super.key,
    required this.preset,
    this.customUrl,
    this.selected = false,
  });

  final String preset;
  final String? customUrl;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PMRadius.m),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(PMRadius.m),
        ),
        child: PMChatBackgroundLayer(
          preset: preset,
          customUrl: customUrl,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class PMAvatarFrame extends StatelessWidget {
  const PMAvatarFrame({
    super.key,
    required this.child,
    required this.size,
    this.preset = ChatCustomizationCatalog.defaultAvatarFrame,
  });

  final Widget child;
  final double size;
  final String preset;

  @override
  Widget build(BuildContext context) {
    if (preset == ChatCustomizationCatalog.defaultAvatarFrame) {
      return child;
    }
    return SizedBox.square(
      dimension: size + 10,
      child: Stack(
        alignment: Alignment.center,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AvatarFramePainter(preset),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PMAvatarFramePreview extends StatelessWidget {
  const PMAvatarFramePreview({
    super.key,
    required this.preset,
    this.selected = false,
  });

  final String preset;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selected
            ? AppColors.pixelBlue
            : AppColors.cloud.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(PMRadius.m),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.borderLight,
          width: selected ? 2 : 1,
        ),
      ),
      child: Center(
        child: PMAvatarFrame(
          preset: preset,
          size: 40,
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.messageGradient,
            ),
            alignment: Alignment.center,
            child: const Text(
              'P',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PMBubbleStyleVisual {
  const PMBubbleStyleVisual({
    required this.decoration,
    required this.textColor,
    required this.secondaryTextColor,
  });

  final BoxDecoration decoration;
  final Color textColor;
  final Color secondaryTextColor;
}

class PMBubbleStyles {
  static PMBubbleStyleVisual resolve({
    required String preset,
    required bool isMe,
    required bool isAnonymous,
    required Color anonymousColor,
  }) {
    if (isAnonymous) {
      return PMBubbleStyleVisual(
        decoration: BoxDecoration(
          color: isMe ? anonymousColor : anonymousColor.withValues(alpha: 0.10),
          borderRadius: _radius(isMe, 18, 6),
          border: isMe
              ? null
              : Border.all(color: anonymousColor.withValues(alpha: 0.30)),
          boxShadow: [_shadow(isMe ? 0.12 : 0.07)],
        ),
        textColor: isMe ? Colors.white : AppColors.textPrimary,
        secondaryTextColor: isMe
            ? Colors.white.withValues(alpha: 0.72)
            : AppColors.textSecondary,
      );
    }

    if (!isMe) {
      return PMBubbleStyleVisual(
        decoration: BoxDecoration(
          color: AppColors.messageReceived,
          borderRadius: _radius(false, 18, 6),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [_shadow(0.07)],
        ),
        textColor: AppColors.textPrimary,
        secondaryTextColor: AppColors.textSecondary,
      );
    }

    final normalized = ChatCustomizationCatalog.isValidBubbleStyle(preset)
        ? preset
        : ChatCustomizationCatalog.defaultBubbleStyle;
    return switch (normalized) {
      'minimal_flat' => PMBubbleStyleVisual(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: _radius(true, 10, 4),
            boxShadow: [_shadow(0.05)],
          ),
          textColor: Colors.white,
          secondaryTextColor: Colors.white.withValues(alpha: 0.72),
        ),
      'rounded_soft' => PMBubbleStyleVisual(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4F8EF7), Color(0xFF21B8A6)],
            ),
            borderRadius: _radius(true, 24, 12),
            boxShadow: [_shadow(0.10, blur: 18, dy: 7)],
          ),
          textColor: Colors.white,
          secondaryTextColor: Colors.white.withValues(alpha: 0.74),
        ),
      'retro_block' => PMBubbleStyleVisual(
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            borderRadius: _radius(true, 4, 2),
            border: Border.all(color: const Color(0xFF0F172A), width: 1.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 0,
                offset: Offset(3, 3),
              ),
            ],
          ),
          textColor: Colors.white,
          secondaryTextColor: Colors.white.withValues(alpha: 0.74),
        ),
      'dark_night' => PMBubbleStyleVisual(
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: _radius(true, 18, 6),
            border: Border.all(color: const Color(0xFF38BDF8), width: 1),
            boxShadow: [_shadow(0.18, blur: 18, dy: 8)],
          ),
          textColor: Colors.white,
          secondaryTextColor: Colors.white.withValues(alpha: 0.76),
        ),
      'high_contrast' => PMBubbleStyleVisual(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: _radius(true, 14, 5),
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: [_shadow(0.18)],
          ),
          textColor: Colors.white,
          secondaryTextColor: Colors.white.withValues(alpha: 0.82),
        ),
      _ => PMBubbleStyleVisual(
          decoration: BoxDecoration(
            gradient: AppColors.messageGradient,
            borderRadius: _radius(true, 18, 6),
            boxShadow: [_shadow(0.12)],
          ),
          textColor: Colors.white,
          secondaryTextColor: Colors.white.withValues(alpha: 0.72),
        ),
    };
  }

  static BorderRadius _radius(bool isMe, double main, double tail) {
    return BorderRadius.only(
      topLeft: Radius.circular(main),
      topRight: Radius.circular(main),
      bottomLeft: Radius.circular(isMe ? main : tail),
      bottomRight: Radius.circular(isMe ? tail : main),
    );
  }

  static BoxShadow _shadow(double alpha, {double blur = 12, double dy = 5}) {
    return BoxShadow(
      color: AppColors.ink.withValues(alpha: alpha),
      blurRadius: blur,
      offset: Offset(0, dy),
    );
  }
}

class PMBubbleStylePreview extends StatelessWidget {
  const PMBubbleStylePreview({
    super.key,
    required this.preset,
    this.selected = false,
  });

  final String preset;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final visual = PMBubbleStyles.resolve(
      preset: preset,
      isMe: true,
      isAnonymous: false,
      anonymousColor: const Color(0xFF7C3AED),
    );
    return Container(
      decoration: BoxDecoration(
        color: selected ? AppColors.pixelBlue : Colors.white,
        borderRadius: BorderRadius.circular(PMRadius.m),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.borderLight,
          width: selected ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: visual.decoration,
        child: Text(
          'PM',
          style: TextStyle(
            color: visual.textColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _PresetBackground extends StatelessWidget {
  const _PresetBackground({this.preset});

  final String? preset;

  @override
  Widget build(BuildContext context) {
    final solidColor = _solidColorFromPreset(preset);
    if (solidColor != null) {
      return ColoredBox(color: solidColor);
    }
    final normalized = ChatCustomizationCatalog.isValidBackground(preset)
        ? preset!
        : ChatCustomizationCatalog.defaultBackground;
    return CustomPaint(
      painter: _BackgroundPainter(normalized),
      child: const SizedBox.expand(),
    );
  }

  Color? _solidColorFromPreset(String? value) {
    final preset = value?.trim();
    if (preset == null || !ChatCustomizationCatalog.isSolidBackground(preset)) {
      return null;
    }
    return Color(
        int.parse('FF${preset.substring('solid:#'.length)}', radix: 16));
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter(this.preset);

  final String preset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = switch (preset) {
      'pixel_mint' => [const Color(0xFFE9FFF7), const Color(0xFFDDF7FF)],
      'sunset_warm' => [const Color(0xFFFFF1E6), const Color(0xFFFFE3F0)],
      'cyber_dark' => [const Color(0xFF111827), const Color(0xFF0F766E)],
      'paper_dotted' => [const Color(0xFFFFFFFF), const Color(0xFFF3F7FB)],
      'gradient_wave' => [const Color(0xFFEAF4FF), const Color(0xFFF4ECFF)],
      'mono_lines' => [const Color(0xFFF8FAFC), const Color(0xFFEFF6FF)],
      'aurora' => [const Color(0xFFE7FFF8), const Color(0xFFF3E8FF)],
      _ => [const Color(0xFFEAF4FF), const Color(0xFFE7FFF8)],
    };
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    switch (preset) {
      case 'cyber_dark':
        _grid(canvas, size, const Color(0x6638BDF8), 34);
        _dots(canvas, size, const Color(0x5522D3EE), 42);
      case 'paper_dotted':
        _dots(canvas, size, const Color(0x220F172A), 18);
      case 'gradient_wave':
        _waves(canvas, size, const Color(0x335B7CFA));
      case 'mono_lines':
        _diagonalLines(canvas, size, const Color(0x160F172A), 22);
      case 'aurora':
        _aurora(canvas, size);
      case 'pixel_mint':
      case 'cloud_gradient':
        _diagonalLines(canvas, size, const Color(0x143B82F6), 24);
        _dots(canvas, size, const Color(0x3321B8A6), 38);
        _dots(canvas, size, const Color(0x22FF7A45), 72);
      default:
        _dots(canvas, size, const Color(0x220F172A), 40);
    }
  }

  void _dots(Canvas canvas, Size size, Color color, double step) {
    final paint = Paint()..color = color;
    for (double x = step / 2; x < size.width; x += step) {
      for (double y = step / 2; y < size.height; y += step) {
        canvas.drawRect(
            Rect.fromCenter(center: Offset(x, y), width: 4, height: 4), paint);
      }
    }
  }

  void _diagonalLines(Canvas canvas, Size size, Color color, double step) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
          Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
  }

  void _grid(Canvas canvas, Size size, Color color, double step) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _waves(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.18 + i * 0.16);
      final path = Path()..moveTo(0, y);
      for (double x = 0; x <= size.width; x += 24) {
        path.lineTo(x, y + math.sin((x / 60) + i) * 18);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _aurora(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 48)
      ..shader = const RadialGradient(
        colors: [Color(0xAA22C55E), Color(0x007C3AED)],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.22, size.height * 0.30),
        radius: size.shortestSide * 0.45,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.22, size.height * 0.30),
      size.shortestSide * 0.45,
      paint,
    );
    paint.shader = const RadialGradient(
      colors: [Color(0xAA7C3AED), Color(0x0022C55E)],
    ).createShader(Rect.fromCircle(
      center: Offset(size.width * 0.78, size.height * 0.42),
      radius: size.shortestSide * 0.40,
    ));
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.42),
      size.shortestSide * 0.40,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) {
    return oldDelegate.preset != preset;
  }
}

class _AvatarFramePainter extends CustomPainter {
  const _AvatarFramePainter(this.preset);

  final String preset;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;

    switch (preset) {
      case 'golden_ring':
        stroke.color = const Color(0xFFF59E0B);
        stroke.strokeWidth = 3;
        canvas.drawCircle(center, radius, stroke);
        stroke.color = const Color(0xFFFFF7AD);
        stroke.strokeWidth = 1.2;
        canvas.drawCircle(center, radius - 3, stroke);
      case 'starry_night':
        stroke.color = const Color(0xFF1E3A8A);
        stroke.strokeWidth = 4;
        canvas.drawCircle(center, radius, stroke);
        final starPaint = Paint()..color = const Color(0xFFFDE68A);
        for (final angle in [0.1, 1.9, 3.3, 5.1]) {
          canvas.drawCircle(
            Offset(
              center.dx + math.cos(angle) * radius,
              center.dy + math.sin(angle) * radius,
            ),
            2,
            starPaint,
          );
        }
      case 'mint_minimal':
        stroke.color = const Color(0xFF14B8A6);
        canvas.drawCircle(center, radius, stroke);
      case 'flame':
        stroke.color = const Color(0xFFFF7A45);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -1.2,
          math.pi * 1.55,
          false,
          stroke..strokeWidth = 4,
        );
        stroke.color = const Color(0xFFFACC15);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - 4),
          1.1,
          math.pi * 0.8,
          false,
          stroke..strokeWidth = 2,
        );
      case 'cyber_glow':
        stroke.color = const Color(0xFF38BDF8);
        stroke.strokeWidth = 2.5;
        canvas.drawCircle(center, radius, stroke);
        canvas.drawCircle(
          center,
          radius + 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = const Color(0x557C3AED)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      case 'retro_dashes':
        stroke.color = const Color(0xFF334155);
        for (var i = 0; i < 18; i += 2) {
          final start = i * math.pi / 9;
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: radius),
            start,
            math.pi / 16,
            false,
            stroke,
          );
        }
      case 'pixel_pink':
        stroke.color = const Color(0xFFEC4899);
        canvas.drawCircle(center, radius, stroke);
        final fill = Paint()..color = const Color(0xFFEC4899);
        for (final offset in [
          const Offset(4, 4),
          Offset(size.width - 8, 4),
          Offset(size.width - 8, size.height - 8),
          Offset(4, size.height - 8),
        ]) {
          canvas.drawRect(offset & const Size(4, 4), fill);
        }
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarFramePainter oldDelegate) {
    return oldDelegate.preset != preset;
  }
}
