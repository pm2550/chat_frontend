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
import '../../widgets/pm_welcome_art.dart';
import '../../widgets/pm_responsive.dart';
import 'api_keys_screen.dart';
import 'bot_edit_screen.dart';

part 'sub/ai_hub_data.dart';
part 'sub/ai_hub_actions.dart';
part 'sub/ai_hub_view.dart';

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
    _AiSection('bots', '助手', '创建、编辑和管理可加入群聊的助手', Icons.smart_toy),
    _AiSection('rooms', '群聊', '把 Bot 接入群聊并设置触发方式', Icons.hub),
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

  static Chat? _resolveImageRoomFrom(List<Chat> rooms) {
    for (final room in rooms) {
      if (room.type == ChatType.private || room.type == ChatType.group) {
        return room;
      }
    }
    return rooms.isEmpty ? null : rooms.first;
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
            padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600
                ? PMSpacing.l
                : PMSpacing.xxl),
            children: [
              PMPageHeader(
                title: 'AI 助手',
                subtitle: '一起想点子，让灵感有个回应',
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.pixelMint,
                    borderRadius: BorderRadius.circular(PMRadius.s),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: AppColors.secondaryDark),
                ),
                actions: [
                  PMButton(
                    label: '创建助手',
                    icon: Icons.add,
                    compact: true,
                    onPressed: _openCreateBot,
                  ),
                  PMButton(
                    label: '连接服务',
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
                  title: '助手加载失败',
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

  void _setViewState(VoidCallback change) {
    if (mounted) setState(change);
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

class _AiSection {
  const _AiSection(this.routeKey, this.label, this.fullLabel, this.icon);

  final String routeKey;
  final String label;
  final String fullLabel;
  final IconData icon;
}
