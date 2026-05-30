import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../services/anonymous_service.dart';
import '../../widgets/pm_brand.dart';

class AnonymousThemePickerScreen extends StatefulWidget {
  const AnonymousThemePickerScreen({
    super.key,
    required this.roomId,
    required this.canEdit,
    this.currentThemeKey,
    this.anonymousService,
  });

  final int roomId;
  final bool canEdit;
  final String? currentThemeKey;
  final AnonymousService? anonymousService;

  @override
  State<AnonymousThemePickerScreen> createState() =>
      _AnonymousThemePickerScreenState();
}

class _AnonymousThemePickerScreenState
    extends State<AnonymousThemePickerScreen> {
  late final AnonymousService _anonymousService;
  List<AnonymousThemeInfo> _themes = const [];
  String? _selectedThemeKey;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _anonymousService = widget.anonymousService ?? AnonymousService();
    _selectedThemeKey = widget.currentThemeKey;
    _loadThemes();
  }

  Future<void> _loadThemes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final themes = await _anonymousService.listThemes(widget.roomId);
      if (!mounted) return;
      setState(() {
        _themes = themes;
        _selectedThemeKey ??= themes.isEmpty ? null : themes.first.themeKey;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _selectTheme(AnonymousThemeInfo theme) async {
    if (!widget.canEdit || _isSaving) return;
    setState(() {
      _selectedThemeKey = theme.themeKey;
      _isSaving = true;
    });
    final updated = await _anonymousService.updateTheme(
      widget.roomId,
      theme.themeKey,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('匿名主题切换失败'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PMChatPattern(
        dense: true,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PMSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PMPageHeader(
                  title: '选择匿名主题',
                  subtitle: widget.canEdit
                      ? '主题会影响本群匿名名称、颜色和 persona 风格'
                      : '只有群主或管理员可以切换匿名主题',
                  leading: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(PMRadius.l),
                    ),
                    child: const Icon(Icons.masks, color: Color(0xFF7C3AED)),
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
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return GridView.builder(
        itemCount: 6,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 360,
          mainAxisSpacing: PMSpacing.l,
          crossAxisSpacing: PMSpacing.l,
          childAspectRatio: 1.25,
        ),
        itemBuilder: (_, __) => PMSkeleton.card(height: 180),
      );
    }
    if (_error != null) {
      return PMErrorState(
        title: '匿名主题加载失败',
        message: _error!,
        onRetry: _loadThemes,
      );
    }
    if (_themes.isEmpty) {
      return const PMEmptyState(
        icon: Icons.masks_outlined,
        title: '暂无匿名主题',
        subtitle: '后端还没有返回可用主题。',
      );
    }
    return GridView.builder(
      itemCount: _themes.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisSpacing: PMSpacing.l,
        crossAxisSpacing: PMSpacing.l,
        childAspectRatio: 1.22,
      ),
      itemBuilder: (context, index) {
        final theme = _themes[index];
        final selected = _selectedThemeKey == theme.themeKey;
        final accent =
            _parseColor(theme.accentColor) ?? const Color(0xFF7C3AED);
        return PMCard(
          interactive: widget.canEdit,
          onTap: widget.canEdit ? () => _selectTheme(theme) : null,
          background:
              selected ? accent.withValues(alpha: 0.08) : AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14 + i * 0.04),
                        borderRadius: BorderRadius.circular(PMRadius.pill),
                      ),
                      child: Icon(Icons.masks, size: 17, color: accent),
                    ),
                  const Spacer(),
                  if (selected)
                    Icon(
                      _isSaving ? Icons.sync : Icons.check_circle,
                      color: accent,
                    ),
                ],
              ),
              const SizedBox(height: PMSpacing.l),
              Text(
                theme.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: PMSpacing.xs),
              Text(
                theme.description ?? '匿名 persona 主题',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const Spacer(),
              PMChip(
                label: _sampleName(theme),
                icon: Icons.badge_outlined,
                selected: true,
                color: accent,
              ),
            ],
          ),
        );
      },
    );
  }

  String _sampleName(AnonymousThemeInfo theme) {
    final prefix = theme.personaPrefix;
    if (prefix == null || prefix.isEmpty) return '匿名-042';
    return '$prefix-042';
  }

  Color? _parseColor(String? value) {
    if (value == null || !value.startsWith('#')) return null;
    final hex = value.substring(1);
    final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
