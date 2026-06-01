import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class PMTitleBadge extends StatefulWidget {
  const PMTitleBadge({
    super.key,
    required this.title,
    this.color,
    this.effect = 'none',
    this.compact = true,
  });

  final String? title;
  final String? color;
  final String effect;
  final bool compact;

  @override
  State<PMTitleBadge> createState() => _PMTitleBadgeState();
}

class _PMTitleBadgeState extends State<PMTitleBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.effect == 'animated_pulse') {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PMTitleBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.effect == 'animated_pulse' && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (widget.effect != 'animated_pulse' && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.title?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final base = _parseColor(widget.color) ?? AppColors.primary;
    final child = Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 7 : 10,
        vertical: widget.compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        gradient: _gradient(base),
        color: widget.effect == 'gradient' || widget.effect == 'rainbow'
            ? null
            : base.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: 0.38)),
        boxShadow: widget.effect == 'glow'
            ? [
                BoxShadow(
                  color: base.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: widget.effect == 'gradient' || widget.effect == 'rainbow'
              ? Colors.white
              : base,
          fontSize: widget.compact ? 10 : 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
    if (widget.effect != 'animated_pulse') return child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Transform.scale(
        scale: 1 + _controller.value * 0.04,
        child: child,
      ),
    );
  }

  LinearGradient? _gradient(Color base) {
    if (widget.effect == 'rainbow') {
      return const LinearGradient(
        colors: [
          Color(0xFFE95C7B),
          Color(0xFFF4B740),
          Color(0xFF18B98F),
          Color(0xFF2F6BFF),
        ],
      );
    }
    if (widget.effect == 'gradient') {
      return LinearGradient(
        colors: [base, AppColors.secondary],
      );
    }
    return null;
  }

  Color? _parseColor(String? value) {
    final text = value?.trim();
    if (text == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) {
      return null;
    }
    return Color(int.parse('FF${text.substring(1)}', radix: 16));
  }
}
