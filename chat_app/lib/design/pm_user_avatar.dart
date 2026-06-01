import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/user.dart';
import 'pm_chat_customization.dart';
import 'pm_status_badge.dart';
import 'tokens.dart';

class PMUserAvatar extends StatelessWidget {
  const PMUserAvatar({
    super.key,
    required this.user,
    this.size = 44,
    this.status,
    this.showOnlineDot = false,
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.framePreset,
  })  : imageUrl = null,
        fallbackText = null,
        isGroup = false;

  const PMUserAvatar.raw({
    super.key,
    this.imageUrl,
    this.fallbackText,
    this.size = 44,
    this.status,
    this.showOnlineDot = false,
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.isGroup = false,
    this.framePreset,
  }) : user = null;

  final User? user;
  final String? imageUrl;
  final String? fallbackText;
  final double size;
  final PMOnlineStatus? status;
  final bool showOnlineDot;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onLongPress;
  final bool isGroup;
  final String? framePreset;

  @override
  Widget build(BuildContext context) {
    final effectiveStatus = status ??
        (user == null
            ? null
            : PMOnlineStatus.fromUserStatus(user!.onlineStatus));
    final url = imageUrl ?? user?.avatarUrl;
    final label = fallbackText ??
        user?.displayName ??
        user?.username ??
        (isGroup ? '群' : 'U');

    final avatar = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: url == null || url.isEmpty ? AppColors.messageGradient : null,
        borderRadius:
            BorderRadius.circular(isGroup ? PMRadius.m : PMRadius.pill),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [PMElevation.subtle],
      ),
      child: url != null && url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallback(label),
            )
          : _buildFallback(label),
    );
    final framedAvatar = PMAvatarFrame(
      preset: framePreset ?? user?.avatarFramePreset ?? 'none',
      size: size,
      child: avatar,
    );

    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        framedAvatar,
        if (showOnlineDot && effectiveStatus != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: PMStatusBadge(
              status: effectiveStatus,
              compact: true,
            ),
          ),
      ],
    );

    if (onTap == null && onSecondaryTap == null && onLongPress == null) {
      return content;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTap: onSecondaryTap,
        onLongPress: onLongPress,
        child: content,
      ),
    );
  }

  Widget _buildFallback(String label) {
    final trimmed = label.trim();
    final text =
        trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first);
    return Center(
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
