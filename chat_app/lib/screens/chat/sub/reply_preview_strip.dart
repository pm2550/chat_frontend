part of '../chat_screen.dart';

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
    final targetId = message.replyToMessage?.id ?? message.replyToId;
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
                  ? '匿名发送中：${_anonymousIdentity!.anonymousName}'
                  : '本房间已开启匿名模式，点击输入框左侧匿名按钮后发送将隐藏真实身份。',
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
            TextButton(
              onPressed: _toggleAnonymousSendMode,
              child: Text(
                _anonymousPerMessageMode
                    ? (_anonymousNextMessage ? '逐条 · 匿名' : '逐条 · 实名')
                    : '持续匿名',
                style: TextStyle(color: accent),
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
                    ? '重抽'
                    : '重抽 · 剩 ${_anonymousQuota!.remaining}',
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
          SnackBar(content: Text(result.message ?? '今日匿名身份切换次数已用完，请明天再试')),
        );
      }
      return;
    }
    final identity = result.identity;
    if (identity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '匿名身份重抽失败')),
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

  void _toggleAnonymousSendMode() {
    _setViewState(() {
      if (_anonymousPerMessageMode) {
        _anonymousNextMessage = !_anonymousNextMessage;
      } else {
        _anonymousPerMessageMode = true;
        _anonymousNextMessage = true;
      }
    });
    final roomId = int.tryParse(_chat.id);
    if (roomId != null) {
      unawaited(_anonymousService.setMode(
        roomId,
        ChatAnonymousMode.perMessage,
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
