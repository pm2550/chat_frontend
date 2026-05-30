import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'pm_brand.dart';

class PMBreakpoints {
  static const double desktop = 1024;
  static const double webDesktop = 720;
  static const double wide = 1360;

  static bool isDesktop(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= desktop || (kIsWeb && width >= webDesktop);
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 600 && !isDesktop(context);
  }
}

class PMDesktopPage extends StatelessWidget {
  const PMDesktopPage({
    super.key,
    required this.child,
    this.maxWidth = 1180,
    this.padding = const EdgeInsets.all(28),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return PMChatPattern(
      dense: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class PMDesktopHeader extends StatelessWidget {
  const PMDesktopHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.dashboard_customize,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

class PMDesktopCard extends StatelessWidget {
  const PMDesktopCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: child,
    );
  }
}
