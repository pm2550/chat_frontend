part of '../chat_screen.dart';

extension _ChatScreenComposerParts on _ChatScreenState {
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    final replyToMessage = _replyingToMessage;
    final replyToId = replyToMessage?.id;
    final sendIdentity = _activeSendIdentity();

    _setViewState(() {
      _messageController.clear();
      _replyingToMessage = null;
      _isTyping = false;
      _mentionStartIndex = null;
      _mentionSuggestions = const [];
      _mentionSelectedIndex = 0;
    });

    try {
      await _webSocketService.connect();
      final roomId = int.tryParse(_chat.id);
      if (replyToId == null &&
          roomId != null &&
          _webSocketService.sendTextMessage(
            roomId,
            content,
            isAnonymous: sendIdentity != null,
          )) {
        _afterOutgoingMessage();
        return;
      }

      final sent = await _chatService.sendTextMessage(
        _chat.id,
        content,
        isAnonymous: sendIdentity != null,
        replyToId: replyToId,
      );
      _afterOutgoingMessage();
      _upsertMessage(
        replyToMessage != null && sent.replyToMessage == null
            ? sent.copyWith(
                replyToId: replyToId,
                replyToMessage: replyToMessage,
                replyToMessageId: replyToId,
              )
            : sent,
      );
      _scrollToBottom();
    } catch (e) {
      final currentUser = _authService.currentUser;
      _upsertMessage(Message(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        content: content,
        senderId: currentUser?.id ?? '',
        senderName:
            sendIdentity?.anonymousName ?? currentUser?.displayName ?? '我',
        senderAvatar: sendIdentity?.anonymousAvatar ?? currentUser?.avatarUrl,
        chatRoomId: _chat.id,
        type: MessageType.text,
        status: MessageStatus.failed,
        timestamp: DateTime.now(),
        replyToId: replyToId,
        replyToMessage: replyToMessage,
        replyToMessageId: replyToId,
        isAnonymous: sendIdentity != null,
        anonymousName: sendIdentity?.anonymousName,
        anonymousAvatar: sendIdentity?.anonymousAvatar,
      ));
      _scrollToBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _insertMessageNewline() {
    final value = _messageController.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final nextText = text.replaceRange(start, end, '\n');
    final nextOffset = start + 1;
    _messageController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    if (!_isTyping && nextText.isNotEmpty) {
      _setViewState(() => _isTyping = true);
    }
  }

  Future<void> _sendPickedFile(
    PickedChatFile file, {
    MessageType? messageType,
  }) async {
    _setViewState(() {
      _isSendingAttachment = true;
    });

    try {
      final sent = await _chatService.sendFileMessage(
        _chat.id,
        file,
        messageType: messageType,
      );
      _upsertMessage(sent);
      _scrollToBottom();
    } catch (e) {
      final currentUser = _authService.currentUser;
      _upsertMessage(Message(
        id: 'local-file-${DateTime.now().microsecondsSinceEpoch}',
        content: file.name,
        senderId: currentUser?.id ?? '',
        senderName: currentUser?.displayName ?? '我',
        senderAvatar: currentUser?.avatarUrl,
        chatRoomId: _chat.id,
        type: messageType ??
            (_isImageFile(file) ? MessageType.image : MessageType.file),
        status: MessageStatus.failed,
        timestamp: DateTime.now(),
        fileName: file.name,
        fileSize: file.size,
        fileType: file.mimeType,
      ));
      _scrollToBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('文件发送失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        _setViewState(() {
          _isSendingAttachment = false;
        });
      }
    }
  }

  Future<PickedChatFile?> _pickImageFromGallery() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    return PickedChatFile(
      name: image.name,
      path: image.path,
      size: await image.length(),
      mimeType: image.mimeType,
      bytes: kIsWeb ? await image.readAsBytes() : null,
    );
  }

  Future<PickedChatFile?> _pickImageFromCamera() async {
    final image = await ImagePicker().pickImage(source: ImageSource.camera);
    if (image == null) return null;
    return PickedChatFile(
      name: image.name,
      path: image.path,
      size: await image.length(),
      mimeType: image.mimeType,
      bytes: kIsWeb ? await image.readAsBytes() : null,
    );
  }

  Future<PickedChatFile?> _pickGenericFile() async {
    if (kIsWeb) {
      return pickGenericFileForCurrentPlatform();
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    return PickedChatFile(
      name: file.name,
      path: file.path,
      size: file.size,
      bytes: file.bytes,
    );
  }

  Future<void> _pickAndSendImage() async {
    final picker = widget.imagePicker ?? _pickImageFromGallery;
    final file = await picker();
    if (file != null) {
      await _sendPickedFile(file);
    }
  }

  Future<void> _pickAndSendFile() async {
    final picker = widget.filePicker ?? _pickGenericFile;
    final file = await picker();
    if (file != null) {
      await _sendPickedFile(file);
    }
  }

  Future<void> _pickAndSendCameraImage() async {
    final file = await _pickImageFromCamera();
    if (file != null) {
      await _sendPickedFile(file, messageType: MessageType.image);
    }
  }

  Future<void> _pickAndSendVoiceFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.audio,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    await _sendPickedFile(
      PickedChatFile(
        name: file.name,
        path: file.path,
        size: file.size,
        bytes: file.bytes,
      ),
      messageType: MessageType.voice,
    );
  }

  Future<void> _sendLocationMessage() async {
    final controller = TextEditingController();
    final location = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送位置'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '位置名称或地图链接',
            hintText: '例如：公司会议室 / https://maps...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (location == null || location.isEmpty) return;

    try {
      final sent = await _chatService.sendTypedMessage(
        _chat.id,
        location,
        type: MessageType.location,
        isAnonymous: _shouldSendAnonymous(),
      );
      _afterOutgoingMessage();
      _upsertMessage(sent);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('位置发送失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildDesktopInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
        boxShadow: [AppColors.appBarShadow],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildReplyPreviewStrip(),
          _buildMentionPickerPanel(),
          Row(
            children: [
              _buildInputIconButton(
                symbol: PMSymbol.emoji,
                onPressed: _showEmojiPanel,
                tooltip: '表情',
              ),
              _buildInputIconButton(
                symbol: PMSymbol.sticker,
                onPressed: _showStickerPanel,
                tooltip: '贴纸',
              ),
              _buildInputIconButton(
                symbol: PMSymbol.terminal,
                onPressed: _showSlashCommandPanel,
                tooltip: 'Agent 命令',
              ),
              _buildInputIconButton(
                symbol: PMSymbol.add,
                onPressed: _showInputOptions,
                tooltip: '附件',
              ),
              AnonymousToggleButton(
                chatRoomId: int.tryParse(_chat.id) ?? 0,
                anonymousEnabled: _chat.anonymousEnabled,
                perMessageMode: _anonymousPerMessageMode,
                nextMessageAnonymous: _anonymousNextMessage,
                onPerMessageModeChanged: _setAnonymousMode,
                onAnonymousChanged: (identity) {
                  _applyAnonymousIdentity(identity);
                },
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cloud,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: _buildMessageTextField(
                    hintText: '输入消息，Enter 发送，Shift+Enter 换行',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _isTyping
                  ? _buildInputIconButton(
                      symbol: PMSymbol.send,
                      onPressed: _sendMessage,
                      tooltip: '发送',
                      filled: true,
                    )
                  : _buildInputIconButton(
                      symbol: PMSymbol.mic,
                      onPressed: _pickAndSendVoiceFile,
                      tooltip: '语音消息',
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTextField({required String hintText}) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveMentionSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveMentionSelection(-1),
        const SingleActivator(LogicalKeyboardKey.escape):
            _clearMentionSuggestions,
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_isMentionPickerVisible) {
            _chooseMentionSuggestion();
          } else {
            _sendMessage();
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter, shift: true):
            _insertMessageNewline,
      },
      child: TextField(
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
      ),
    );
  }

  bool get _isMentionPickerVisible =>
      _mentionStartIndex != null && _mentionSuggestions.isNotEmpty;

  void _handleComposerChanged(String text) {
    final selection = _messageController.selection.baseOffset;
    _setViewState(() => _isTyping = text.isNotEmpty);
    _updateMentionSuggestions(text, selection);
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
    final candidates = _chat.participants
        .where((user) {
          final display = user.displayName.toLowerCase();
          final username = user.username.toLowerCase();
          return normalized.isEmpty ||
              display.startsWith(normalized) ||
              username.startsWith(normalized);
        })
        .take(5)
        .toList(growable: false);

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
    final label =
        user.displayName.isNotEmpty ? user.displayName : user.username;
    final value = _messageController.value;
    final nextText = value.text.replaceRange(start, selection, '@$label ');
    final nextOffset = start + label.length + 2;
    _messageController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    _clearMentionSuggestions();
    _setViewState(() => _isTyping = nextText.trim().isNotEmpty);
  }

  void _clearMentionSuggestions() {
    if (_mentionStartIndex == null && _mentionSuggestions.isEmpty) return;
    _setViewState(() {
      _mentionStartIndex = null;
      _mentionSuggestions = const [];
      _mentionSelectedIndex = 0;
    });
  }

  Widget _buildMentionPickerPanel() {
    if (!_isMentionPickerVisible) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PMCard(
            elevated: true,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < _mentionSuggestions.length; index++)
                  _buildMentionSuggestionRow(
                    _mentionSuggestions[index],
                    selected: index == _mentionSelectedIndex,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMentionSuggestionRow(User user, {required bool selected}) {
    final label =
        user.displayName.isNotEmpty ? user.displayName : user.username;
    return PMListRow(
      leading: PMUserAvatar(
        user: user,
        status: PMOnlineStatus.fromUserStatus(user.onlineStatus),
        showOnlineDot: true,
      ),
      title: Text(label),
      subtitle: Text('@${user.username}'),
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
    return Tooltip(
      message: tooltip,
      child: Container(
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
          icon: PMSymbolIcon(
            symbol,
            size: 20,
            color: filled ? Colors.white : AppColors.primary,
          ),
          onPressed: onPressed,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  void _showInputOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.78,
                    children: [
                      _buildInputOption(
                        symbol: PMSymbol.emoji,
                        label: '表情',
                        onTap: () {
                          Navigator.pop(context);
                          _showEmojiPanel();
                        },
                      ),
                      _buildInputOption(
                        symbol: PMSymbol.sticker,
                        label: '贴纸',
                        onTap: () {
                          Navigator.pop(context);
                          _showStickerPanel();
                        },
                      ),
                      _buildInputOption(
                        symbol: PMSymbol.terminal,
                        label: 'Agent 命令',
                        onTap: () {
                          Navigator.pop(context);
                          _showSlashCommandPanel();
                        },
                      ),
                      _buildInputOption(
                        symbol: PMSymbol.camera,
                        label: '拍照',
                        onTap: () {
                          final sendFuture = _pickAndSendCameraImage();
                          Navigator.pop(context);
                          unawaited(sendFuture);
                        },
                      ),
                      _buildInputOption(
                        symbol: PMSymbol.image,
                        label: '相册',
                        onTap: () {
                          final sendFuture = _pickAndSendImage();
                          Navigator.pop(context);
                          unawaited(sendFuture);
                        },
                      ),
                      _buildInputOption(
                        symbol: PMSymbol.files,
                        label: '文件',
                        onTap: () {
                          final sendFuture = _pickAndSendFile();
                          Navigator.pop(context);
                          unawaited(sendFuture);
                        },
                      ),
                      _buildInputOption(
                        symbol: PMSymbol.location,
                        label: '位置',
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_sendLocationMessage());
                        },
                      ),
                      _buildInputOption(
                        symbol: PMSymbol.poll,
                        label: '投票',
                        onTap: () {
                          Navigator.pop(context);
                          _showPollCreateSheet();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEmojiPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: PMCard(
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: 360,
            child: EmojiPicker(
              textEditingController: _messageController,
              onEmojiSelected: (_, __) {
                _setViewState(() =>
                    _isTyping = _messageController.text.trim().isNotEmpty);
                _focusNode.requestFocus();
              },
              onBackspacePressed: () {
                final text = _messageController.text;
                if (text.isEmpty) return;
                final next = text.characters.skipLast(1).toString();
                _messageController.value = TextEditingValue(
                  text: next,
                  selection: TextSelection.collapsed(offset: next.length),
                );
              },
              config: Config(
                height: 336,
                locale: const Locale('zh'),
                checkPlatformCompatibility: true,
                emojiViewConfig: EmojiViewConfig(
                  emojiSizeMax: 28 *
                      (defaultTargetPlatform == TargetPlatform.iOS ? 1.2 : 1.0),
                ),
                viewOrderConfig: const ViewOrderConfig(
                  top: EmojiPickerItem.categoryBar,
                  middle: EmojiPickerItem.emojiView,
                  bottom: EmojiPickerItem.searchBar,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showStickerPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FutureBuilder<List<StickerPack>>(
        future: _chatService.getStickerPacks(),
        builder: (context, packsSnapshot) {
          final packs = packsSnapshot.data ?? const <StickerPack>[];
          final pack = packs.isEmpty ? null : packs.first;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: PMCard(
              child: SizedBox(
                height: 360,
                child: pack == null
                    ? const Center(child: Text('暂无贴纸包'))
                    : FutureBuilder<List<StickerItem>>(
                        future: _chatService.getStickers(pack.id),
                        builder: (context, stickersSnapshot) {
                          final stickers =
                              stickersSnapshot.data ?? const <StickerItem>[];
                          if (stickersSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      pack.name,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  PMButton(
                                    label: '上传',
                                    compact: true,
                                    variant: PMButtonVariant.secondary,
                                    onPressed: () async {
                                      final uploaded =
                                          await Navigator.of(context)
                                              .push<bool>(MaterialPageRoute(
                                        builder: (_) => StickerPackUploadScreen(
                                          chatService: _chatService,
                                        ),
                                      ));
                                      if (!mounted ||
                                          !context.mounted ||
                                          uploaded != true) {
                                        return;
                                      }
                                      Navigator.of(context).pop();
                                      _showStickerPanel();
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                child: GridView.count(
                                  crossAxisCount: 4,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  children: [
                                    for (final sticker in stickers)
                                      _buildStickerTile(sticker),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStickerTile(StickerItem sticker) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.pop(context);
        unawaited(_sendSticker(sticker));
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.pixelBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Center(
          child: sticker.url == null
              ? Text(
                  sticker.keyword ?? '😀',
                  style: const TextStyle(fontSize: 34),
                )
              : Image.network(
                  ApiConstants.resolveFileUrl(sticker.url!),
                  fit: BoxFit.contain,
                ),
        ),
      ),
    );
  }

  Future<void> _sendSticker(StickerItem sticker) async {
    try {
      final sent = await _chatService.sendStickerMessage(
        _chat.id,
        sticker.id,
        isAnonymous: _shouldSendAnonymous(),
      );
      _afterOutgoingMessage();
      _upsertMessage(sent);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('贴纸发送失败: $e')),
      );
    }
  }

  void _showPollCreateSheet() {
    final questionController = TextEditingController();
    final optionControllers = [
      TextEditingController(),
      TextEditingController(),
    ];
    bool multiSelect = false;
    bool anonymous = false;
    Duration? expiresIn = const Duration(hours: 6);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          void addOption() {
            if (optionControllers.length >= 10) return;
            setModalState(() => optionControllers.add(TextEditingController()));
          }

          void removeOption(int index) {
            if (optionControllers.length <= 2) return;
            final controller = optionControllers.removeAt(index);
            controller.dispose();
            setModalState(() {});
          }

          Widget expiryChip(String label, Duration? value) {
            final selected = expiresIn == value;
            return PMChip(
              label: label,
              selected: selected,
              onTap: () => setModalState(() => expiresIn = value),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              top: 16,
            ),
            child: PMCard(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.86,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '发起投票',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: questionController,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          labelText: '投票问题',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (var index = 0;
                          index < optionControllers.length;
                          index++) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: optionControllers[index],
                                maxLength: 80,
                                decoration: InputDecoration(
                                  labelText: '选项 ${index + 1}',
                                  border: const OutlineInputBorder(),
                                  counterText: '',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: optionControllers.length <= 2
                                  ? null
                                  : () => removeOption(index),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PMButton(
                          label: '添加选项',
                          icon: Icons.add,
                          compact: true,
                          variant: PMButtonVariant.secondary,
                          onPressed:
                              optionControllers.length >= 10 ? null : addOption,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          PMChip(
                            label: '单选',
                            selected: !multiSelect,
                            onTap: () =>
                                setModalState(() => multiSelect = false),
                          ),
                          PMChip(
                            label: '多选',
                            selected: multiSelect,
                            onTap: () =>
                                setModalState(() => multiSelect = true),
                          ),
                          PMChip(
                            label: '实名详情',
                            selected: !anonymous,
                            onTap: () => setModalState(() => anonymous = false),
                          ),
                          PMChip(
                            label: '匿名详情',
                            selected: anonymous,
                            onTap: () => setModalState(() => anonymous = true),
                          ),
                        ],
                      ),
                      if (anonymous) ...[
                        const SizedBox(height: 8),
                        const Text(
                          '开启后只能看到票数，不能查看具体谁投了谁。',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          expiryChip('1 小时', const Duration(hours: 1)),
                          expiryChip('6 小时', const Duration(hours: 6)),
                          expiryChip('1 天', const Duration(days: 1)),
                          expiryChip('3 天', const Duration(days: 3)),
                          expiryChip('永不结束', null),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            final question = questionController.text.trim();
                            final options = optionControllers
                                .map((controller) => controller.text.trim())
                                .where((value) => value.isNotEmpty)
                                .toList();
                            Navigator.pop(context);
                            unawaited(_createPoll(
                              question,
                              options,
                              multiSelect: multiSelect,
                              anonymous: anonymous,
                              expiresAt: expiresIn == null
                                  ? null
                                  : DateTime.now().add(expiresIn!),
                            ));
                          },
                          child: const Text('创建投票'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      questionController.dispose();
      for (final controller in optionControllers) {
        controller.dispose();
      }
    });
  }

  Future<void> _createPoll(
    String question,
    List<String> options, {
    bool multiSelect = false,
    bool anonymous = false,
    DateTime? expiresAt,
  }) async {
    if (question.isEmpty || options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('投票至少需要问题和两个选项')),
      );
      return;
    }
    try {
      final poll = await _chatService.createPoll(
        _chat.id,
        question: question,
        options: options,
        multiSelect: multiSelect,
        anonymous: anonymous,
        expiresAt: expiresAt,
      );
      _upsertMessage(Message(
        id: poll.messageId.toString(),
        content: '[投票] ${poll.question}',
        senderId: _authService.currentUser?.id ?? '',
        senderName: _authService.currentUser?.displayName ??
            _authService.currentUser?.username ??
            '我',
        chatRoomId: _chat.id,
        type: MessageType.poll,
        status: MessageStatus.sent,
        timestamp: DateTime.now(),
        pollId: poll.id,
      ));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('投票创建失败: $e')),
      );
    }
  }

  Widget _buildInputOption({
    required PMSymbol symbol,
    required String label,
    required VoidCallback onTap,
  }) {
    final isBusy = _isSendingAttachment && (label == '相册' || label == '文件');
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: isBusy
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : PMSymbolIcon(
                        symbol,
                        color: AppColors.primary,
                        size: 28,
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
