part of '../chat_screen.dart';

extension _ChatScreenBotsPanelParts on _ChatScreenState {
  Future<void> _loadRoomBots() async {
    final roomId = int.tryParse(_chat.id);
    if (roomId == null) return;
    _setViewState(() => _isLoadingRoomBots = true);
    try {
      final bots = await _botService.getBotsInRoom(roomId);
      if (!mounted) return;
      _setViewState(() {
        _roomBots = bots;
        _isLoadingRoomBots = false;
      });
      if (_mentionStartIndex != null) {
        _updateMentionSuggestions(
          _messageController.text,
          _messageController.selection.baseOffset,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _setViewState(() => _isLoadingRoomBots = false);
    }
  }

  Widget _buildBotsPanel() {
    if (_isLoadingRoomBots) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_roomBots.isEmpty) {
      return PMEmptyState(
        icon: Icons.smart_toy_rounded,
        title: '本群暂无 AI 助手',
        subtitle: '可以从 AI 助手页创建 Bot，再加入当前群。',
        action: PMButton(
          label: '去 AI 助手',
          icon: Icons.open_in_new,
          onPressed: () => Navigator.of(context).pushReplacementNamed(
            '/home/ai/bots',
          ),
        ),
      );
    }
    final roomId = int.tryParse(_chat.id) ?? 0;
    return ListView.separated(
      itemCount: _roomBots.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final bot = _roomBots[index];
        return PMCard(
          elevated: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                subtitle: Text(
                  '${bot.llmProvider} · ${bot.modelName ?? '默认模型'}',
                ),
                badge: bot.enabledInRoom ? '启用' : '停用',
                badgeColor: bot.enabledInRoom
                    ? AppColors.secondaryDark
                    : AppColors.error,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PMChip(
                    label: _botTriggerLabel(bot.triggerMode),
                    icon: _botTriggerIcon(bot.triggerMode),
                    selected: true,
                    color: AppColors.secondaryDark,
                  ),
                  PMButton(
                    label: '查看配置',
                    icon: Icons.tune,
                    compact: true,
                    variant: PMButtonVariant.secondary,
                    onPressed: () async {
                      // Authoritative owner check via member role; createdBy goes stale
                      // after an ownership transfer, so only use it as a fallback.
                      final uid = _authService.currentUser?.id;
                      var isOwner = _chat.createdBy == uid;
                      try {
                        final members =
                            await _chatService.getChatRoomMembers(_chat.id);
                        isOwner = members
                            .any((m) => m.userId == uid && m.isOwner);
                      } catch (_) {
                        // Fall back to the createdBy heuristic; server still enforces 403.
                      }
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatRoomBotConfigScreen(
                            roomId: roomId,
                            bot: bot,
                            botService: _botService,
                            chatService: _chatService,
                            isOwner: isOwner,
                          ),
                        ),
                      );
                      _loadRoomBots();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _botTriggerLabel(String? mode) {
    return switch ((mode ?? 'MENTION').toUpperCase()) {
      'KEYWORD' => '关键词触发',
      'REGEX' => '正则触发',
      'ALL' => '全消息触发',
      _ => '提及触发',
    };
  }

  IconData _botTriggerIcon(String? mode) {
    return switch ((mode ?? 'MENTION').toUpperCase()) {
      'KEYWORD' => Icons.key,
      'REGEX' => Icons.data_object,
      'ALL' => Icons.all_inclusive,
      _ => Icons.alternate_email,
    };
  }

  void _openRoomSettings() {
    unawaited(() async {
      final left = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ChatRoomSettingsScreen(
            chatRoomId: int.tryParse(_chat.id) ?? 0,
            chatRoomName: _chat.name,
            isAdmin: _chat.createdBy == _authService.currentUser?.id,
            isGroup: _chat.type == ChatType.group,
            currentUserId: _authService.currentUser?.id,
            chatService: _chatService,
            initialAnonymousEnabled: _chat.anonymousEnabled,
          ),
        ),
      );
      if (left == true && mounted) {
        Navigator.of(context).pop(true);
        return;
      }
      if (!mounted) return;
      try {
        final updated = await _chatService.getChatRoom(_chat.id);
        if (!mounted) return;
        _setViewState(() => _chat = updated);
      } catch (_) {
        // Settings changes are still visible after the next room refresh.
      }
    }());
  }
}
