import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'pm_card.dart';
import 'tokens.dart';

enum EmptyStateVariant { normal, muted, illustration }

class PMEmptyState extends StatelessWidget {
  const PMEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.variant = EmptyStateVariant.normal,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final EmptyStateVariant variant;

  @override
  Widget build(BuildContext context) {
    final iconColor = switch (variant) {
      EmptyStateVariant.normal => AppColors.primary,
      EmptyStateVariant.muted => AppColors.textTertiary,
      EmptyStateVariant.illustration => AppColors.secondaryDark,
    };
    final background = switch (variant) {
      EmptyStateVariant.illustration => AppColors.pixelMint,
      EmptyStateVariant.muted => AppColors.cloud,
      EmptyStateVariant.normal => AppColors.pixelBlue,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: PMCard(
          elevated: variant != EmptyStateVariant.muted,
          background: variant == EmptyStateVariant.muted
              ? Colors.transparent
              : AppColors.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(PMRadius.l),
                ),
                child: Icon(icon, color: iconColor, size: 36),
              ),
              const SizedBox(height: PMSpacing.l),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: PMSpacing.s),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: PMSpacing.l),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
