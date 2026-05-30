import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

class PMChip extends StatelessWidget {
  const PMChip({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.selected = false,
    this.onTap,
    this.color,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(PMRadius.pill),
      onTap: onTap,
      child: AnimatedContainer(
        duration: PMMotion.fast,
        curve: PMMotion.curveStandard,
        padding: const EdgeInsets.symmetric(
          horizontal: PMSpacing.m,
          vertical: PMSpacing.s,
        ),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.11) : Colors.white,
          borderRadius: BorderRadius.circular(PMRadius.pill),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.35) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              IconTheme(
                data: IconThemeData(
                  size: 16,
                  color: selected ? accent : AppColors.textSecondary,
                ),
                child: leading!,
              ),
              const SizedBox(width: PMSpacing.xs),
            ] else if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? accent : AppColors.textSecondary,
              ),
              const SizedBox(width: PMSpacing.xs),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? accent : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
