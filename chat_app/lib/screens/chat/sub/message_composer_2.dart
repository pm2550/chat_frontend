part of '../chat_screen.dart';

extension _ChatComposer2Parts on _ChatScreenState {
  Widget _buildMessageTextField({required String hintText}) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _isSlashPanelVisible
                ? _moveSlashSelection(1)
                : _moveMentionSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _isSlashPanelVisible
                ? _moveSlashSelection(-1)
                : _moveMentionSelection(-1),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _clearSlashSuggestions();
          _clearMentionSuggestions();
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_isSlashPanelVisible) {
            _chooseSlashCommand();
          } else if (_isMentionPickerVisible) {
            _chooseMentionSuggestion();
          } else {
            _sendMessage();
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter, shift: true):
            _insertMessageNewline,
      },
      child: _withSlashTabKey(TextField(
        controller: _messageController,
        focusNode: _focusNode,
        keyboardType: TextInputType.multiline,
        maxLines: 4,
        minLines: 1,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: _handleComposerChanged,
      )),
    );
  }

  bool get _isMentionPickerVisible =>
      _mentionStartIndex != null &&
      _mentionSuggestions.isNotEmpty &&
      !_isSlashPanelVisible;

  void _handleComposerChanged(String text) {
    final selection = _messageController.selection.baseOffset;
    _setViewState(() => _isTyping = text.isNotEmpty);
    _updateMentionSuggestions(text, selection);
    _updateSlashSuggestions(text, selection);
  }

  void _updateMentionSuggestions(String text, int selectionOffset) {
    if (selectionOffset < 0 || selectionOffset > text.length) {
      _clearMentionSuggestions();
      return;
    }
    final prefix = text.substring(0, selectionOffset);
    final atIndex = prefix.lastIndexOf('@');
    if (atIndex < 0 || (atIndex > 0 && prefix[atIndex - 1] == r'\')) {
      _clearMentionSuggestions();
      return;
    }

    final query = prefix.substring(atIndex + 1);
    if (query.contains(RegExp(r'\s'))) {
      _clearMentionSuggestions();
      return;
    }

    final normalized = query.toLowerCase();
    final source = _mentionSourceUsers();
    if (source.isEmpty && !_isLoadingMentionMembers) {
      unawaited(_loadMentionMembers().then((_) {
        if (!mounted) return;
        _updateMentionSuggestions(
          _messageController.text,
          _messageController.selection.baseOffset,
        );
      }));
    }

    final candidates = source.where(_isMentionableUser).where((user) {
      final display = user.displayName.toLowerCase();
      final username = user.username.toLowerCase();
      return normalized.isEmpty ||
          display.startsWith(normalized) ||
          username.startsWith(normalized);
    }).toList(growable: false);

    _setViewState(() {
      _mentionStartIndex = candidates.isEmpty ? null : atIndex;
      _mentionSuggestions = candidates;
      if (_mentionSelectedIndex >= candidates.length) {
        _mentionSelectedIndex = 0;
      }
    });
  }

  void _moveMentionSelection(int delta) {
    if (!_isMentionPickerVisible) return;
    _setViewState(() {
      _mentionSelectedIndex =
          (_mentionSelectedIndex + delta) % _mentionSuggestions.length;
      if (_mentionSelectedIndex < 0) {
        _mentionSelectedIndex += _mentionSuggestions.length;
      }
    });
  }

  void _chooseMentionSuggestion([User? selected]) {
    if (!_isMentionPickerVisible) return;
    final selection = _messageController.selection.baseOffset;
    final start = _mentionStartIndex;
    if (start == null || selection < start) {
      _clearMentionSuggestions();
      return;
    }
    final user = selected ?? _mentionSuggestions[_mentionSelectedIndex];
    _insertMentionForUser(user, replaceStart: start, replaceEnd: selection);
  }

  List<User> _mentionSourceUsers() {
    final source =
        _mentionMembers.isNotEmpty ? _mentionMembers : _chat.participants;
    final seen = <String>{};
    final users = <User>[];

    for (final user in source) {
      if (_isMentionableUser(user) && seen.add(user.id)) {
        users.add(user);
      }
    }

    for (final bot in _roomBots) {
      if (!bot.enabledInRoom) continue;
      final mentionUser = _mentionUserForBot(bot);
      if (seen.add(mentionUser.id)) {
        users.add(mentionUser);
      }
    }

    return users;
  }

  User _mentionUserForBot(BotConfig bot) {
    final label = _botMentionLabel(bot);
    return User(
      id: 'bot-${bot.id ?? label}',
      username: label,
      email: '',
      displayName: label,
      avatarUrl: bot.botAvatar,
      onlineStatus: OnlineStatus.online,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String _botMentionLabel(BotConfig bot) {
    final roomName = bot.roomNickname?.trim();
    if (roomName != null && roomName.isNotEmpty) {
      return roomName;
    }
    return bot.botName.trim();
  }

  void _insertMentionForUser(
    User user, {
    int? replaceStart,
    int? replaceEnd,
  }) {
    if (!_isMentionableUser(user)) return;
    final username = user.username.trim();
    final value = _messageController.value;
    final text = value.text;
    final selection = value.selection;
    final start =
        replaceStart ?? _clampTextOffset(selection.start, text.length);
    final end =
        replaceEnd ?? _clampTextOffset(selection.end, text.length, min: start);
    final needsLeadingSpace =
        start > 0 && !RegExp(r'\s').hasMatch(text.substring(start - 1, start));
    final mentionText = '${needsLeadingSpace ? ' ' : ''}@$username ';
    final nextText = text.replaceRange(start, end, mentionText);
    final nextOffset = start + mentionText.length;
    _messageController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    _clearMentionSuggestions();
    _setViewState(() => _isTyping = nextText.trim().isNotEmpty);
    _focusNode.requestFocus();
  }

  int _clampTextOffset(int offset, int length, {int min = 0}) {
    if (offset < 0) return length;
    if (offset < min) return min;
    if (offset > length) return length;
    return offset;
  }

  void _clearMentionSuggestions() {
    if (_mentionStartIndex == null && _mentionSuggestions.isEmpty) return;
    _setViewState(() {
      _mentionStartIndex = null;
      _mentionSuggestions = const [];
      _mentionSelectedIndex = 0;
    });
  }

  Future<void> _loadMentionMembers() async {
    if (_isLoadingMentionMembers) return;
    _isLoadingMentionMembers = true;
    try {
      final members = await _chatService.getChatRoomMembers(_chat.id);
      if (!mounted) return;
      _syncPinPermissions(members);
      _setViewState(() {
        final users =
            members.map((member) => member.user).toList(growable: false);
        _chat = _chat.copyWith(
          participants: users,
          memberCount: users.length,
        );
        _mentionMembers =
            users.where(_isMentionableUser).toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      _setViewState(() {
        _mentionMembers = _chat.participants
            .where(_isMentionableUser)
            .toList(growable: false);
      });
    } finally {
      _isLoadingMentionMembers = false;
    }
  }

  bool _isMentionableUser(User user) {
    final username = user.username.trim();
    if (username.isEmpty) return false;
    final normalized = username.toLowerCase();
    return !normalized.startsWith('anonymous_') &&
        !normalized.startsWith('anon_') &&
        !normalized.startsWith('anonymous-') &&
        !normalized.startsWith('anon-');
  }

  User? _participantForMessageSender(Message message) {
    if (message.isBotMessage) {
      final label = message.effectiveBotName.trim();
      if (label.isEmpty) return null;
      return User(
        id: 'bot-${message.botConfigId ?? message.botSenderId ?? label}',
        username: label,
        email: '',
        displayName: label,
        avatarUrl: message.botAvatar,
        onlineStatus: OnlineStatus.online,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }

    final source =
        _mentionMembers.isNotEmpty ? _mentionMembers : _chat.participants;
    for (final participant in source) {
      if (participant.id == message.senderId &&
          _isMentionableUser(participant)) {
        return participant;
      }
    }
    return null;
  }

  Widget _buildMentionPickerPanel() {
    if (!_isMentionPickerVisible) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 320),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PMCard(
            elevated: true,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _mentionSuggestions.length,
              itemBuilder: (context, index) => _buildMentionSuggestionRow(
                _mentionSuggestions[index],
                selected: index == _mentionSelectedIndex,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMentionSuggestionRow(User user, {required bool selected}) {
    final isBot = user.id.startsWith('bot-');
    final label =
        user.displayName.isNotEmpty ? user.displayName : user.username;
    return PMListRow(
      leading: isBot
          ? PMUserAvatar.raw(
              imageUrl: user.avatarUrl == null
                  ? null
                  : ApiConstants.resolveFileUrl(user.avatarUrl!),
              fallbackText: label,
              size: 40,
            )
          : PMUserAvatar(
              user: user,
              status: PMOnlineStatus.fromUserStatus(user.onlineStatus),
              showOnlineDot: true,
            ),
      title: Text(label),
      subtitle:
          Text(isBot ? 'AI Bot · @${user.username}' : '@${user.username}'),
      badge: selected ? 'Enter' : null,
      badgeColor: AppColors.primary,
      trailing: selected
          ? const Icon(Icons.keyboard_return, color: AppColors.primary)
          : null,
      onTap: () => _chooseMentionSuggestion(user),
    );
  }

  Widget _buildInputIconButton({
    required PMSymbol symbol,
    required VoidCallback onPressed,
    required String tooltip,
    bool filled = false,
  }) {
    return Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        gradient: filled ? AppColors.messageGradient : null,
        color: filled ? null : AppColors.pixelBlue,
        borderRadius: BorderRadius.circular(8),
        border: filled ? null : Border.all(color: AppColors.borderLight),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: PMSymbolIcon(
          symbol,
          size: 20,
          color: filled ? Colors.white : AppColors.primary,
        ),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  void _showAttachmentOptions() {
    _showComposerMenu(
      title: '发送附件',
      itemsBuilder: (sheetContext) => [
        if (_cameraCaptureSupported)
          _buildComposerMenuRow(
            symbol: PMSymbol.camera,
            label: '拍照',
            subtitle: '拍摄照片并预览',
            onTap: () {
              final pending = _takePhotoIntoStrip();
              Navigator.pop(sheetContext);
              unawaited(pending);
            },
          ),
        _buildComposerMenuRow(
          symbol: PMSymbol.image,
          label: '相册',
          subtitle: '选择图片，发送前可预览',
          onTap: () {
            // Open the native picker within the user gesture, before dismissing.
            final pending = _pickImagesIntoStrip();
            Navigator.pop(sheetContext);
            unawaited(pending);
          },
        ),
        _buildComposerMenuRow(
          symbol: PMSymbol.files,
          label: '文件',
          subtitle: '按原文件上传',
          onTap: () {
            final pending = _pickAndSendFile();
            Navigator.pop(sheetContext);
            unawaited(pending);
          },
        ),
        _buildComposerMenuRow(
          symbol: PMSymbol.mic,
          label: '语音文件',
          subtitle: '选择已有的音频文件',
          onTap: () {
            final pending = _pickAndSendVoiceFile();
            Navigator.pop(sheetContext);
            unawaited(pending);
          },
        ),
      ],
    );
  }

  void _showMoreComposerTools() {
    _showComposerMenu(
      title: '更多工具',
      itemsBuilder: (sheetContext) => [
        _buildComposerMenuRow(
          symbol: PMSymbol.image,
          label: 'AI 图片',
          subtitle: _e2eeBlocksAi ? _kE2eeAiBlockedReason : '根据描述生成图片',
          onTap: () {
            Navigator.pop(sheetContext);
            // 加密私聊里描述和生成的图都会以明文存在服务器上。
            if (_refuseAiInE2eeChat()) return;
            _showImageGenerationSheet();
          },
        ),
        _buildComposerMenuRow(
          symbol: PMSymbol.location,
          label: '位置',
          subtitle: '发送当前位置',
          onTap: () {
            Navigator.pop(sheetContext);
            unawaited(_sendLocationMessage());
          },
        ),
        _buildComposerMenuRow(
          symbol: PMSymbol.poll,
          label: '投票',
          subtitle: '创建问题和选项',
          onTap: () {
            Navigator.pop(sheetContext);
            _showPollCreateSheet();
          },
        ),
      ],
    );
  }

  Widget _buildComposerMenuRow({
    required PMSymbol symbol,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      PMListRow(
        leading: PMSymbolIcon(symbol, size: 24, color: AppColors.primary),
        title: Text(label),
        subtitle: Text(subtitle),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
        onTap: onTap,
      );

  void _showComposerMenu({
    required String title,
    required List<Widget> Function(BuildContext) itemsBuilder,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PMSpacing.l),
            child: PMCard(
              elevated: false,
              radius: PMRadius.l,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PMDialogHeader(
                      title: title, onClose: () => Navigator.pop(sheetContext)),
                  const SizedBox(height: PMSpacing.m),
                  ...itemsBuilder(sheetContext),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
