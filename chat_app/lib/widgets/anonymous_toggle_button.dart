import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../design/design.dart';
import '../services/anonymous_service.dart';

class AnonymousToggleButton extends StatefulWidget {
  const AnonymousToggleButton({
    super.key,
    required this.chatRoomId,
    required this.anonymousEnabled,
    required this.onAnonymousChanged,
    this.perMessageMode = false,
    this.nextMessageAnonymous = false,
    this.onPerMessageModeChanged,
    this.compact = false,
  });

  final int chatRoomId;
  final bool anonymousEnabled;
  final ValueChanged<AnonymousIdentity?> onAnonymousChanged;
  final bool perMessageMode;
  final bool nextMessageAnonymous;
  final ValueChanged<bool>? onPerMessageModeChanged;
  final bool compact;

  @override
  State<AnonymousToggleButton> createState() => _AnonymousToggleButtonState();
}

class _AnonymousToggleButtonState extends State<AnonymousToggleButton> {
  static const _anonymousColor = Color(0xFF7C3AED);

  final AnonymousService _anonymousService = AnonymousService();
  AnonymousIdentity? _currentIdentity;
  bool _isLoading = false;

  bool get _isAnonymous => _currentIdentity != null;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.anonymousEnabled && widget.chatRoomId > 0;
    final label = enabled
        ? _isAnonymous
            ? '匿名 · ${_currentIdentity!.anonymousName}'
            : '实名'
        : '实名';
    final color = _isAnonymous ? _anonymousColor : AppColors.primary;

    if (widget.compact) {
      return Tooltip(
        message: enabled ? label : '群管理员未开启匿名',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(PMRadius.m),
            onTap: enabled && !_isLoading ? _toggleAnonymous : null,
            onLongPress: enabled && _isAnonymous ? _showPersonaSheet : null,
            child: AnimatedContainer(
              duration: PMMotion.fast,
              curve: PMMotion.curveStandard,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: enabled
                    ? color.withValues(alpha: _isAnonymous ? 0.13 : 0.09)
                    : AppColors.cloud,
                borderRadius: BorderRadius.circular(PMRadius.m),
                border: Border.all(
                  color: enabled
                      ? color.withValues(alpha: 0.35)
                      : AppColors.borderLight,
                ),
              ),
              child: Center(
                child: _isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(
                        _isAnonymous
                            ? Icons.masks
                            : Icons.account_circle_outlined,
                        color: enabled ? color : AppColors.textTertiary,
                        size: 19,
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: enabled ? '切换匿名身份' : '群管理员未开启匿名',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(PMRadius.pill),
          onTap: enabled && !_isLoading ? _toggleAnonymous : null,
          onLongPress: enabled && _isAnonymous ? _showPersonaSheet : null,
          child: AnimatedContainer(
            duration: PMMotion.fast,
            curve: PMMotion.curveStandard,
            constraints: const BoxConstraints(maxWidth: 168),
            padding: const EdgeInsets.symmetric(
              horizontal: PMSpacing.m,
              vertical: PMSpacing.s,
            ),
            decoration: BoxDecoration(
              color: enabled
                  ? color.withValues(alpha: _isAnonymous ? 0.13 : 0.09)
                  : AppColors.cloud,
              borderRadius: BorderRadius.circular(PMRadius.pill),
              border: Border.all(
                color: enabled
                    ? color.withValues(alpha: 0.35)
                    : AppColors.borderLight,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else
                  Icon(
                    _isAnonymous ? Icons.masks : Icons.account_circle_outlined,
                    color: enabled ? color : AppColors.textTertiary,
                    size: 17,
                  ),
                const SizedBox(width: PMSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? color : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.swap_horiz,
                    color: color.withValues(alpha: 0.78),
                    size: 15,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleAnonymous() async {
    if (_isAnonymous) {
      setState(() => _currentIdentity = null);
      widget.onAnonymousChanged(null);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final identity =
          await _anonymousService.enterAnonymousMode(widget.chatRoomId);
      if (!mounted) return;
      setState(() => _currentIdentity = identity);
      widget.onAnonymousChanged(identity);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _rerollPersona() async {
    setState(() => _isLoading = true);
    try {
      final identity =
          await _anonymousService.rerollAnonymous(widget.chatRoomId);
      if (!mounted) return;
      setState(() => _currentIdentity = identity);
      widget.onAnonymousChanged(identity);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showPersonaSheet() {
    final identity = _currentIdentity;
    if (identity == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PMSpacing.l),
          child: PMCard(
            radius: PMRadius.xl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PMDialogHeader(
                  title: '匿名身份',
                  subtitle: identity.theme?.displayName == null
                      ? '当前匿名 persona'
                      : '主题：${identity.theme!.displayName}',
                ),
                const SizedBox(height: PMSpacing.l),
                CircleAvatar(
                  radius: 34,
                  backgroundColor:
                      _parseColor(identity.anonymousAvatar) ?? _anonymousColor,
                  child: Text(
                    identity.anonymousName.isEmpty
                        ? '?'
                        : identity.anonymousName.substring(0, 1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: PMSpacing.s),
                Text(
                  identity.anonymousName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: PMSpacing.l),
                Wrap(
                  spacing: PMSpacing.s,
                  runSpacing: PMSpacing.s,
                  children: [
                    PMChip(
                      label: '持续匿名',
                      selected: !widget.perMessageMode,
                      color: _anonymousColor,
                      onTap: () {
                        widget.onPerMessageModeChanged?.call(false);
                        Navigator.of(context).pop();
                      },
                    ),
                    PMChip(
                      label:
                          widget.nextMessageAnonymous ? '逐条选择 · 下条匿名' : '逐条选择',
                      selected: widget.perMessageMode,
                      color: _anonymousColor,
                      onTap: () {
                        widget.onPerMessageModeChanged?.call(true);
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: PMSpacing.s),
                Text(
                  identity.theme?.displayName == null
                      ? '匿名主题由群主设置'
                      : '主题：${identity.theme!.displayName} · 由群主设置',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: PMSpacing.l),
                PMButton(
                  label: '换一个 persona',
                  icon: Icons.casino_outlined,
                  onPressed: () {
                    Navigator.of(context).pop();
                    _rerollPersona();
                  },
                ),
                const SizedBox(height: PMSpacing.s),
                PMButton(
                  label: '自定义名字',
                  icon: Icons.edit_outlined,
                  variant: PMButtonVariant.secondary,
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showRenameDialog();
                  },
                ),
                const SizedBox(height: PMSpacing.s),
                PMButton(
                  label: '退出匿名',
                  icon: Icons.logout,
                  variant: PMButtonVariant.danger,
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() => _currentIdentity = null);
                    widget.onAnonymousChanged(null);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PMSpacing.l),
            child: PMCard(
              radius: PMRadius.xl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PMDialogHeader(
                    title: '修改匿名昵称',
                    subtitle: '每天只能改名一次，长度 2-20 字。',
                  ),
                  const SizedBox(height: PMSpacing.l),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      hintText: '输入新昵称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: PMSpacing.m),
                  PMButton(
                    label: '保存',
                    icon: Icons.check,
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.length < 2) return;
                      final result = await _anonymousService.renameAnonymous(
                        widget.chatRoomId,
                        text,
                      );
                      if (!mounted || !context.mounted) return;
                      if (result != null) {
                        setState(() => _currentIdentity = result);
                        widget.onAnonymousChanged(result);
                      }
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color? _parseColor(String? value) {
    if (value == null || !value.startsWith('#')) return null;
    final hex = value.substring(1);
    final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
