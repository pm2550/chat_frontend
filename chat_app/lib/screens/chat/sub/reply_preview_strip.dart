part of '../chat_screen.dart';

/// 下一条消息用什么身份发。三个选项互斥，菜单里直接选中生效。
enum _AnonymousSendChoice { always, nextAnonymous, nextRealName }

extension _ChatScreenAnonymousParts on _ChatScreenState {
  Widget _buildReplyPreviewStrip() {
    final message = _replyingToMessage;
    if (message == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ReplyPreviewStrip(
        message: message,
        onCancel: () {
          _setViewState(() => _replyingToMessage = null);
        },
      ),
    );
  }

  void _quoteMessage(Message message) {
    _setViewState(() => _replyingToMessage = message);
    _focusNode.requestFocus();
  }

  GlobalKey _messageKeyFor(String messageId) {
    return _messageKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  void _scrollToQuotedMessage(Message message) {
    final targetId = message.replyToMessage?.id ??
        message.replyToMessageId ??
        message.replyToId;
    if (targetId == null || targetId.isEmpty) return;
    final key = _messageKeys[targetId];
    final context = key?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    } else {
      final index = _messages.indexWhere((item) => item.id == targetId);
      if (index != -1 && _scrollController.hasClients) {
        final estimate = (index * 96.0).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          estimate,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    }
    _messageHighlightTimer?.cancel();
    _setViewState(() => _highlightedMessageId = targetId);
    _messageHighlightTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _highlightedMessageId == targetId) {
        _setViewState(() => _highlightedMessageId = null);
      }
    });
  }

  Widget _buildAnonymousBanner() {
    if (!_chat.anonymousEnabled) {
      return const SizedBox.shrink();
    }

    final theme = _anonymousIdentity?.theme;
    final accent = _parseAnonymousColor(
          theme?.accentColor ?? _anonymousIdentity?.anonymousAvatar,
        ) ??
        const Color(0xFF7C3AED);
    final active = _anonymousIdentity != null;
    final isDesktop = PMBreakpoints.isDesktop(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 22 : 14,
        8,
        isDesktop ? 22 : 14,
        8,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        border: Border(
          top: BorderSide(color: accent.withValues(alpha: 0.18)),
          bottom: BorderSide(color: accent.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.visibility_off_outlined, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              active
                  ? (_shouldSendAnonymous()
                      ? '这条会匿名发送：${_anonymousIdentity!.anonymousName}'
                      : '这条会用你自己的名字发送')
                  : '这个群可以匿名说话。点输入框左边的匿名按钮，别人就看不到是你发的。',
              maxLines: isDesktop ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: isDesktop ? 13 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (theme != null) ...[
            const SizedBox(width: 8),
            _buildAnonymousChip(theme.displayName, accent),
          ],
          if (active) ...[
            const SizedBox(width: 6),
            PopupMenuButton<_AnonymousSendChoice>(
              tooltip: '选择下一条用什么身份发',
              onSelected: _applyAnonymousSendChoice,
              itemBuilder: (context) => [
                _anonymousChoiceItem(
                  _AnonymousSendChoice.always,
                  '一直匿名',
                  '每条都匿名，直到你退出匿名',
                  accent,
                ),
                _anonymousChoiceItem(
                  _AnonymousSendChoice.nextAnonymous,
                  '下一条匿名',
                  '只有下一条匿名，发完自动回真名',
                  accent,
                ),
                _anonymousChoiceItem(
                  _AnonymousSendChoice.nextRealName,
                  '下一条用真名',
                  '下一条用你自己的名字发',
                  accent,
                ),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _anonymousSendModeLabel(),
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, size: 18, color: accent),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: _anonymousQuota?.remaining == 0
                  ? null
                  : _rerollAnonymousIdentity,
              icon: Icon(Icons.casino_outlined, size: 16, color: accent),
              label: Text(
                _anonymousQuota == null
                    ? '换个名字'
                    : '换个名字 · 还能换 ${_anonymousQuota!.remaining} 次',
                style: TextStyle(color: accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnonymousChip(String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Future<void> _rerollAnonymousIdentity() async {
    final roomId = int.tryParse(_chat.id);
    if (roomId == null) return;
    if (_isRerollingAnonymous) return;
    _setViewState(() => _isRerollingAnonymous = true);
    final result = await _anonymousService.rerollAnonymousWithResult(roomId);
    if (!mounted) return;
    _setViewState(() => _isRerollingAnonymous = false);
    if (result.quotaExhausted) {
      final quota = await _anonymousService.getQuota();
      if (mounted) {
        _setViewState(() => _anonymousQuota = quota);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? '今天换名字的次数用完了，明天再来')),
        );
      }
      return;
    }
    final identity = result.identity;
    if (identity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '换名字失败了，稍后再试')),
      );
      return;
    }
    _setViewState(() {
      _anonymousIdentity = identity;
      _anonymousQuota = AnonymousQuota(
        used: 3 - (identity.dailyRemaining ?? 0),
        remaining: identity.dailyRemaining ?? 0,
        resetsAt: identity.quotaResetsAt,
      );
      if (_anonymousPerMessageMode) {
        _anonymousNextMessage = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换为 ${identity.anonymousName}')),
    );
  }

  bool _shouldSendAnonymous() =>
      _anonymousIdentity != null &&
      (!_anonymousPerMessageMode || _anonymousNextMessage);

  AnonymousIdentity? _activeSendIdentity() =>
      _shouldSendAnonymous() ? _anonymousIdentity : null;

  void _afterOutgoingMessage() {
    if (_anonymousPerMessageMode && _anonymousNextMessage) {
      _setViewState(() => _anonymousNextMessage = false);
    }
  }

  _AnonymousSendChoice get _anonymousSendChoice {
    if (!_anonymousPerMessageMode) return _AnonymousSendChoice.always;
    return _anonymousNextMessage
        ? _AnonymousSendChoice.nextAnonymous
        : _AnonymousSendChoice.nextRealName;
  }

  String _anonymousSendModeLabel() {
    switch (_anonymousSendChoice) {
      case _AnonymousSendChoice.always:
        return '一直匿名';
      case _AnonymousSendChoice.nextAnonymous:
        return '下一条匿名';
      case _AnonymousSendChoice.nextRealName:
        return '下一条用真名';
    }
  }

  PopupMenuItem<_AnonymousSendChoice> _anonymousChoiceItem(
    _AnonymousSendChoice choice,
    String title,
    String subtitle,
    Color accent,
  ) {
    final selected = _anonymousSendChoice == choice;
    return PopupMenuItem<_AnonymousSendChoice>(
      value: choice,
      height: 58,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 22,
            child: selected
                ? Icon(Icons.check, size: 16, color: accent)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? accent : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 菜单里选中即生效，不存在“点一下就被切走”。
  void _applyAnonymousSendChoice(_AnonymousSendChoice choice) {
    final perMessage = choice != _AnonymousSendChoice.always;
    final nextAnonymous = choice == _AnonymousSendChoice.nextAnonymous;
    _setViewState(() {
      _anonymousPerMessageMode = perMessage;
      _anonymousNextMessage = nextAnonymous;
    });
    final roomId = int.tryParse(_chat.id);
    if (roomId != null) {
      unawaited(_anonymousService.setMode(
        roomId,
        perMessage ? ChatAnonymousMode.perMessage : ChatAnonymousMode.sticky,
      ));
    }
  }

  void _setAnonymousMode(bool perMessage) {
    _setViewState(() {
      _anonymousPerMessageMode = perMessage;
      _anonymousNextMessage = perMessage && _anonymousIdentity != null;
    });
    final roomId = int.tryParse(_chat.id);
    if (roomId != null) {
      unawaited(_anonymousService.setMode(
        roomId,
        perMessage ? ChatAnonymousMode.perMessage : ChatAnonymousMode.sticky,
      ));
    }
  }

  void _applyAnonymousIdentity(AnonymousIdentity? identity) {
    _setViewState(() {
      _anonymousIdentity = identity;
      if (identity != null && _anonymousPerMessageMode) {
        _anonymousNextMessage = true;
      }
      if (identity == null) {
        _anonymousQuota = null;
        _anonymousNextMessage = false;
      }
    });
    if (identity != null) {
      _refreshAnonymousQuota();
    }
  }

  Future<void> _refreshAnonymousQuota() async {
    final quota = await _anonymousService.getQuota();
    if (!mounted || quota == null) return;
    _setViewState(() => _anonymousQuota = quota);
  }
}

class ReplyPreviewStrip extends StatelessWidget {
  const ReplyPreviewStrip({
    super.key,
    required this.message,
    required this.onCancel,
  });

  final Message message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final excerpt = _replyExcerpt(message, maxLength: 80);
    return PMCard(
      elevated: false,
      padding: EdgeInsets.zero,
      background: AppColors.cloud,
      radius: PMRadius.s,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(PMRadius.s),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '回复 ${message.senderName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      excerpt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '取消引用',
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

String _replyExcerpt(Message message, {int maxLength = 80}) {
  if (message.isRemoved) {
    return '原消息已删除';
  }
  final raw = message.type == MessageType.text
      ? message.content
      : message.resolvedFileLabel;
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) {
    return message.type.description;
  }
  if (text.length <= maxLength) {
    return text;
  }
  return '${text.substring(0, maxLength)}...';
}
