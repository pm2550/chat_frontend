import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../design/design.dart';
import '../services/anonymous_service.dart';

class AnonymousIdentityHint extends StatelessWidget {
  const AnonymousIdentityHint({
    super.key,
    required this.identity,
    required this.quota,
    required this.onReroll,
    this.visible = true,
    this.rerolling = false,
  });

  final AnonymousIdentity? identity;
  final AnonymousQuota? quota;
  final VoidCallback? onReroll;
  final bool visible;
  final bool rerolling;

  static const int dailyLimit = 3;

  @override
  Widget build(BuildContext context) {
    final current = identity;
    if (!visible || current == null) {
      return const SizedBox.shrink();
    }

    final accent = AnonymousAvatar.parseColor(current.anonymousAvatar) ??
        const Color(0xFF7C3AED);
    final remaining = quota?.remaining ?? current.dailyRemaining;
    final disabled = remaining == 0 || rerolling;
    final label = remaining == null
        ? '今天还可换 --/$dailyLimit 次'
        : '今天还可换 $remaining/$dailyLimit 次';

    return Padding(
      padding: const EdgeInsets.only(bottom: PMSpacing.s),
      child: Container(
        key: const ValueKey('anonymous-identity-hint'),
        padding: const EdgeInsets.symmetric(
          horizontal: PMSpacing.m,
          vertical: PMSpacing.s,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(PMRadius.m),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            AnonymousAvatar(
              name: current.anonymousName,
              color: accent,
              size: 26,
            ),
            const SizedBox(width: PMSpacing.s),
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '当前匿名身份：',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    current.anonymousName,
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '· $label',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: PMSpacing.s),
            Tooltip(
              message: remaining == 0 ? '今日额度已用完，明天恢复' : '切换匿名身份',
              child: PMButton(
                label: '换一个',
                compact: true,
                variant: PMButtonVariant.secondary,
                loading: rerolling,
                onPressed: disabled ? null : onReroll,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
