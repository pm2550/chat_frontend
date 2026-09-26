part of '../contacts_page.dart';

extension _ContactsView2Parts on _ContactsPageState {
  Widget _buildUserCard(
      {required User user,
      String? subtitle,
      String? secondarySubtitle,
      Widget? trailing,
      VoidCallback? onTap,
      VoidCallback? onLongPress,
      GestureTapDownCallback? onSecondaryTapDown}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: PMSpacing.l, vertical: PMSpacing.xs),
      child: GestureDetector(
          onSecondaryTapDown: onSecondaryTapDown,
          child: PMCard(
              elevated: false,
              padding: EdgeInsets.zero,
              child: PMListRow(
                onTap: onTap,
                onLongPress: onLongPress,
                leading: _buildAvatar(user, radius: 22),
                title: Row(children: [
                  Flexible(
                      child: Text(_displayName(user),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (user.title?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(width: PMSpacing.xs),
                    PMTitleBadge(
                        title: user.title,
                        color: user.titleColor,
                        effect: user.titleEffect)
                  ],
                ]),
                subtitle: subtitle == null
                    ? null
                    : Text(
                        [
                          subtitle,
                          if (secondarySubtitle?.isNotEmpty == true)
                            secondarySubtitle!
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                trailing: trailing,
              ))),
    );
  }

  Widget _buildAvatar(User user, {required double radius}) {
    return Stack(
      children: [
        PMAvatarFrame(
          preset: user.avatarFramePreset,
          size: radius * 2,
          child: CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            backgroundImage: user.avatarUrl != null
                ? NetworkImage(ApiConstants.resolveFileUrl(user.avatarUrl!))
                : null,
            child: user.avatarUrl == null
                ? Text(
                    _displayName(user).isNotEmpty
                        ? _displayName(user)[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: radius <= 28 ? 18 : 24,
                    ),
                  )
                : null,
          ),
        ),
        if (user.onlineStatus == OnlineStatus.online)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: IconButton(
            icon: Icon(icon, color: AppColors.primary),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildContactDetailLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
