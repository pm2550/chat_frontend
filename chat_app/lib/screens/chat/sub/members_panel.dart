part of '../chat_screen.dart';

extension _ChatScreenMembersPanelParts on _ChatScreenState {
  Widget _buildDesktopInfoPanel() {
    // Private (1-on-1) chats get a QQ-style panel: friend profile + files + actions.
    // Group chats keep the members/files/Bot/memory tabs.
    final isGroup = _chat.type == ChatType.group;
    final tabs = isGroup
        ? const [
            (PMSymbol.members, '成员', AppColors.primary),
            (PMSymbol.files, '文件', AppColors.primary),
            (PMSymbol.ai, 'Bot', AppColors.secondaryDark),
            // No dedicated memory glyph exists in PMSymbol; reuse the
            // knowledge-node workspace glyph for the 记忆 (memory) tab.
            (PMSymbol.workspace, '记忆', Color(0xFF7C3AED)),
          ]
        : const [
            (PMSymbol.profile, '资料', AppColors.primary),
            (PMSymbol.files, '文件', AppColors.primary),
          ];
    // Tab index is shared state across rooms; a leftover group index (e.g. 记忆=3)
    // falls back to the first tab (资料) when viewing a 2-tab private panel.
    final selectedTab =
        _desktopInfoPanelTab <= (tabs.length - 1) ? _desktopInfoPanelTab : 0;
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
                    color: selectedTab == i
                        ? tabs[i].$3
                        : AppColors.textSecondary,
                    style: IconButton.styleFrom(
                      backgroundColor: selectedTab == i
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
                            selected: selectedTab == i,
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
                child: isGroup
                    ? switch (selectedTab) {
                        0 => _buildMembersPanel(),
                        1 => _buildFilesPanel(),
                        2 => _buildBotsPanel(),
                        3 => _buildMemoryPanel(),
                        _ => _buildMembersPanel(),
                      }
                    : switch (selectedTab) {
                        1 => _buildFilesPanel(),
                        _ => _buildPrivateProfilePanel(),
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
                          _displayChatTitle(),
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

  Widget _buildMemoryPanel() {
    return MemoryPanel(
      service: _memoryService,
      roomId: int.tryParse(_chat.id) ?? 0,
      currentUserId: _authService.currentUser?.id,
      resolveUserName: (userId) {
        for (final u in _chat.participants) {
          if (u.id == userId.toString()) {
            return u.displayName.isNotEmpty ? u.displayName : u.username;
          }
        }
        return '';
      },
      resolveBotName: (botId) {
        for (final b in _roomBots) {
          if (b.id.toString() == botId.toString()) {
            return (b.roomNickname?.isNotEmpty == true)
                ? b.roomNickname!
                : b.botName;
          }
        }
        return '';
      },
    );
  }

  // ---- Private (1-on-1) info panel: friend profile + actions (QQ-style) ----

  Widget _buildPrivateProfilePanel() {
    final currentUserId = _authService.currentUser?.id;
    final others =
        _chat.participants.where((u) => u.id != currentUserId).toList();
    final User? other = others.isNotEmpty
        ? others.first
        : (_chat.participants.isNotEmpty ? _chat.participants.first : null);

    return ListView(
      children: [
        PMCard(
          elevated: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (other != null) ...[
                PMUserAvatar(
                  user: other,
                  size: 72,
                  status: PMOnlineStatus.fromUserStatus(other.onlineStatus),
                  showOnlineDot: true,
                ),
                const SizedBox(height: 10),
                Text(
                  _memberDisplayName(other),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  other.onlineStatus.name,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                _buildFriendshipAction(other),
              ] else
                const Text('聊天信息',
                    style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('操作', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        PMCard(
          elevated: false,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('消息免打扰'),
                value: _chat.isMuted,
                onChanged: _togglePrivateMute,
              ),
              SwitchListTile(
                title: const Text('置顶聊天'),
                value: _chat.isPinned,
                onChanged: _togglePrivatePin,
              ),
              PMListRow(
                leading: const Icon(Icons.delete_sweep_rounded,
                    color: AppColors.error),
                title: const Text('清空聊天记录'),
                onTap: _confirmClearPrivateHistory,
              ),
              PMListRow(
                leading: const Icon(Icons.settings_rounded,
                    color: AppColors.textSecondary),
                title: const Text('聊天设置'),
                onTap: _openRoomSettings,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _togglePrivateMute(bool value) async {
    try {
      await _chatService.updateNotificationSettings(_chat.id, muted: value);
      if (!mounted) return;
      _setViewState(() => _chat = _chat.copyWith(isMuted: value));
    } catch (error) {
      _privateActionError('设置失败: $error');
    }
  }

  Future<void> _togglePrivatePin(bool value) async {
    try {
      await _chatService.updateNotificationSettings(_chat.id, pinned: value);
      if (!mounted) return;
      _setViewState(() => _chat = _chat.copyWith(isPinned: value));
    } catch (error) {
      _privateActionError('设置失败: $error');
    }
  }

  Future<void> _confirmClearPrivateHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PMDialogHeader(title: '清空聊天记录', showHandle: false),
        content: const Text('确定清空与对方的聊天记录吗？此操作仅清空你这边，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _chatService.clearChatHistory(_chat.id);
      if (!mounted) return;
      _setViewState(() => _messages = []);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清空聊天记录')));
    } catch (error) {
      _privateActionError('清空失败: $error');
    }
  }

  void _privateActionError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}
