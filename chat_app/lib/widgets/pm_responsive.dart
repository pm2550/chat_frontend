import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'pm_brand.dart';
import '../design/design.dart';

class PMBreakpoints {
  static const double desktop = 1024;
  static const double webDesktop = 1024;
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

class PMDesktopLayout {
  static double conversationListWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 1200 ? 300 : 340;
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
  Widget build(BuildContext context) => PMPageHeader(
        title: title,
        subtitle: subtitle,
        actions: actions,
        leading: PMCard(
            elevated: false,
            padding: const EdgeInsets.all(PMSpacing.m),
            background: AppColors.pixelBlue,
            child: Icon(icon, color: AppColors.primary, size: 24)),
      );
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
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: PMCard(padding: padding, radius: PMRadius.l, child: child),
    );
  }
}
