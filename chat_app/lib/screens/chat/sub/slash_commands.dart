part of '../chat_screen.dart';

const String _kE2eeAiBlockedReason = '端到端加密的私聊里不能用 AI';

/// 输入框上方 "/" 命令面板的状态。
class _SlashPanelState {
  List<SlashCommand> suggestions = const [];
  int selectedIndex = 0;
}

/// 输入框里的 "/" 快捷命令：/画图、/问、房间里的机器人、/投票、/位置。
/// 面板和 @ 成员面板是同一套做法（输入框上方的内联面板、↑↓ 选、Enter/Tab 确定、Esc 关）；
/// 直接打 "/画图 一只猫" 回车也行，发送时在 [_applySlashCommandOnSend] 里执行或改写。
extension _ChatScreenSlashCommandParts on _ChatScreenState {
  bool get _isSlashPanelVisible => _slashPanel.suggestions.isNotEmpty;

  /// 服务器认为这个私聊是端到端加密的（双方都开了，不管本机解没解锁）：
  /// 发出去的都是密文，AI 看不到；画图的描述和结果却会以明文存在服务器上。
  bool get _e2eeBlocksAi => switch (_e2eeRoom.mode) {
        E2eeRoomMode.active ||
        E2eeRoomMode.needsUnlock ||
        E2eeRoomMode.keyChanged =>
          true,
        _ => false,
      };

  /// 加密私聊里要用 AI：提示并返回 true（调用方什么都不做）。
  bool _refuseAiInE2eeChat() {
    if (!_e2eeBlocksAi) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(_kE2eeAiBlockedReason)),
    );
    return true;
  }

  List<SlashCommand> _roomSlashCommands() {
    final agent = _systemAgentBot();
    final myId = _authService.currentUser?.id;
    return buildSlashCommands(
      agentLabel: agent == null ? null : _botMentionLabel(agent),
      bots: [
        for (final bot in _roomBots)
          if (bot.enabledInRoom &&
              !identical(bot, agent) &&
              _botAnswersMentions(bot) &&
              _canTriggerBot(bot, myId))
            SlashBotEntry(
              label: _botMentionLabel(bot),
              botName: bot.botName,
              avatarUrl: bot.botAvatar,
            ),
      ],
    );
  }

  /// 只按关键词/正则触发的机器人 @ 它也不会回，不给它命令。
  static bool _botAnswersMentions(BotConfig bot) =>
      switch ((bot.triggerMode ?? 'MENTION').toUpperCase()) {
        'KEYWORD' || 'REGEX' => false,
        _ => true,
      };

  /// 和服务器 BotService.canTriggerBot 一致：系统机器人、自己的、公开的可以；
  /// 白名单的名单只有主人看得到，这里放行交给服务器判断；别人的私有机器人不给。
  static bool _canTriggerBot(BotConfig bot, String? myId) {
    final owner = bot.createdById;
    if (owner == null || owner.toString() == myId) return true;
    return switch (bot.accessPolicy.toUpperCase()) {
      'PUBLIC' => true,
      'ALLOWLIST' => bot.allowedUsers.isEmpty ||
          bot.allowedUsers.any((user) => user.id.toString() == myId),
      _ => false,
    };
  }

  void _updateSlashSuggestions(String text, int selectionOffset) {
    final query = slashCommandQuery(text, selectionOffset);
    final next = query == null
        ? const <SlashCommand>[]
        : filterSlashCommands(_roomSlashCommands(), query);
    if (next.isEmpty && _slashPanel.suggestions.isEmpty) return;
    _setViewState(() {
      _slashPanel
        ..suggestions = next
        ..selectedIndex = 0;
    });
  }

  void _clearSlashSuggestions() {
    if (!_isSlashPanelVisible) return;
    _setViewState(() {
      _slashPanel
        ..suggestions = const []
        ..selectedIndex = 0;
    });
  }

  void _moveSlashSelection(int delta) {
    if (!_isSlashPanelVisible) return;
    final count = _slashPanel.suggestions.length;
    _setViewState(() {
      _slashPanel.selectedIndex =
          (_slashPanel.selectedIndex + delta + count) % count;
    });
  }

  /// Tab 也能选命令（面板没开时不拦，照常切换焦点）。
  Widget _withSlashTabKey(Widget child) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyUpEvent ||
              event.logicalKey != LogicalKeyboardKey.tab ||
              HardwareKeyboard.instance.isShiftPressed ||
              !_isSlashPanelVisible) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) _chooseSlashCommand();
          return KeyEventResult.handled;
        },
        child: child,
      );

  void _chooseSlashCommand([SlashCommand? picked]) {
    if (!_isSlashPanelVisible) return;
    final command =
        picked ?? _slashPanel.suggestions[_slashPanel.selectedIndex];
    _clearSlashSuggestions();
    if (command.usesAi && _refuseAiInE2eeChat()) return;
    final value = _messageController.value;
    final cursor =
        _clampTextOffset(value.selection.baseOffset, value.text.length);
    final rest = value.text.substring(cursor).trimLeft();
    switch (command.kind) {
      case SlashCommandKind.draw:
        _replaceComposerText('/${command.name} ', rest);
      case SlashCommandKind.ask:
      case SlashCommandKind.bot:
        _replaceComposerText('', rest);
        _insertMentionForUser(
          _mentionUserForLabel(command.mentionLabel!, command.avatarUrl),
          replaceStart: 0,
          replaceEnd: 0,
        );
      case SlashCommandKind.poll:
        _replaceComposerText('', rest);
        _showPollCreateSheet();
      case SlashCommandKind.location:
        _replaceComposerText('', rest);
        unawaited(_sendLocationMessage());
    }
  }

  /// 输入框换成 [head] + [tail]，光标停在 [head] 后面。
  void _replaceComposerText(String head, String tail) {
    final text = '$head$tail';
    _messageController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: head.length),
    );
    _setViewState(() => _isTyping = text.trim().isNotEmpty);
    _focusNode.requestFocus();
  }

  User _mentionUserForLabel(String label, String? avatarUrl) => User(
        id: 'bot-$label',
        username: label,
        email: '',
        displayName: label,
        avatarUrl: avatarUrl,
        onlineStatus: OnlineStatus.online,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// 发送前处理 "/命令"：返回真正要发的文字；返回 null 表示这条已经在这里执行了
  /// （画图、投票、位置）或被拒绝了（加密私聊、没写内容），不再发文字。
  /// 不认识的 "/xxx" 原样返回，照常当文字发（例如机器人的关键词 "/chat 你好"）。
  String? _applySlashCommandOnSend(String content) {
    final invocation = parseSlashInvocation(content, _roomSlashCommands());
    if (invocation == null) return content;
    final command = invocation.command;
    if (command.usesAi && _refuseAiInE2eeChat()) return null;
    switch (command.kind) {
      case SlashCommandKind.draw:
        if (invocation.body.isEmpty) {
          _showSlashHint('在 /${command.name} 后面写上想画什么');
          return null;
        }
        _clearComposerAfterSlashCommand();
        unawaited(_generateImageMessage(invocation.body));
        return null;
      case SlashCommandKind.ask:
      case SlashCommandKind.bot:
        if (invocation.body.isEmpty) {
          _showSlashHint('在 /${command.name} 后面写上想说的话');
          return null;
        }
        return invocation.mentionText;
      case SlashCommandKind.poll:
        _clearComposerAfterSlashCommand();
        _showPollCreateSheet();
        return null;
      case SlashCommandKind.location:
        _clearComposerAfterSlashCommand();
        unawaited(_sendLocationMessage());
        return null;
    }
  }

  void _showSlashHint(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _clearComposerAfterSlashCommand() {
    _messageController.clear();
    _clearSlashSuggestions();
    _clearMentionSuggestions();
    _setViewState(() => _isTyping = false);
  }

  /// 输入框上方：命令面板；或者正在写 "/画图 …" 时的一行提示。
  Widget _buildSlashCommandPanel() {
    if (!_isSlashPanelVisible) return _buildSlashDrawHint();
    final suggestions = _slashPanel.suggestions;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 320),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PMCard(
            key: const ValueKey('slash-command-panel'),
            elevated: true,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (context, index) => _buildSlashCommandRow(
                suggestions[index],
                selected: index == _slashPanel.selectedIndex,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlashCommandRow(SlashCommand command, {required bool selected}) {
    final disabled = command.usesAi && _e2eeBlocksAi;
    final Widget leading = switch (command.kind) {
      SlashCommandKind.bot => PMUserAvatar.raw(
          imageUrl: command.avatarUrl == null
              ? null
              : ApiConstants.resolveFileUrl(command.avatarUrl!),
          fallbackText: command.name,
          size: 40,
        ),
      _ => SizedBox(
          width: 40,
          child: PMSymbolIcon(
            switch (command.kind) {
              SlashCommandKind.draw => PMSymbol.image,
              SlashCommandKind.ask => PMSymbol.terminal,
              SlashCommandKind.poll => PMSymbol.poll,
              _ => PMSymbol.location,
            },
            size: 22,
            color: disabled ? AppColors.textTertiary : AppColors.primary,
          ),
        ),
    };
    return Opacity(
      key: ValueKey('slash-command-${command.name}'),
      opacity: disabled ? 0.55 : 1,
      child: PMListRow(
        leading: leading,
        title: Text('/${command.name}'),
        subtitle: Text(
          disabled ? _kE2eeAiBlockedReason : command.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        badge: selected ? 'Enter' : null,
        badgeColor: AppColors.primary,
        trailing: selected
            ? const Icon(Icons.keyboard_return, color: AppColors.primary)
            : null,
        onTap: () => _chooseSlashCommand(command),
      ),
    );
  }

  Widget _buildSlashDrawHint() {
    final text = _messageController.text;
    if (!text.trimLeft().startsWith('/') ||
        !isDrawCommandInProgress(text, _roomSlashCommands())) {
      return const SizedBox.shrink();
    }
    final blocked = _e2eeBlocksAi;
    return Padding(
      key: const ValueKey('slash-draw-hint'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        PMSymbolIcon(PMSymbol.image,
            size: 14,
            color: blocked ? AppColors.textTertiary : AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            blocked
                ? _kE2eeAiBlockedReason
                : 'AI 画图：写好描述直接发送 · $kDrawPriceHint',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        if (!blocked) ...[
          const SizedBox(width: 6),
          const ImagePromptHelperSelector(compact: true),
        ],
      ]),
    );
  }
}
