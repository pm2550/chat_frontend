import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../services/bot_service.dart';
import '../../services/chat_data_service.dart';
import '../../widgets/cost_preview_chip.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import 'api_keys_screen.dart';
import 'bot_edit_screen.dart';

class AiHubPage extends StatefulWidget {
  const AiHubPage({
    super.key,
    this.initialSection = 'bots',
    this.botService,
    this.chatDataService,
    this.onSectionChanged,
  });

  final String initialSection;
  final BotService? botService;
  final ChatDataService? chatDataService;
  final ValueChanged<String>? onSectionChanged;

  static Future<void> warmCache() => _AiHubPageState.warmCache();

  @override
  State<AiHubPage> createState() => _AiHubPageState();
}

class _AiHubSnapshot {
  const _AiHubSnapshot({
    required this.bots,
    required this.rooms,
    required this.selectedImageRoomId,
  });

  final List<BotConfig> bots;
  final List<Chat> rooms;
  final String? selectedImageRoomId;
}

class _AiHubPageState extends State<AiHubPage>
    with AutomaticKeepAliveClientMixin<AiHubPage> {
  static const Duration _snapshotTtl = Duration(minutes: 2);
  static _AiHubSnapshot? _cachedSnapshot;
  static DateTime? _cachedSnapshotAt;

  static Future<void> warmCache() async {
    try {
      final results = await Future.wait([
        BotService().getMyBots(),
        ChatDataService().getChatRooms(includeDetails: false),
      ]);
      final bots = results[0] as List<BotConfig>;
      final rooms = results[1] as List<Chat>;
      _cachedSnapshot = _AiHubSnapshot(
        bots: List<BotConfig>.from(bots),
        rooms: List<Chat>.from(rooms),
        selectedImageRoomId: _resolveImageRoomFrom(rooms)?.id,
      );
      _cachedSnapshotAt = DateTime.now();
    } catch (_) {
      // Best-effort preloading must never block the home shell.
    }
  }

  late final BotService _botService;
  late final ChatDataService _chatDataService;
  late int _selectedIndex;

  bool _loading = true;
  String? _error;
  List<BotConfig> _bots = const [];
  List<Chat> _rooms = const [];
  Chat? _selectedImageRoom;
  final TextEditingController _imagePromptController = TextEditingController();
  bool _imageFastMode = false;
  bool _imageSubmitting = false;
  String? _imageError;
  _ImageGenerationJob? _latestImageJob;
  Timer? _imagePollTimer;

  static const _sections = [
    _AiSection('bots', 'Bots', '创建、编辑和管理可加入群聊的助手', Icons.smart_toy),
    _AiSection('rooms', '群配置', '把 Bot 接入群聊并设置触发方式', Icons.hub),
    _AiSection('images', '画图', '用积分生成图片并发到会话', Icons.auto_awesome),
  ];

  @override
  void initState() {
    super.initState();
    _botService = widget.botService ?? BotService();
    _chatDataService = widget.chatDataService ?? ChatDataService();
    _selectedIndex = _indexForSection(widget.initialSection);
    _restoreSnapshotIfFresh();
    unawaited(_bootstrapData());
  }

  @override
  void didUpdateWidget(covariant AiHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      setState(() {
        _selectedIndex = _indexForSection(widget.initialSection);
      });
    }
  }

  bool get _canUseSnapshot =>
      widget.botService == null && widget.chatDataService == null;

  void _restoreSnapshotIfFresh() {
    if (!_canUseSnapshot) return;
    final snapshot = _cachedSnapshot;
    final snapshotAt = _cachedSnapshotAt;
    if (snapshot == null ||
        snapshotAt == null ||
        DateTime.now().difference(snapshotAt) >= _snapshotTtl) {
      return;
    }
    _bots = List<BotConfig>.from(snapshot.bots);
    _rooms = List<Chat>.from(snapshot.rooms);
    Chat? restoredImageRoom;
    if (snapshot.selectedImageRoomId != null) {
      for (final room in _rooms) {
        if (room.id == snapshot.selectedImageRoomId) {
          restoredImageRoom = room;
          break;
        }
      }
    }
    _selectedImageRoom = restoredImageRoom ?? _resolveSelectedImageRoom(_rooms);
    _loading = false;
  }

  Future<void> _bootstrapData() async {
    if (_canUseSnapshot && _loading) {
      final results = await Future.wait<dynamic>([
        _botService.loadPersistedMyBots(),
        _chatDataService.loadPersistedChatRooms(includeDetails: false),
      ]);
      if (mounted) {
        final cachedBots = results[0] as List<BotConfig>?;
        final cachedRooms = results[1] as List<Chat>?;
        if ((cachedBots?.isNotEmpty ?? false) ||
            (cachedRooms?.isNotEmpty ?? false)) {
          setState(() {
            _bots = cachedBots ?? const [];
            _rooms = cachedRooms ?? const [];
            _selectedImageRoom = _resolveSelectedImageRoom(_rooms);
            _loading = false;
          });
        }
      }
    }
    await _load(showLoading: _loading);
  }

  int _indexForSection(String section) {
    final index = _sections.indexWhere((item) => item.routeKey == section);
    return index < 0 ? 0 : index;
  }

  static Chat? _resolveImageRoomFrom(List<Chat> rooms) {
    for (final room in rooms) {
      if (room.type == ChatType.private || room.type == ChatType.group) {
        return room;
      }
    }
    return rooms.isEmpty ? null : rooms.first;
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && _bots.isEmpty && _rooms.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (showLoading) {
      setState(() {
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _botService.getMyBots(),
        _chatDataService.getChatRooms(includeDetails: false),
      ]);
      if (!mounted) return;
      final bots = results[0] as List<BotConfig>;
      final rooms = results[1] as List<Chat>;
      final selectedImageRoom = _resolveSelectedImageRoom(rooms);
      if (_canUseSnapshot) {
        _cachedSnapshot = _AiHubSnapshot(
          bots: List<BotConfig>.from(bots),
          rooms: List<Chat>.from(rooms),
          selectedImageRoomId: selectedImageRoom?.id,
        );
        _cachedSnapshotAt = DateTime.now();
      }
      setState(() {
        _bots = bots;
        _rooms = rooms;
        _selectedImageRoom = selectedImageRoom;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (!showLoading && (_bots.isNotEmpty || _rooms.isNotEmpty)) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _imagePollTimer?.cancel();
    _imagePromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final content = PMChatPattern(
      dense: true,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(PMSpacing.xl),
            children: [
              PMPageHeader(
                title: 'AI 助手',
                subtitle: '集中管理 Bot 和群聊内 AI 协作配置',
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(PMRadius.s),
                  ),
                  child: const Icon(Icons.smart_toy, color: Colors.white),
                ),
                actions: [
                  PMButton(
                    label: '新建 Bot',
                    icon: Icons.add,
                    compact: true,
                    onPressed: _openCreateBot,
                  ),
                  PMButton(
                    label: 'API 密钥',
                    icon: Icons.vpn_key,
                    compact: true,
                    variant: PMButtonVariant.secondary,
                    onPressed: _openApiKeys,
                  ),
                  PMButton(
                    label: '刷新',
                    icon: Icons.refresh,
                    compact: true,
                    variant: PMButtonVariant.secondary,
                    onPressed: _load,
                  ),
                ],
              ),
              const SizedBox(height: PMSpacing.xl),
              _buildSegmentedNav(),
              const SizedBox(height: PMSpacing.l),
              if (_loading)
                const _AiLoadingGrid()
              else if (_error != null)
                PMErrorState(
                  title: 'AI Hub 加载失败',
                  message: _error!,
                  onRetry: _load,
                )
              else
                IndexedStack(
                  index: _selectedIndex,
                  children: [
                    _buildBotsTab(),
                    _buildRoomsTab(),
                    _buildImagesTab(),
                  ],
                ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(backgroundColor: AppColors.background, body: content);
  }

  Widget _buildSegmentedNav() {
    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.s),
      elevated: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final children = List.generate(_sections.length, (index) {
            final section = _sections[index];
            final selected = _selectedIndex == index;
            final tile = InkWell(
              borderRadius: BorderRadius.circular(PMRadius.s),
              onTap: () => _selectSection(index),
              child: AnimatedContainer(
                duration: PMMotion.fast,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? PMSpacing.m : PMSpacing.l,
                  vertical: PMSpacing.m,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.pixelMint : Colors.transparent,
                  borderRadius: BorderRadius.circular(PMRadius.s),
                  border: Border.all(
                    color: selected ? AppColors.secondary : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    Icon(
                      section.icon,
                      color: selected
                          ? AppColors.secondaryDark
                          : AppColors.textSecondary,
                      size: 19,
                    ),
                    const SizedBox(width: PMSpacing.s),
                    Flexible(
                      child: Text(
                        section.fullLabel,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );

            if (compact) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == _sections.length - 1 ? 0 : PMSpacing.xs,
                ),
                child: tile,
              );
            }
            return Expanded(child: tile);
          });

          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children)
              : Row(children: children);
        },
      ),
    );
  }

  void _selectSection(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    widget.onSectionChanged?.call(_sections[index].routeKey);
  }

  Widget _buildBotsTab() {
    if (_bots.isEmpty) {
      return PMEmptyState(
        icon: Icons.smart_toy_outlined,
        title: '还没有 Bot',
        subtitle: '创建第一个 Bot 后，就可以把它加入群聊，给每个房间配置不同昵称和提示词。',
        action: PMButton(
            label: '新建 Bot', icon: Icons.add, onPressed: _openCreateBot),
      );
    }

    return _ResponsiveGrid(
      children: [
        for (final bot in _bots)
          PMCard(
            interactive: true,
            onTap: () => _openEditBot(bot),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _AiAvatar(
                      icon: Icons.smart_toy,
                      label: bot.botName,
                      avatarUrl: bot.botAvatar,
                      active: bot.isActive,
                    ),
                    const SizedBox(width: PMSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bot.botName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: PMSpacing.xs),
                          Text(
                            '${bot.llmProvider} · ${bot.modelName?.isNotEmpty == true ? bot.modelName : '默认模型'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PMStatusBadge(
                      status: bot.isActive
                          ? PMOnlineStatus.online
                          : PMOnlineStatus.offline,
                      label: bot.isActive ? '可用' : '停用',
                    ),
                  ],
                ),
                const SizedBox(height: PMSpacing.l),
                Text(
                  bot.systemPrompt?.trim().isNotEmpty == true
                      ? bot.systemPrompt!.trim()
                      : '尚未配置系统提示词',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const Spacer(),
                const SizedBox(height: PMSpacing.l),
                Row(
                  children: [
                    _MiniMetric(
                        label: '温度', value: bot.temperature.toStringAsFixed(1)),
                    const SizedBox(width: PMSpacing.s),
                    _MiniMetric(
                        label: 'Tokens', value: bot.maxTokens.toString()),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRoomsTab() {
    if (_rooms.isEmpty) {
      return const PMEmptyState(
        icon: Icons.forum_outlined,
        title: '还没有可配置的房间',
        subtitle: '创建群聊后，可以在这里把 Bot 加入房间并设置触发规则。',
      );
    }

    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.s),
      child: Column(
        children: [
          for (final room in _rooms)
            PMListRow(
              leading: _AiAvatar(
                icon:
                    room.type == ChatType.private ? Icons.person : Icons.groups,
                label: room.name,
                color: room.anonymousEnabled
                    ? const Color(0xFF7C3AED)
                    : AppColors.secondary,
                active: true,
              ),
              title: Text(room.name.isEmpty ? '未命名会话' : room.name),
              subtitle: Text(
                '${room.type.description} · ${room.effectiveMemberCount} 人 · ${room.anonymousEnabled ? '匿名已启用' : '匿名未启用'}',
              ),
              badge: room.anonymousEnabled ? '匿名' : null,
              badgeColor: const Color(0xFF7C3AED),
              trailing: PMButton(
                label: '配置 Bot',
                icon: Icons.tune,
                compact: true,
                variant: PMButtonVariant.secondary,
                onPressed: () => _showRoomBotSheet(room),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagesTab() {
    if (_rooms.isEmpty) {
      return const PMEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: '还没有可发送图片的会话',
        subtitle: '先创建或加入一个会话，再用积分生成图片并发到那里。',
      );
    }

    final selectedRoom = _selectedImageRoom ?? _rooms.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PMCard(
          padding: const EdgeInsets.all(PMSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImageIntro(),
              const SizedBox(height: PMSpacing.l),
              PMListRow(
                leading: _AiAvatar(
                  icon: selectedRoom.type == ChatType.private
                      ? Icons.person
                      : Icons.groups,
                  label: selectedRoom.name,
                  color: AppColors.secondary,
                  active: true,
                ),
                title: Text(
                  selectedRoom.name.isEmpty ? '未命名会话' : selectedRoom.name,
                ),
                subtitle: Text('图片将发送到这个${selectedRoom.type.description}'),
                trailing: PMButton(
                  label: '选择会话',
                  icon: Icons.swap_horiz,
                  compact: true,
                  variant: PMButtonVariant.secondary,
                  onPressed: _pickImageRoom,
                ),
              ),
              const SizedBox(height: PMSpacing.m),
              TextField(
                controller: _imagePromptController,
                minLines: 3,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '描述你想要的图片，例如：一只蓝色玻璃杯放在雨后窗边，柔和自然光',
                  filled: true,
                  fillColor: AppColors.cloud,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: PMSpacing.m),
              PMListRow(
                leading: const _AiAvatar(
                  icon: Icons.speed,
                  label: '快出图',
                  color: AppColors.warning,
                ),
                title: const Text('快出图'),
                subtitle: const Text('关闭 Grok prompt 扩写，直接把原始描述交给画图服务。'),
                trailing: Switch(
                  value: _imageFastMode,
                  onChanged: _imageSubmitting
                      ? null
                      : (value) => setState(() => _imageFastMode = value),
                ),
              ),
              if (_imageError != null) ...[
                const SizedBox(height: PMSpacing.m),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(PMSpacing.m),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    '提交失败：$_imageError',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: PMSpacing.l),
              Wrap(
                spacing: PMSpacing.s,
                runSpacing: PMSpacing.s,
                children: [
                  PMButton(
                    label: _imageSubmitting ? '提交中' : '生成并发送',
                    icon: Icons.auto_awesome,
                    onPressed: _imageSubmitting ? null : _submitImageGeneration,
                  ),
                  PMButton(
                    label: '打开会话',
                    icon: Icons.open_in_new,
                    variant: PMButtonVariant.secondary,
                    onPressed: () => _openRoom(selectedRoom),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_latestImageJob != null) ...[
          const SizedBox(height: PMSpacing.l),
          _buildLatestImageJob(_latestImageJob!),
        ],
      ],
    );
  }

  Widget _buildImageIntro() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        const avatar = _AiAvatar(
          icon: Icons.auto_awesome,
          label: 'AI 画图',
          color: Color(0xFF7C3AED),
          active: true,
        );
        const copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 点数画图',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: PMSpacing.xs),
            Text(
              '生成完成后会作为图片消息发送到选中的会话，失败会自动退回积分。',
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        );
        if (compact) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  SizedBox(width: PMSpacing.m),
                  Expanded(child: copy),
                ],
              ),
              SizedBox(height: PMSpacing.m),
              PMCostPreviewChip(featureKey: 'image_generation'),
            ],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            SizedBox(width: PMSpacing.m),
            Expanded(child: copy),
            PMCostPreviewChip(featureKey: 'image_generation'),
          ],
        );
      },
    );
  }

  Widget _buildLatestImageJob(_ImageGenerationJob job) {
    final status = job.message.isImageGenerationDone
        ? '已完成'
        : job.message.isImageGenerationFailed
            ? '生成失败'
            : '生成中';
    final color = job.message.isImageGenerationDone
        ? AppColors.success
        : job.message.isImageGenerationFailed
            ? AppColors.error
            : AppColors.warning;

    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PMChip(
                label: status,
                icon: job.message.isImageGenerationDone
                    ? Icons.check_circle
                    : job.message.isImageGenerationFailed
                        ? Icons.error_outline
                        : Icons.hourglass_top,
                selected: true,
                color: color,
              ),
              const SizedBox(width: PMSpacing.s),
              Expanded(
                child: Text(
                  job.room.name.isEmpty ? '未命名会话' : job.room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PMButton(
                label: '去会话查看',
                icon: Icons.open_in_new,
                compact: true,
                variant: PMButtonVariant.secondary,
                onPressed: () => _openRoom(job.room),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.m),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: MessageBubble(
                message: job.message,
                isMe: true,
                showAvatar: false,
                onOpenAttachment: (_) async => _openRoom(job.room),
              ),
            ),
          ),
        ],
      ),
    );
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
                          label: room.name,
                          active: room.id == _selectedImageRoom?.id,
                        ),
                        title: Text(room.name.isEmpty ? '未命名会话' : room.name),
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
    setState(() => _selectedImageRoom = selected);
  }

  Future<void> _submitImageGeneration() async {
    final room = _selectedImageRoom ?? _rooms.firstOrNull;
    final prompt = _imagePromptController.text.trim();
    if (room == null || prompt.isEmpty || _imageSubmitting) return;

    setState(() {
      _imageSubmitting = true;
      _imageError = null;
    });
    try {
      final message = await _chatDataService.generateImageMessage(
        room.id,
        prompt: prompt,
        expand: !_imageFastMode,
      );
      if (!mounted) return;
      setState(() {
        _latestImageJob = _ImageGenerationJob(room: room, message: message);
      });
      _startImageJobPolling(room, message.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已提交到 ${room.name.isEmpty ? '会话' : room.name}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _imageError = error.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 画图提交失败: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _imageSubmitting = false);
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
        setState(() {
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
                  '配置 ${room.name} 的 Bot',
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
                    title: '还没有 Bot',
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
        triggerMode: 'MENTION',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selectedBot.botName} 已加入 ${room.name}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bot 配置失败: $error')),
      );
    }
  }
}

class _ImageGenerationJob {
  const _ImageGenerationJob({required this.room, required this.message});

  final Chat room;
  final Message message;
}

class _AiLoadingGrid extends StatelessWidget {
  const _AiLoadingGrid();

  @override
  Widget build(BuildContext context) {
    return _ResponsiveGrid(
      children: List.generate(
        4,
        (_) => PMCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PMSkeleton.text(lines: 1),
              const SizedBox(height: PMSpacing.m),
              PMSkeleton.text(lines: 2),
              const Spacer(),
              PMSkeleton.row(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= PMBreakpoints.wide
        ? 3
        : width >= PMBreakpoints.desktop
            ? 2
            : 1;

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: columns == 1 ? 2.4 : 1.55,
      crossAxisSpacing: PMSpacing.l,
      mainAxisSpacing: PMSpacing.l,
      children: children,
    );
  }
}

class _AiAvatar extends StatelessWidget {
  const _AiAvatar({
    required this.icon,
    required this.label,
    this.avatarUrl,
    this.active = false,
    this.color = AppColors.secondary,
  });

  final IconData icon;
  final String label;
  final String? avatarUrl;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(PMRadius.s),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: avatarUrl?.trim().isNotEmpty == true
              ? Image.network(
                  ApiConstants.resolveFileUrl(avatarUrl!.trim()),
                  fit: BoxFit.cover,
                  width: 48,
                  height: 48,
                  errorBuilder: (_, __, ___) => Icon(icon, color: color),
                )
              : Icon(icon, color: color),
        ),
        if (active)
          Positioned(
            right: -1,
            bottom: -1,
            child: Semantics(
              label: '$label 可用',
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(PMRadius.pill),
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PMSpacing.s,
          vertical: PMSpacing.s,
        ),
        decoration: BoxDecoration(
          color: AppColors.cloud,
          borderRadius: BorderRadius.circular(PMRadius.s),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiSection {
  const _AiSection(this.routeKey, this.label, this.fullLabel, this.icon);

  final String routeKey;
  final String label;
  final String fullLabel;
  final IconData icon;
}
