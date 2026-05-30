part of '../chat_screen.dart';

extension _ChatScreenMessageListParts on _ChatScreenState {
  Widget _buildMessageArea() {
    return PMChatBackgroundLayer(
      preset: _effectiveBackgroundPreset,
      customUrl: _effectiveBackgroundUrl,
      child: Stack(
        children: [
          if (_isLoadingMessages)
            const Center(child: CircularProgressIndicator())
          else if (_errorMessage != null)
            _buildMessageLoadError()
          else if (_messages.isEmpty && _agentTasks.isEmpty)
            _buildEmptyMessages()
          else
            _buildMessageList(),
          if (_showNewMessagesButton)
            Positioned(
              right: 20,
              bottom: 18,
              child: FilledButton.icon(
                onPressed: () {
                  _setViewState(() {
                    _newMessagesBelow = 0;
                    _showNewMessagesButton = false;
                  });
                  _scrollToBottom();
                },
                icon: const Icon(Icons.keyboard_arrow_down),
                label: Text('$_newMessagesBelow 条新消息'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final currentUserId = _authService.currentUser?.id;
    final messageOffset = _isLoadingOlderMessages ? 1 : 0;
    final taskOffset = messageOffset + _messages.length;
    final typingOffset = taskOffset + _agentTasks.length;
    final remoteTypingOffset =
        typingOffset + (_isSendingAttachment || _isRunningAgentTask ? 1 : 0);
    final itemCount =
        remoteTypingOffset + (_typingUserNames.isNotEmpty ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (_isLoadingOlderMessages && index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (index >= taskOffset && index < typingOffset) {
          return _buildAgentTaskCard(_agentTasks[index - taskOffset]);
        }
        if (index == typingOffset &&
            (_isSendingAttachment || _isRunningAgentTask)) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TypingIndicator(
              userName: _isRunningAgentTask ? 'Agent' : '文件',
              isBot: _isRunningAgentTask,
            ),
          );
        }
        if (index == remoteTypingOffset && _typingUserNames.isNotEmpty) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TypingIndicator(userNames: _typingUserNames),
          );
        }
        final messageIndex = index - messageOffset;
        final message = _messages[messageIndex];
        final previousMessage =
            messageIndex == 0 ? null : _messages[messageIndex - 1];
        final isMe = currentUserId != null && message.senderId == currentUserId;
        final startsNewGroup = previousMessage == null ||
            previousMessage.senderId != message.senderId ||
            message.timestamp
                    .difference(previousMessage.timestamp)
                    .inMinutes
                    .abs() >
                5;
        final showDateSeparator = previousMessage == null ||
            !_isSameMessageDate(previousMessage.timestamp, message.timestamp);

        return Column(
          key: _messageKeyFor(message.id),
          children: [
            if (showDateSeparator)
              _MessageDateSeparator(
                label: _formatMessageDateLabel(message.timestamp),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: _highlightedMessageId == message.id
                    ? AppColors.warning.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: EdgeInsets.only(top: startsNewGroup ? 8 : 2),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onLongPress: () => _showMessageActions(message, isMe),
                  onSecondaryTap: () => _showMessageActions(message, isMe),
                  child: MessageBubble(
                    message: message,
                    isMe: isMe,
                    showAvatar: message.isAnonymous ||
                        (_chat.type == ChatType.group && startsNewGroup),
                    onOpenAttachment: _openAttachment,
                    onRetrySend: _retryFailedMessage,
                    onOpenReply: () => _scrollToQuotedMessage(message),
                    onMentionTap: _showMentionProfile,
                    currentUserId: currentUserId,
                    onToggleReaction: _toggleReaction,
                    pollLoader: _chatService.getPoll,
                    onVotePoll: _chatService.votePoll,
                    pollRefreshEpoch: _pollRefreshEpoch,
                    linkPreviewLoader: _loadLinkPreview,
                    bubbleStylePreset: isMe
                        ? _appSettings.bubbleStylePreset
                        : ChatCustomizationCatalog.defaultBubbleStyle,
                    senderAvatarFramePreset:
                        _avatarFramePresetForMessage(message, isMe),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _avatarFramePresetForMessage(Message message, bool isMe) {
    if (message.isAnonymous) {
      return ChatCustomizationCatalog.defaultAvatarFrame;
    }
    if (isMe) {
      return _appSettings.avatarFramePreset;
    }
    for (final participant in _chat.participants) {
      if (participant.id == message.senderId) {
        return participant.avatarFramePreset;
      }
    }
    return ChatCustomizationCatalog.defaultAvatarFrame;
  }

  Widget _buildAgentTaskCard(AgentTask task) {
    final statusColor = switch (task.status) {
      AgentTaskStatus.pending => AppColors.warning,
      AgentTaskStatus.running => AppColors.primary,
      AgentTaskStatus.succeeded => AppColors.success,
      AgentTaskStatus.failed => AppColors.error,
    };
    final statusText = switch (task.status) {
      AgentTaskStatus.pending => '等待中',
      AgentTaskStatus.running => '执行中',
      AgentTaskStatus.succeeded => '已完成',
      AgentTaskStatus.failed => '失败',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: PMCard(
            elevated: false,
            background: Colors.white.withValues(alpha: 0.92),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.smart_toy_rounded,
                        color: AppColors.secondaryDark, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _statusPill(statusText, statusColor),
                  ],
                ),
                if (task.status == AgentTaskStatus.running ||
                    task.status == AgentTaskStatus.pending) ...[
                  const SizedBox(height: 10),
                  PMProgressStrip(label: statusText),
                ],
                if (task.errorMessage?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    task.errorMessage!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                if (task.artifactFileName?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  PMAttachmentCard(
                    type: AttachmentType.file,
                    name: task.artifactFileName!,
                    sizeText: 'Agent 产物',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retryFailedMessage(Message message) async {
    if (message.status != MessageStatus.failed || message.content.isEmpty) {
      return;
    }
    _setViewState(() {
      _messages.removeWhere((item) => item.id == message.id);
      _messageController.text = message.type == MessageType.text
          ? message.content
          : _messageController.text;
    });
    if (message.type == MessageType.text) {
      await _sendMessage();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('附件重发需要重新选择文件')),
      );
    }
  }

  void _showMentionProfile(String mentionLabel) {
    final normalized = mentionLabel.trim().toLowerCase();
    final participant = _chat.participants.cast<User?>().firstWhere(
          (user) =>
              user != null &&
              (user.displayName.toLowerCase() == normalized ||
                  user.username.toLowerCase() == normalized),
          orElse: () => null,
        );
    if (participant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('未找到 @$mentionLabel 对应的成员')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PMCard(
            radius: PMRadius.l,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PMListRow(
                  leading: PMUserAvatar(
                    user: participant,
                    status: PMOnlineStatus.fromUserStatus(
                      participant.onlineStatus,
                    ),
                    showOnlineDot: true,
                  ),
                  title: Text(participant.displayName.isNotEmpty
                      ? participant.displayName
                      : participant.username),
                  subtitle: Text('@${participant.username}'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('关闭'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _setViewState(() => _desktopInfoPanelTab = 0);
                      },
                      icon: const Icon(Icons.groups, size: 18),
                      label: const Text('查看成员'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              '消息加载失败',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialMessages,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyMessages() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PMChatMark(size: 54),
              SizedBox(height: 12),
              Text(
                '暂无消息',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '发出第一条消息，PM chat 会把上下文留在这里。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMessageTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return '今天 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return '昨天 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return '${weekdays[timestamp.weekday - 1]} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.month}月${timestamp.day}日 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  bool _isSameMessageDate(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatMessageDateLabel(DateTime timestamp) {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    if (date == today) return '今天';
    if (date == today.subtract(const Duration(days: 1))) return '昨天';
    return '${local.month}月${local.day}日';
  }
}

class _MessageDateSeparator extends StatelessWidget {
  const _MessageDateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
