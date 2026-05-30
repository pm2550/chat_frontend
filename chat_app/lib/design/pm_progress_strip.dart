import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

class PMProgressStrip extends StatelessWidget {
  const PMProgressStrip({
    super.key,
    required this.label,
    this.progress,
    this.success = false,
  });

  final String label;
  final double? progress;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success ? AppColors.success : AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(PMRadius.m),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PMSpacing.m,
              vertical: PMSpacing.s,
            ),
            child: Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.sync,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: PMSpacing.s),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
