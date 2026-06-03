import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../services/bot_service.dart';
import '../../services/chat_data_service.dart';
import '../../widgets/pm_brand.dart';

class ChatRoomBotConfigScreen extends StatefulWidget {
  const ChatRoomBotConfigScreen({
    super.key,
    required this.roomId,
    required this.bot,
    this.botService,
    this.chatService,
    this.isOwner = false,
  });

  final int roomId;
  final BotConfig bot;
  final BotService? botService;

  /// Used for the owner-only moderation-grant call (separate endpoint from the bot config).
  final ChatDataService? chatService;

  /// Whether the current viewer is the room OWNER. Gates the moderation-grant chips
  /// (server is authoritative and returns 403 for non-owners regardless).
  final bool isOwner;

  @override
  State<ChatRoomBotConfigScreen> createState() =>
      _ChatRoomBotConfigScreenState();
}

class _ChatRoomBotConfigScreenState extends State<ChatRoomBotConfigScreen> {
  late final BotService _botService;
  late final ChatDataService _chatService;
  late final TextEditingController _keywordsController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _promptSuffixController;

  String _triggerMode = 'MENTION';
  String _moderationGrant = 'NONE';
  bool _enabledInRoom = true;
  bool _isSaving = false;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    _botService = widget.botService ?? BotService();
    _chatService = widget.chatService ?? ChatDataService();
    _triggerMode = (widget.bot.triggerMode ?? 'MENTION').toUpperCase();
    _moderationGrant = (widget.bot.moderationGrant ?? 'NONE').toUpperCase();
    _enabledInRoom = widget.bot.enabledInRoom;
    _keywordsController =
        TextEditingController(text: widget.bot.triggerKeywords ?? '');
    _nicknameController =
        TextEditingController(text: widget.bot.roomNickname ?? '');
    _promptSuffixController =
        TextEditingController(text: widget.bot.roomPromptSuffix ?? '');
  }

  @override
  void dispose() {
    _keywordsController.dispose();
    _nicknameController.dispose();
    _promptSuffixController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final botId = widget.bot.id;
    if (botId == null) return;
    setState(() => _isSaving = true);
    try {
      await _botService.updateRoomBotConfig(
        widget.roomId,
        botId,
        triggerMode: _triggerMode,
        keywords: _keywordsController.text.trim(),
        roomNickname: _nicknameController.text.trim(),
        roomPromptSuffix: _promptSuffixController.text.trim(),
        enabledInRoom: _enabledInRoom,
      );
      // F5: the moderation grant is a separate, owner-only endpoint. Only push it
      // when the viewer is the owner and the value actually changed.
      if (widget.isOwner &&
          _moderationGrant !=
              (widget.bot.moderationGrant ?? 'NONE').toUpperCase()) {
        await _chatService.setChatRoomBotModerationGrant(
          chatRoomId: widget.roomId.toString(),
          botId: botId,
          grant: _moderationGrant,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _remove() async {
    final botId = widget.bot.id;
    if (botId == null) return;
    setState(() => _isRemoving = true);
    try {
      await _botService.removeBotFromRoom(widget.roomId, botId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isRemoving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('移除失败: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PMChatPattern(
        dense: true,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.all(PMSpacing.xl),
                children: [
                  PMPageHeader(
                    title: '群内 Bot 配置',
                    subtitle: widget.bot.botName,
                    leading: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(PMRadius.l),
                      ),
                      child: const Icon(
                        Icons.smart_toy_outlined,
                        color: AppColors.secondaryDark,
                      ),
                    ),
                    actions: [
                      PMButton(
                        label: '返回',
                        icon: Icons.arrow_back,
                        compact: true,
                        variant: PMButtonVariant.secondary,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: PMSpacing.xl),
                  PMSectionCard(
                    title: '触发方式',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(PMSpacing.m),
                        child: Wrap(
                          spacing: PMSpacing.s,
                          runSpacing: PMSpacing.s,
                          children: [
                            for (final mode in const [
                              'MENTION',
                              'KEYWORD',
                              'ALL'
                            ])
                              PMChip(
                                label: _modeLabel(mode),
                                icon: mode == 'MENTION'
                                    ? Icons.alternate_email
                                    : mode == 'KEYWORD'
                                        ? Icons.key
                                        : Icons.all_inclusive,
                                selected: _triggerMode == mode,
                                color: AppColors.secondaryDark,
                                onTap: () =>
                                    setState(() => _triggerMode = mode),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_triggerMode == 'KEYWORD') ...[
                    const SizedBox(height: PMSpacing.l),
                    PMSectionCard(
                      title: '关键词',
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(PMSpacing.m),
                          child: TextField(
                            controller: _keywordsController,
                            decoration: const InputDecoration(
                              labelText: '关键词',
                              hintText: '用逗号分隔，例如：总结, 帮我, PM',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: PMSpacing.l),
                  PMSectionCard(
                    title: '群内身份',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(PMSpacing.m),
                        child: TextField(
                          controller: _nicknameController,
                          decoration: const InputDecoration(
                            labelText: '群内别名',
                            hintText: '为空时使用全局 Bot 名称',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PMSpacing.l),
                  PMSectionCard(
                    title: '群内 Prompt 追加',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(PMSpacing.m),
                        child: TextField(
                          controller: _promptSuffixController,
                          minLines: 5,
                          maxLines: 10,
                          decoration: const InputDecoration(
                            labelText: '只在这个群生效的附加指令',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PMSpacing.l),
                  PMSectionCard(
                    title: '启用状态',
                    children: [
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: PMSpacing.m),
                        title: const Text('在此群启用'),
                        subtitle: const Text('关闭后，该 Bot 不会响应本群消息。'),
                        value: _enabledInRoom,
                        onChanged: (value) =>
                            setState(() => _enabledInRoom = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: PMSpacing.l),
                  PMSectionCard(
                    title: '管理权限 (群主可设)',
                    subtitle: widget.isOwner
                        ? 'AI 可代为禁言/移出成员的最高权限。KICK 含 MUTE。'
                        : '仅群主可修改。',
                    children: [
                      Opacity(
                        opacity: widget.isOwner ? 1.0 : 0.5,
                        child: Padding(
                          padding: const EdgeInsets.all(PMSpacing.m),
                          child: Wrap(
                            spacing: PMSpacing.s,
                            runSpacing: PMSpacing.s,
                            children: [
                              for (final grant in const ['NONE', 'MUTE', 'KICK'])
                                PMChip(
                                  label: _grantLabel(grant),
                                  icon: grant == 'NONE'
                                      ? Icons.block
                                      : grant == 'MUTE'
                                          ? Icons.volume_off
                                          : Icons.person_remove,
                                  selected: _moderationGrant == grant,
                                  color: AppColors.error,
                                  onTap: widget.isOwner
                                      ? () => setState(
                                          () => _moderationGrant = grant)
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: PMSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: PMButton(
                          label: '保存配置',
                          icon: Icons.save_outlined,
                          loading: _isSaving,
                          onPressed: _save,
                        ),
                      ),
                      const SizedBox(width: PMSpacing.m),
                      PMButton(
                        label: '从群中移除',
                        icon: Icons.delete_outline,
                        loading: _isRemoving,
                        variant: PMButtonVariant.danger,
                        onPressed: _remove,
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

  String _modeLabel(String mode) {
    return switch (mode) {
      'KEYWORD' => '关键词',
      'ALL' => '全部消息',
      _ => '提及',
    };
  }

  String _grantLabel(String grant) {
    return switch (grant) {
      'MUTE' => '可禁言',
      'KICK' => '可移出',
      _ => '无',
    };
  }
}
