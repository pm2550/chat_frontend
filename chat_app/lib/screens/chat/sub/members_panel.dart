part of '../chat_screen.dart';

extension _ChatScreenMembersPanelParts on _ChatScreenState {
  Widget _buildDesktopInfoPanel() {
    final tabs = [
      (PMSymbol.members, '成员', AppColors.primary),
      (PMSymbol.files, '文件', AppColors.primary),
      (PMSymbol.ai, 'Bot', AppColors.secondaryDark),
    ];
    if (_desktopInfoPanelCollapsed) {
      return Container(
        width: 64,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: AppColors.borderLight)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              IconButton(
                tooltip: '展开房间信息',
                icon: const Icon(Icons.chevron_left),
                onPressed: () =>
                    _setViewState(() => _desktopInfoPanelCollapsed = false),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: IconButton.filledTonal(
                    tooltip: tabs[i].$2,
                    icon: PMSymbolIcon(tabs[i].$1, size: 18),
                    color: _desktopInfoPanelTab == i
                        ? tabs[i].$3
                        : AppColors.textSecondary,
                    style: IconButton.styleFrom(
                      backgroundColor: _desktopInfoPanelTab == i
                          ? tabs[i].$3.withValues(alpha: 0.12)
                          : AppColors.cloud,
                    ),
                    onPressed: () => _setViewState(() {
                      _desktopInfoPanelTab = i;
                      _desktopInfoPanelCollapsed = false;
                    }),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: AppColors.borderLight)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          PMChip(
                            label: tabs[i].$2,
                            leading: PMSymbolIcon(tabs[i].$1, size: 16),
                            selected: _desktopInfoPanelTab == i,
                            color: tabs[i].$3,
                            onTap: () =>
                                _setViewState(() => _desktopInfoPanelTab = i),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '收起',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () =>
                        _setViewState(() => _desktopInfoPanelCollapsed = true),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: switch (_desktopInfoPanelTab) {
                  0 => _buildMembersPanel(),
                  1 => _buildFilesPanel(),
                  _ => _buildBotsPanel(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembersPanel() {
    return ListView(
      children: [
        PMCard(
          elevated: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildChatAvatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _chat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _chatSubtitle(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _chat.type == ChatType.group ? '群聊设置' : '聊天信息',
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: _openRoomSettings,
                  ),
                ],
              ),
              if (_chat.anonymousEnabled) ...[
                const SizedBox(height: 12),
                PMChip(
                  label: '匿名主题 · ${_chat.anonymousTheme}',
                  icon: Icons.masks,
                  selected: true,
                  color: const Color(0xFF7C3AED),
                  onTap: _openRoomSettings,
                ),
              ],
              if (_chat.type == ChatType.group &&
                  (_chat.description?.trim().isNotEmpty ?? false)) ...[
                const SizedBox(height: 12),
                Text(
                  _chat.description!.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('成员', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        for (final participant in _chat.participants)
          PMListRow(
            leading: PMUserAvatar(
              key: ValueKey('member-avatar-${participant.id}'),
              user: participant,
              status: PMOnlineStatus.fromUserStatus(participant.onlineStatus),
              showOnlineDot: true,
              onSecondaryTap: () => _insertMentionForUser(participant),
              onLongPress: () => _insertMentionForUser(participant),
            ),
            title: Text(participant.displayName.isNotEmpty
                ? participant.displayName
                : participant.username),
            subtitle: Text(participant.onlineStatus.name),
            onSecondaryTap: () => _insertMentionForUser(participant),
            onLongPress: () => _insertMentionForUser(participant),
            trailing: Wrap(
              spacing: 4,
              children: [
                _buildFriendshipAction(participant),
                IconButton(
                  tooltip: '私聊',
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  onPressed: () {},
                ),
                IconButton(
                  tooltip: '视频',
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        if (_roomBots.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('AI 助手', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final bot in _roomBots)
            PMListRow(
              leading: CircleAvatar(
                backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  color: AppColors.secondaryDark,
                ),
              ),
              title: Text(bot.roomNickname?.isNotEmpty == true
                  ? bot.roomNickname!
                  : bot.botName),
              subtitle: Text(bot.enabledInRoom ? '已启用' : '已停用'),
            ),
        ],
      ],
    );
  }

  Future<void> _loadFriendshipState() async {
    try {
      final responses = await Future.wait<dynamic>([
        _contactService.getFriends(),
        _contactService.getSentFriendRequests(),
      ]);
      final friends = responses[0] as List<User>;
      final sentRequests = responses[1] as List<FriendshipRequest>;
      if (!mounted) return;
      final currentUserId = _authService.currentUser?.id;
      _setViewState(() {
        _friendUserIds
          ..clear()
          ..addAll(friends.map((friend) => friend.id));
        _pendingFriendRequestUserIds
          ..clear()
          ..addAll(sentRequests
              .where((request) => request.status.toUpperCase() == 'PENDING')
              .map((request) {
            if (request.friend.id.isNotEmpty &&
                request.friend.id != currentUserId) {
              return request.friend.id;
            }
            return request.user.id;
          }).where((id) => id.isNotEmpty));
      });
    } catch (_) {
      // Friend state is progressive UI chrome; the chat itself must not fail.
    }
  }

  Widget _buildFriendshipAction(User participant) {
    final userId = participant.id;
    final currentUserId = _authService.currentUser?.id;
    if (userId.isEmpty || userId == currentUserId) {
      return const SizedBox.shrink();
    }

    if (_friendUserIds.contains(userId)) {
      return const IconButton(
        tooltip: '已是好友',
        icon: Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: AppColors.success,
        ),
        onPressed: null,
      );
    }

    if (_pendingFriendRequestUserIds.contains(userId)) {
      return const IconButton(
        tooltip: '好友请求已发送',
        icon: Icon(
          Icons.hourglass_top_rounded,
          size: 18,
          color: AppColors.warning,
        ),
        onPressed: null,
      );
    }

    final isSending = _sendingFriendRequestUserIds.contains(userId);
    return IconButton(
      tooltip: '添加好友',
      icon: isSending
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.person_add_alt_1_rounded, size: 18),
      onPressed:
          isSending ? null : () => _sendFriendRequestFromMember(participant),
    );
  }

  Future<void> _sendFriendRequestFromMember(User participant) async {
    final userId = participant.id;
    if (userId.isEmpty || _sendingFriendRequestUserIds.contains(userId)) {
      return;
    }

    _setViewState(() {
      _sendingFriendRequestUserIds.add(userId);
    });

    try {
      final request = await _contactService.sendFriendRequest(userId);
      if (!mounted) return;
      final status = request.status.toUpperCase();
      _setViewState(() {
        _sendingFriendRequestUserIds.remove(userId);
        if (status == 'ACCEPTED') {
          _friendUserIds.add(userId);
        } else {
          _pendingFriendRequestUserIds.add(userId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'ACCEPTED'
              ? '已添加 ${_memberDisplayName(participant)}'
              : '已向 ${_memberDisplayName(participant)} 发送好友请求'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _setViewState(() {
        _sendingFriendRequestUserIds.remove(userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('好友请求失败: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _memberDisplayName(User user) {
    if (user.displayName.isNotEmpty) return user.displayName;
    if (user.username.isNotEmpty) return user.username;
    return '成员';
  }
}
