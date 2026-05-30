import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

class PMPageHeader extends StatelessWidget {
  const PMPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.search,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? search;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: PMSpacing.l),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: PMSpacing.xs),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: PMSpacing.l),
              Wrap(
                spacing: PMSpacing.s,
                runSpacing: PMSpacing.s,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
          ],
        ),
        if (search != null) ...[
          const SizedBox(height: PMSpacing.l),
          search!,
        ],
      ],
    );
  }
}
