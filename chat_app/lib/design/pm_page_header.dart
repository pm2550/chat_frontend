import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

class PMPageHeader extends StatelessWidget {
  const PMPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.search,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? search;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              SizedBox(width: compact ? PMSpacing.m : PMSpacing.l),
            ],
            Expanded(
              child: _PageHeading(
                title: title,
                subtitle: subtitle,
                compact: compact,
              ),
            ),
          ],
        );
        final actionWrap = Wrap(
          spacing: PMSpacing.s,
          runSpacing: PMSpacing.s,
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          children: actions,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact) ...[
              heading,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: PMSpacing.m),
                actionWrap,
              ],
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: heading),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: PMSpacing.l),
                    actionWrap,
                  ],
                ],
              ),
            if (search != null) ...[
              const SizedBox(height: PMSpacing.l),
              search!,
            ],
          ],
        );
      },
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.title,
    required this.compact,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: PMSpacing.xs),
          Text(
            subtitle!,
            maxLines: compact ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
