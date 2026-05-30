import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

class PMSkeleton extends StatefulWidget {
  const PMSkeleton._({
    required this.width,
    required this.height,
    required this.radius,
    this.lines,
  });

  factory PMSkeleton.row({double height = 56}) {
    return PMSkeleton._(
      width: double.infinity,
      height: height,
      radius: PMRadius.m,
    );
  }

  factory PMSkeleton.card({double height = 120}) {
    return PMSkeleton._(
      width: double.infinity,
      height: height,
      radius: PMRadius.l,
    );
  }

  factory PMSkeleton.text({int lines = 3}) {
    return PMSkeleton._(
      width: double.infinity,
      height: 18,
      radius: PMRadius.s,
      lines: lines,
    );
  }

  final double width;
  final double height;
  final double radius;
  final int? lines;

  @override
  State<PMSkeleton> createState() => _PMSkeletonState();
}

class _PMSkeletonState extends State<PMSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.lines!; i++) ...[
            FractionallySizedBox(
              widthFactor: i == widget.lines! - 1 ? 0.62 : 1,
              child: _ShimmerBox(
                controller: _controller,
                height: widget.height,
                radius: widget.radius,
              ),
            ),
            if (i != widget.lines! - 1) const SizedBox(height: PMSpacing.s),
          ],
        ],
      );
    }
    return _ShimmerBox(
      controller: _controller,
      width: widget.width,
      height: widget.height,
      radius: widget.radius,
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.controller,
    required this.height,
    required this.radius,
    this.width,
  });

  final AnimationController controller;
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = controller.value;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(-1.2 + value * 2.4, 0),
              end: Alignment(-0.2 + value * 2.4, 0),
              colors: const [
                AppColors.mist,
                Colors.white,
                AppColors.mist,
              ],
            ),
          ),
        );
      },
    );
  }
}
