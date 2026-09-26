part of '../chat_screen.dart';

extension _ChatComposer3Parts on _ChatScreenState {
  void _showImageGenerationSheet() {
    final promptController =
        TextEditingController(text: _messageController.text);
    var submitting = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
          top: 16,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              final prompt = promptController.text.trim();
              if (prompt.isEmpty || submitting) return;
              setModalState(() => submitting = true);
              Navigator.pop(sheetContext);
              await _generateImageMessage(prompt);
            }

            return PMCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI 图片生成',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '本次 10 积分。生成完成后会作为图片消息发到当前会话。',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: promptController,
                    minLines: 3,
                    maxLines: 6,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '描述你想生成的图片',
                      filled: true,
                      fillColor: AppColors.cloud,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PMButton(
                        label: '取消',
                        variant: PMButtonVariant.secondary,
                        onPressed: submitting
                            ? null
                            : () => Navigator.pop(sheetContext),
                      ),
                      const SizedBox(width: 10),
                      PMButton(
                        label: '生成',
                        loading: submitting,
                        onPressed: submitting ? null : () => submit(),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(promptController.dispose);
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
    return StickerTile(
      sticker: sticker,
      onTap: () {
        Navigator.pop(context);
        unawaited(_sendSticker(sticker));
      },
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
}
