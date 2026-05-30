import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

enum PMButtonVariant { primary, secondary, danger, link }

class PMButton extends StatelessWidget {
  const PMButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = PMButtonVariant.primary,
    this.loading = false,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final PMButtonVariant variant;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, size: 18),
        if (loading || icon != null) const SizedBox(width: PMSpacing.s),
        Text(label),
      ],
    );

    final padding = EdgeInsets.symmetric(
      horizontal: compact ? PMSpacing.m : PMSpacing.l,
      vertical: compact ? PMSpacing.s : PMSpacing.m,
    );

    return switch (variant) {
      PMButtonVariant.primary => FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PMRadius.s),
            ),
          ),
          child: child,
        ),
      PMButtonVariant.secondary => OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.border),
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PMRadius.s),
            ),
          ),
          child: child,
        ),
      PMButtonVariant.danger => OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.35)),
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PMRadius.s),
            ),
          ),
          child: child,
        ),
      PMButtonVariant.link => TextButton(
          onPressed: enabled ? onPressed : null,
          style: TextButton.styleFrom(
            foregroundColor: variant == PMButtonVariant.danger
                ? AppColors.error
                : AppColors.primary,
            padding: padding,
          ),
          child: child,
        ),
    };
  }
}
