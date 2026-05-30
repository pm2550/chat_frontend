import 'package:flutter/material.dart';

import 'pm_button.dart';
import 'pm_empty_state.dart';

class PMErrorState extends StatelessWidget {
  const PMErrorState({
    super.key,
    required this.message,
    this.title = '加载失败',
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return PMEmptyState(
      icon: Icons.cloud_off_outlined,
      title: title,
      subtitle: message,
      variant: EmptyStateVariant.muted,
      action: onRetry == null
          ? null
          : PMButton(
              label: '重试',
              icon: Icons.refresh,
              onPressed: onRetry,
              variant: PMButtonVariant.secondary,
            ),
    );
  }
}
