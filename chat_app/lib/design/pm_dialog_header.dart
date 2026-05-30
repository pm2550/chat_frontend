import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

class PMDialogHeader extends StatelessWidget {
  const PMDialogHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
    this.showHandle = true,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHandle) ...[
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(PMRadius.pill),
            ),
          ),
          const SizedBox(height: PMSpacing.l),
        ],
        Row(
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
                      fontSize: 20,
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
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: '关闭',
                onPressed: onClose,
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
              ),
          ],
        ),
      ],
    );
  }
}
