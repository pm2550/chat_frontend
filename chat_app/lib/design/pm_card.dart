import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

class PMCard extends StatefulWidget {
  const PMCard({
    super.key,
    this.padding = const EdgeInsets.all(PMSpacing.l),
    this.background = AppColors.surface,
    this.radius = PMRadius.m,
    this.elevated = true,
    this.interactive = false,
    this.onTap,
    required this.child,
  });

  final EdgeInsets padding;
  final Color background;
  final double radius;
  final bool elevated;
  final bool interactive;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<PMCard> createState() => _PMCardState();
}

class _PMCardState extends State<PMCard> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _isInteractive => widget.interactive || widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final hoverTint = _hovered && _isInteractive
        ? Color.alphaBlend(
            AppColors.primary.withValues(alpha: 0.035), widget.background)
        : widget.background;
    final shadow = !widget.elevated
        ? <BoxShadow>[]
        : [
            if (_hovered && _isInteractive)
              PMElevation.hover
            else
              PMElevation.card,
          ];

    return MouseRegion(
      cursor: _isInteractive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:
            _isInteractive ? (_) => setState(() => _pressed = true) : null,
        onTapCancel:
            _isInteractive ? () => setState(() => _pressed = false) : null,
        onTapUp:
            _isInteractive ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: PMMotion.fast,
          curve: PMMotion.curveStandard,
          scale: _pressed ? 0.99 : 1,
          child: AnimatedContainer(
            duration: PMMotion.fast,
            curve: PMMotion.curveStandard,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: hoverTint,
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: shadow,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
