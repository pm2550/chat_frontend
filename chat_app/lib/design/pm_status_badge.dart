import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/user.dart';
import 'tokens.dart';

enum PMOnlineStatus {
  online('在线', AppColors.online),
  away('离开', AppColors.away),
  busy('忙碌', AppColors.busy),
  offline('离线', AppColors.offline);

  const PMOnlineStatus(this.label, this.color);

  final String label;
  final Color color;

  static PMOnlineStatus fromUserStatus(OnlineStatus status) {
    return switch (status) {
      OnlineStatus.online => PMOnlineStatus.online,
      OnlineStatus.away => PMOnlineStatus.away,
      OnlineStatus.busy => PMOnlineStatus.busy,
      OnlineStatus.offline => PMOnlineStatus.offline,
    };
  }
}

class PMStatusBadge extends StatelessWidget {
  const PMStatusBadge({
    super.key,
    required this.status,
    this.label,
    this.compact = false,
  });

  final PMOnlineStatus status;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Semantics(
        label: label ?? status.label,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: status.color,
            borderRadius: BorderRadius.circular(PMRadius.pill),
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PMSpacing.s,
        vertical: PMSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PMRadius.pill),
        border: Border.all(color: status.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: status.color,
              borderRadius: BorderRadius.circular(PMRadius.pill),
            ),
          ),
          const SizedBox(width: PMSpacing.xs),
          Text(
            label ?? status.label,
            style: TextStyle(
              color: status.color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
