import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'tokens.dart';

class PMKeywordEditor extends StatefulWidget {
  const PMKeywordEditor({
    super.key,
    required this.controller,
    this.fieldKey,
    this.label = '添加触发词',
    this.hintText = '输入一个词，按 Enter 添加',
    this.helperText = '消息包含任一词条时触发；可粘贴逗号或换行分隔的多个词。',
  });

  final TextEditingController controller;
  final Key? fieldKey;
  final String label;
  final String hintText;
  final String helperText;

  @override
  State<PMKeywordEditor> createState() => _PMKeywordEditorState();
}

class _PMKeywordEditorState extends State<PMKeywordEditor> {
  final TextEditingController _inputController = TextEditingController();

  List<String> get _keywords {
    final seen = <String>{};
    return widget.controller.text
        .split(RegExp(r'[,，\n\r]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _addKeywords([String? raw]) {
    final additions = (raw ?? _inputController.text)
        .split(RegExp(r'[,，\n\r]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    final combined = <String>[..._keywords];
    for (final keyword in additions) {
      if (!combined.contains(keyword)) {
        combined.add(keyword);
      }
    }
    widget.controller.text = combined.join(',');
    _inputController.clear();
    setState(() {});
  }

  void _removeKeyword(String keyword) {
    widget.controller.text =
        _keywords.where((item) => item != keyword).join(',');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keywords = _keywords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (keywords.isNotEmpty) ...[
          Wrap(
            spacing: PMSpacing.s,
            runSpacing: PMSpacing.s,
            children: [
              for (final keyword in keywords)
                Container(
                  key: ValueKey('trigger-keyword-$keyword'),
                  padding: const EdgeInsets.only(
                    left: PMSpacing.m,
                    right: PMSpacing.xs,
                    top: PMSpacing.xs,
                    bottom: PMSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(PMRadius.pill),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        keyword,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        key: ValueKey('remove-trigger-keyword-$keyword'),
                        tooltip: '删除 $keyword',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                            width: 28, height: 28),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, size: 16),
                        color: AppColors.textSecondary,
                        onPressed: () => _removeKeyword(keyword),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: PMSpacing.m),
        ],
        TextField(
          key: widget.fieldKey,
          controller: _inputController,
          textInputAction: TextInputAction.done,
          onSubmitted: _addKeywords,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
            helperText: widget.helperText,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              key: const Key('add-trigger-keyword'),
              tooltip: '添加触发词',
              icon: const Icon(Icons.add),
              onPressed: _addKeywords,
            ),
          ),
        ),
      ],
    );
  }
}
