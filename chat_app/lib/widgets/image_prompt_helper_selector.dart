import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../design/tokens.dart';
import '../services/image_prompt_helper.dart';

/// 选 AI 画图的提示词扩写档位（关闭 / 仅翻译 / 创意扩写），选择记在本机。
///
/// 默认是三段选择 + 一行说明；[compact] 是一个"扩写：创意扩写 ▾"小按钮，点开菜单选，
/// 给 /画图 输入框上方那一行提示用（320px 宽的手机也放得下）。
class ImagePromptHelperSelector extends StatefulWidget {
  const ImagePromptHelperSelector({
    super.key,
    this.compact = false,
    this.enabled = true,
  });

  final bool compact;
  final bool enabled;

  @override
  State<ImagePromptHelperSelector> createState() =>
      _ImagePromptHelperSelectorState();
}

class _ImagePromptHelperSelectorState extends State<ImagePromptHelperSelector> {
  @override
  void initState() {
    super.initState();
    ImagePromptHelperPreference.load();
  }

  void _choose(ImagePromptHelper level) {
    ImagePromptHelperPreference.set(level);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ImagePromptHelper>(
      valueListenable: ImagePromptHelperPreference.current,
      builder: (context, level, _) =>
          widget.compact ? _buildCompact(level) : _buildFull(level),
    );
  }

  Widget _buildCompact(ImagePromptHelper level) {
    final color = widget.enabled ? AppColors.primary : AppColors.textTertiary;
    return PopupMenuButton<ImagePromptHelper>(
      key: const ValueKey('image-prompt-helper-compact'),
      tooltip: '画图扩写方式',
      enabled: widget.enabled,
      initialValue: level,
      onSelected: _choose,
      itemBuilder: (context) => [
        for (final option in ImagePromptHelper.values)
          PopupMenuItem<ImagePromptHelper>(
            key: ValueKey('image-prompt-helper-menu-${option.apiValue}'),
            value: option,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: option == level
                        ? const Icon(Icons.check,
                            size: 16, color: AppColors.primary)
                        : null,
                  ),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          option.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.only(left: 8, right: 2, top: 3, bottom: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PMRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '扩写：${level.label}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildFull(ImagePromptHelper level) {
    return Column(
      key: const ValueKey('image-prompt-helper-selector'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '提示词扩写',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 36,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppColors.cloud,
            borderRadius: BorderRadius.circular(PMRadius.s),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              for (final option in ImagePromptHelper.values)
                Expanded(child: _buildSegment(option, option == level)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          level.description,
          key: const ValueKey('image-prompt-helper-description'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildSegment(ImagePromptHelper option, bool selected) {
    final foreground = !widget.enabled
        ? AppColors.textTertiary
        : selected
            ? AppColors.primary
            : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('image-prompt-helper-${option.apiValue}'),
        borderRadius: BorderRadius.circular(PMRadius.s - 2),
        onTap: widget.enabled ? () => _choose(option) : null,
        child: AnimatedContainer(
          duration: PMMotion.fast,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(PMRadius.s - 2),
            border: selected
                ? Border.all(color: AppColors.primary.withValues(alpha: 0.35))
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              option.label,
              maxLines: 1,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
