import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

class PMRowAction {
  const PMRowAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}

class PMListRow extends StatefulWidget {
  const PMListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.badge,
    this.badgeColor,
    this.dense = false,
    this.onTap,
    this.onLongPress,
    this.swipeActions,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final String? badge;
  final Color? badgeColor;
  final bool dense;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final List<PMRowAction>? swipeActions;

  @override
  State<PMListRow> createState() => _PMListRowState();
}

class _PMListRowState extends State<PMListRow> {
  bool _hovered = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: PMMotion.fast,
      curve: PMMotion.curveStandard,
      padding: EdgeInsets.symmetric(
        horizontal: widget.dense ? PMSpacing.m : PMSpacing.l,
        vertical: widget.dense ? PMSpacing.s : PMSpacing.m,
      ),
      decoration: BoxDecoration(
        color: _hovered
            ? AppColors.pixelBlue.withValues(alpha: 0.55)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(PMRadius.m),
      ),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            SizedBox(width: widget.dense ? PMSpacing.m : PMSpacing.l),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle(
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: widget.dense ? 14 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: widget.title,
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: PMSpacing.xs),
                  DefaultTextStyle(
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: widget.dense ? 12 : 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    child: widget.subtitle!,
                  ),
                ],
              ],
            ),
          ),
          if (widget.badge != null) ...[
            const SizedBox(width: PMSpacing.m),
            _Badge(
              label: widget.badge!,
              color: widget.badgeColor ?? AppColors.primary,
            ),
          ],
          if (widget.trailing != null) ...[
            const SizedBox(width: PMSpacing.m),
            widget.trailing!,
          ] else if (_hovered && _interactive) ...[
            const SizedBox(width: PMSpacing.m),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textTertiary),
          ],
          if (_hovered &&
              widget.swipeActions != null &&
              widget.swipeActions!.isNotEmpty) ...[
            const SizedBox(width: PMSpacing.s),
            for (final action in widget.swipeActions!.take(3))
              IconButton(
                tooltip: action.label,
                onPressed: action.onTap,
                icon: Icon(action.icon,
                    color: action.color ?? AppColors.textSecondary),
              ),
          ],
        ],
      ),
    );

    return MouseRegion(
      cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: content,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: PMSpacing.s),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(PMRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
