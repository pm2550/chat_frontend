import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../design/design.dart';
import '../models/points.dart';
import '../services/points_service.dart';

class PMCostPreviewChip extends StatelessWidget {
  const PMCostPreviewChip({
    super.key,
    required this.featureKey,
    this.trailing,
    this.pointsService = const PointsService(),
  });

  final String featureKey;
  final Widget? trailing;
  final PointsService pointsService;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CostPreview>(
      future: pointsService.previewCost(featureKey),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final color = preview == null
            ? AppColors.textSecondary
            : preview.sufficient
                ? AppColors.success
                : AppColors.error;
        final label = preview == null
            ? '积分预览'
            : preview.willUseFree
                ? '本次免费 · 今日剩余 ${preview.freeRemaining} 次'
                : '本次 ${preview.cost} 积分 · 余额 ${preview.paidPoints} → ${preview.paidRemainingAfter}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PMChip(
              label: label,
              icon: Icons.toll,
              selected: true,
              color: color,
            ),
            if (trailing != null) ...[
              const SizedBox(width: PMSpacing.s),
              trailing!,
            ],
          ],
        );
      },
    );
  }
}
