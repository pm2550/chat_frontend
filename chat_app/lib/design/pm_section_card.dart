import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'pm_card.dart';
import 'tokens.dart';

class PMSectionCard extends StatelessWidget {
  const PMSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.children = const [],
    this.padding = const EdgeInsets.all(PMSpacing.l),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return PMCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: PMSpacing.xs),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: PMSpacing.l),
                  trailing!,
                ],
              ],
            ),
          ),
          if (children.isNotEmpty)
            const Divider(height: 1, color: AppColors.borderLight),
          for (var i = 0; i < children.length; i++) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                PMSpacing.s,
                i == 0 ? PMSpacing.s : 0,
                PMSpacing.s,
                i == children.length - 1 ? PMSpacing.s : 0,
              ),
              child: children[i],
            ),
            if (i != children.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: PMSpacing.l),
                child: Divider(height: 1, color: AppColors.borderLight),
              ),
          ],
        ],
      ),
    );
  }
}
