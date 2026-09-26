import 'package:flutter/material.dart';

import '../constants/app_brand.dart';
import '../constants/app_colors.dart';

class PMChatLogo extends StatelessWidget {
  const PMChatLogo({
    super.key,
    this.size = 64,
    this.showWordmark = true,
    this.bright = false,
    this.centered = false,
  });

  final double size;
  final bool showWordmark;
  final bool bright;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final textColor = bright ? Colors.white : AppColors.textPrimary;
    final subtitleColor =
        bright ? Colors.white.withValues(alpha: 0.78) : AppColors.textSecondary;

    final logo = size <= 0 ? const SizedBox.shrink() : PMChatMark(size: size);
    if (!showWordmark) return logo;

    final wordmark = Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppBrand.name,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          AppBrand.tagline,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: subtitleColor,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
        ),
      ],
    );

    return centered
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (size > 0) ...[
                logo,
                const SizedBox(height: 14),
              ],
              wordmark,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (size > 0) ...[
                logo,
                const SizedBox(width: 12),
              ],
              wordmark,
            ],
          );
  }
}

class PMChatMark extends StatelessWidget {
  const PMChatMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PMChatMarkPainter(),
      ),
    );
  }
}

class PMChatPattern extends StatelessWidget {
  const PMChatPattern({
    super.key,
    required this.child,
    this.dense = false,
    this.dark = false,
  });

  final Widget child;
  final bool dense;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient:
                dark ? AppColors.primaryGradient : AppColors.backgroundGradient,
          ),
        ),
        child,
      ],
    );
  }
}

class PMSectionHeader extends StatelessWidget {
  const PMSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: subtitle == null ? 22 : 36,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _PMChatMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.width * 0.22);
    final rrect = RRect.fromRectAndRadius(rect, radius);
    final paint = Paint()
      ..shader = AppColors.primaryGradient.createShader(rect);
    canvas.drawRRect(rrect, paint);

    final accentPaint = Paint()
      ..shader = AppColors.accentGradient.createShader(rect)
      ..style = PaintingStyle.fill;
    final accentPath = Path()
      ..moveTo(size.width * 0.66, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.34)
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.31,
        size.width * 0.66,
        0,
      );
    canvas.drawPath(accentPath, accentPaint);

    final bubblePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.94)
      ..style = PaintingStyle.fill;
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.24,
        size.width * 0.64,
        size.height * 0.42,
      ),
      Radius.circular(size.width * 0.15),
    );
    canvas.drawRRect(bubble, bubblePaint);

    final tail = Path()
      ..moveTo(size.width * 0.38, size.height * 0.62)
      ..lineTo(size.width * 0.30, size.height * 0.78)
      ..lineTo(size.width * 0.53, size.height * 0.65)
      ..close();
    canvas.drawPath(tail, bubblePaint);

    final dotPaint = Paint()..color = AppColors.primaryDark;
    for (final x in [0.35, 0.50, 0.65]) {
      canvas.drawCircle(
        Offset(size.width * x, size.height * 0.45),
        size.width * 0.045,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
