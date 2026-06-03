import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/chat.dart';
import '../../services/bot_service.dart';
import '../../services/chat_data_service.dart';
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
  });

  final String initialSection;
  final BotService? botService;
  final ChatDataService? chatDataService;

  @override
  State<AiHubPage> createState() => _AiHubPageState();
}

class _AiHubPageState extends State<AiHubPage> {
  late final BotService _botService;
  late final ChatDataService _chatDataService;
  late int _selectedIndex;

  bool _loading = true;
  String? _error;
  List<BotConfig> _bots = const [];
  List<Chat> _rooms = const [];

  static const _sections = [
    _AiSection('bots', 'Bots', '创建、编辑和管理可加入群聊的助手', Icons.smart_toy),
    _AiSection('rooms', '群配置', '把 Bot 接入群聊并设置触发方式', Icons.hub),
  ];

  @override
  void initState() {
    super.initState();
    _botService = widget.botService ?? BotService();
    _chatDataService = widget.chatDataService ?? ChatDataService();
    _selectedIndex = _indexForSection(widget.initialSection);
    _load();
  }

  @override
  void didUpdateWidget(covariant AiHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _selectedIndex = _indexForSection(widget.initialSection);
    }
  }

  int _indexForSection(String section) {
    final index = _sections.indexWhere((item) => item.routeKey == section);
    return index < 0 ? 0 : index;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _botService.getMyBots(),
        _chatDataService.getChatRooms(includeDetails: false),
      ]);
      if (!mounted) return;
      final bots = results[0] as List<BotConfig>;
      final rooms = results[1] as List<Chat>;
      setState(() {
        _bots = bots;
        _rooms = rooms;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(PMRadius.s),
                onTap: () => _selectSection(index),
                child: AnimatedContainer(
                  duration: PMMotion.fast,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? PMSpacing.s : PMSpacing.l,
                    vertical: PMSpacing.m,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.pixelMint : Colors.transparent,
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    border: Border.all(
                      color:
                          selected ? AppColors.secondary : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                          compact ? section.label : section.fullLabel,
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
              ),
            );
          });

          return Row(children: children);
        },
      ),
    );
  }

  void _selectSection(int index) {
    setState(() => _selectedIndex = index);
    Navigator.of(context).pushNamed('/home/ai/${_sections[index].routeKey}');
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
                '${room.type.description} · ${room.participants.length} 人 · ${room.anonymousEnabled ? '匿名已启用' : '匿名未启用'}',
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
    this.active = false,
    this.color = AppColors.secondary,
  });

  final IconData icon;
  final String label;
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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(PMRadius.s),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Icon(icon, color: color),
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
