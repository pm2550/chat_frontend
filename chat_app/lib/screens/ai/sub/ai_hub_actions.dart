part of '../ai_hub_page.dart';

extension _AiHubActions1Parts on _AiHubPageState {
  Future<void> _joinRoomWithBot(BotConfig bot) async {
    if (bot.id == null) return;
    final groups = _rooms.where((room) => room.type == ChatType.group).toList();
    final room = await showModalBottomSheet<Chat>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.all(PMSpacing.xl),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PMDialogHeader(title: '把 ${bot.botName} 加入群聊'),
              const SizedBox(height: PMSpacing.l),
              if (groups.isEmpty)
                PMEmptyState(
                    icon: Icons.forum_outlined,
                    title: '先创建一个群聊',
                    subtitle: '创建群聊后，就能邀请助手一起聊天。',
                    action: PMButton(
                        label: '前往联系人',
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(context).pushNamed('/home/contacts');
                        }))
              else
                ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .55),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: groups.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, index) => PMListRow(
                        leading: const Icon(Icons.forum_outlined,
                            color: AppColors.secondaryDark),
                        title: Text(groups[index].name),
                        subtitle: const Text('加入后打开聊天'),
                        onTap: () =>
                            Navigator.of(sheetContext).pop(groups[index]),
                      ),
                    )),
            ]),
      )),
    );
    if (room == null || !mounted) return;
    try {
      await _botService.addBotToRoom(int.parse(room.id), bot.id!);
      if (!mounted) return;
      _openRoom(room);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('未能加入群聊：$error')));
    }
  }

  bool get _canUseSnapshot =>
      widget.botService == null && widget.chatDataService == null;

  int _indexForSection(String section) {
    final index = _AiHubPageState._sections
        .indexWhere((item) => item.routeKey == section);
    return index < 0 ? 0 : index;
  }

  void _selectSection(int index) {
    if (index == _selectedIndex) return;
    _setViewState(() => _selectedIndex = index);
    widget.onSectionChanged?.call(_AiHubPageState._sections[index].routeKey);
  }

  Chat? _resolveSelectedImageRoom(List<Chat> rooms) {
    if (rooms.isEmpty) return null;
    final current = _selectedImageRoom;
    if (current == null) return rooms.first;
    for (final room in rooms) {
      if (room.id == current.id) return room;
    }
    return rooms.first;
  }

  Future<void> _pickImageRoom() async {
    final selected = await showModalBottomSheet<Chat>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PMSpacing.l,
            PMSpacing.s,
            PMSpacing.l,
            PMSpacing.l,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择接收图片的会话',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: PMSpacing.m),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final room in _rooms)
                      PMListRow(
                        leading: _AiAvatar(
                          icon: room.type == ChatType.private
                              ? Icons.person
                              : Icons.groups,
                          label: _aiRoomTitle(room),
                          active: room.id == _selectedImageRoom?.id,
                        ),
                        title: Text(_aiRoomTitle(room)),
                        subtitle: Text(
                          '${room.type.description} · ${room.effectiveMemberCount} 人',
                        ),
                        badge: room.id == _selectedImageRoom?.id ? '当前' : null,
                        onTap: () => Navigator.pop(context, room),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _setViewState(() => _selectedImageRoom = selected);
  }

  Future<void> _submitImageGeneration() async {
    final room = _selectedImageRoom ?? _rooms.firstOrNull;
    final prompt = _imagePromptController.text.trim();
    if (room == null || prompt.isEmpty || _imageSubmitting) return;

    _setViewState(() {
      _imageSubmitting = true;
      _imageError = null;
    });
    try {
      final message = await _chatDataService.generateImageMessage(
        room.id,
        prompt: prompt,
        promptHelper: ImagePromptHelperPreference.current.value,
      );
      if (!mounted) return;
      _setViewState(() {
        _latestImageJob = _ImageGenerationJob(room: room, message: message);
      });
      _startImageJobPolling(room, message.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已提交到 ${_aiRoomTitle(room, empty: '会话')}')),
      );
    } catch (error) {
      if (!mounted) return;
      _setViewState(() => _imageError = error.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 画图提交失败: $error')),
      );
    } finally {
      if (mounted) {
        _setViewState(() => _imageSubmitting = false);
      }
    }
  }

  void _startImageJobPolling(Chat room, String messageId) {
    _imagePollTimer?.cancel();
    var attempts = 0;

    Future<void> refresh() async {
      attempts += 1;
      try {
        final messages = await _chatDataService.getRecentMessages(
          room.id,
          limit: 30,
        );
        final message = messages
            .where((item) => item.id == messageId)
            .cast<Message?>()
            .firstWhere((item) => item != null, orElse: () => null);
        if (!mounted || message == null) return;
        _setViewState(() {
          _latestImageJob = _ImageGenerationJob(room: room, message: message);
        });
        if (message.isImageGenerationDone ||
            message.isImageGenerationFailed ||
            attempts >= 80) {
          _imagePollTimer?.cancel();
        }
      } catch (_) {
        if (attempts >= 3) {
          _imagePollTimer?.cancel();
        }
      }
    }

    unawaited(refresh());
    _imagePollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refresh()),
    );
  }

  void _openRoom(Chat room) {
    Navigator.of(context).pushNamed('/chat/${room.id}', arguments: room);
  }

  Future<void> _openApiKeys() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ApiKeysScreen(botService: _botService),
      ),
    );
  }

  Future<void> _openCreateBot() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BotEditScreen(botService: _botService),
      ),
    );
    if (created == true) {
      await _load();
    }
  }

  Future<void> _openEditBot(BotConfig bot) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BotEditScreen(bot: bot, botService: _botService),
      ),
    );
    if (changed == true) {
      await _load();
    }
  }

  Future<void> _showRoomBotSheet(Chat room) async {
    final selectedBot = await showModalBottomSheet<BotConfig>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              PMSpacing.l,
              PMSpacing.s,
              PMSpacing.l,
              PMSpacing.l,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '配置 ${_aiRoomTitle(room)} 的 Bot',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: PMSpacing.m),
                if (_bots.isEmpty)
                  const PMEmptyState(
                    icon: Icons.smart_toy_outlined,
                    title: '你的第一位 AI 伙伴',
                    subtitle: '先创建 Bot，再把它加入群聊。',
                    variant: EmptyStateVariant.muted,
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final bot in _bots)
                          PMListRow(
                            leading: _AiAvatar(
                              icon: Icons.smart_toy,
                              label: bot.botName,
                              avatarUrl: bot.botAvatar,
                              active: bot.isActive,
                            ),
                            title: Text(bot.botName),
                            subtitle: Text(bot.modelName ?? bot.llmProvider),
                            onTap: () => Navigator.pop(context, bot),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedBot?.id == null) return;
    try {
      await _botService.addBotToRoom(
        int.parse(room.id),
        selectedBot!.id!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selectedBot.botName} 已加入 ${_aiRoomTitle(room)}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bot 配置失败: $error')),
      );
    }
  }
}
