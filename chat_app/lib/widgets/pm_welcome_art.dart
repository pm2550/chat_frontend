import 'package:flutter/material.dart';
import '../design/tokens.dart';
import 'pm_brand.dart';

/// A single compressed, static illustration; no idle animation or GPU loop.
class PMWelcomeArt extends StatelessWidget {
  const PMWelcomeArt({super.key, this.size = 240});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(PMRadius.xl),
        child: Image.asset(
          'assets/images/pmchat-welcome-v1.webp',
          width: size,
          height: size,
          cacheWidth: 512,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => SizedBox(
              width: size,
              height: size,
              child: const Center(child: PMChatMark(size: 72))),
        ),
      );
}
