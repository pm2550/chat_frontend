import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/chat_customization.dart';
import '../../services/user_profile_service.dart';
import '../../widgets/pm_brand.dart';

class ChatPreferencesScreen extends StatefulWidget {
  const ChatPreferencesScreen({
    super.key,
    this.initialSettings,
    this.profileService,
  });

  final UserAppSettings? initialSettings;
  final UserProfileService? profileService;

  @override
  State<ChatPreferencesScreen> createState() => _ChatPreferencesScreenState();
}

class _ChatPreferencesScreenState extends State<ChatPreferencesScreen> {
  static const _solidBackgrounds = [
    ('solid:#EAF4FF', '雾蓝'),
    ('solid:#E7FFF8', '薄荷'),
    ('solid:#FFF7ED', '米杏'),
    ('solid:#F3E8FF', '淡紫'),
    ('solid:#F8FAFC', '纸白'),
    ('solid:#111827', '夜色'),
  ];

  late final UserProfileService _profileService;
  UserAppSettings _settings = const UserAppSettings();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? UserProfileService();
    _settings = widget.initialSettings ?? const UserAppSettings();
    _load();
  }

  Future<void> _load() async {
    if (widget.initialSettings != null) {
      setState(() => _loading = false);
    }
    try {
      final settings = await _profileService.getSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _save(UserAppSettings next) async {
    final previous = _settings;
    setState(() {
      _settings = next;
      _saving = true;
    });
    try {
      final saved = await _profileService.updateSettings(next);
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _settings = previous;
        _saving = false;
      });
      _showSnack('保存失败: $error', isError: true);
    }
  }

  Future<void> _pickAndUploadBackground() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.size > 2 * 1024 * 1024) {
      _showSnack('背景图片不能超过 2MB', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await _profileService.uploadChatBackground(
        PickedChatBackground(
          name: file.name,
          path: file.path,
          size: file.size,
          bytes: file.bytes,
        ),
      );
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _saving = false;
      });
      _showSnack('聊天背景已上传');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('上传失败: $error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天偏好'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: PMSpacing.l),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: PMChatPattern(
        dense: true,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: PMErrorState(message: _error!, onRetry: _load),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(PMSpacing.xl),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PMPageHeader(
                              title: '聊天偏好',
                              subtitle: '背景、头像框和自己发送的消息气泡',
                              leading: Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  gradient: AppColors.messageGradient,
                                  borderRadius:
                                      BorderRadius.circular(PMRadius.l),
                                ),
                                child: const Icon(
                                  Icons.palette_outlined,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: PMSpacing.l),
                            _buildBackgroundSection(),
                            const SizedBox(height: PMSpacing.l),
                            _buildAvatarFrameSection(),
                            const SizedBox(height: PMSpacing.l),
                            _buildBubbleSection(),
                            const SizedBox(height: 48),
                          ],
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildBackgroundSection() {
    final customUrl = _settings.chatBackgroundCustomUrl;
    return PMSectionCard(
      title: '聊天背景',
      subtitle: '上传背景会优先于预设；聊天区始终叠加 30% 白色蒙版保证可读性',
      trailing: Wrap(
        spacing: PMSpacing.s,
        children: [
          PMButton(
            label: '上传',
            icon: Icons.upload,
            compact: true,
            variant: PMButtonVariant.secondary,
            onPressed: _saving ? null : _pickAndUploadBackground,
          ),
          if (customUrl?.isNotEmpty == true)
            PMButton(
              label: '使用预设',
              icon: Icons.layers_clear,
              compact: true,
              variant: PMButtonVariant.secondary,
              onPressed: _saving
                  ? null
                  : () => _save(_settings.copyWith(
                        chatBackgroundCustomUrl: '',
                      )),
            ),
        ],
      ),
      children: [
        if (customUrl?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PMSpacing.l,
              PMSpacing.m,
              PMSpacing.l,
              0,
            ),
            child: SizedBox(
              height: 116,
              child: PMBackgroundPreview(
                preset: _settings.chatBackgroundPreset,
                customUrl: customUrl,
                selected: true,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(PMSpacing.l),
          child: _OptionGrid(
            minTileWidth: 168,
            itemCount: ChatCustomizationCatalog.backgrounds.length,
            itemBuilder: (context, index) {
              final option = ChatCustomizationCatalog.backgrounds[index];
              final selected = option.id == _settings.chatBackgroundPreset &&
                  (customUrl == null || customUrl.isEmpty);
              return _PresetTile(
                label: option.label,
                description: option.description,
                selected: selected,
                preview: PMBackgroundPreview(
                  preset: option.id,
                  selected: selected,
                ),
                onTap: _saving
                    ? null
                    : () => _save(_settings.copyWith(
                          chatBackgroundPreset: option.id,
                          chatBackgroundCustomUrl: '',
                        )),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PMSpacing.l,
            0,
            PMSpacing.l,
            PMSpacing.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '纯色',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: PMSpacing.s),
              Wrap(
                spacing: PMSpacing.s,
                runSpacing: PMSpacing.s,
                children: [
                  for (final option in _solidBackgrounds)
                    _SolidBackgroundChip(
                      preset: option.$1,
                      label: option.$2,
                      selected: _settings.chatBackgroundPreset == option.$1 &&
                          (customUrl == null || customUrl.isEmpty),
                      onTap: _saving
                          ? null
                          : () => _save(_settings.copyWith(
                                chatBackgroundPreset: option.$1,
                                chatBackgroundCustomUrl: '',
                              )),
                    ),
                  PMButton(
                    label: '自定义色',
                    icon: Icons.color_lens_outlined,
                    compact: true,
                    variant: PMButtonVariant.secondary,
                    onPressed: _saving ? null : _showCustomSolidColorSheet,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarFrameSection() {
    return PMSectionCard(
      title: '头像框',
      subtitle: '应用到你在成员列表和消息头像中的展示；匿名消息不会使用头像框',
      children: [
        Padding(
          padding: const EdgeInsets.all(PMSpacing.l),
          child: _OptionGrid(
            minTileWidth: 148,
            itemCount: ChatCustomizationCatalog.avatarFrames.length,
            itemBuilder: (context, index) {
              final option = ChatCustomizationCatalog.avatarFrames[index];
              final selected = option.id == _settings.avatarFramePreset;
              return _PresetTile(
                label: option.label,
                description: option.description,
                selected: selected,
                preview: PMAvatarFramePreview(
                  preset: option.id,
                  selected: selected,
                ),
                onTap: _saving
                    ? null
                    : () => _save(
                          _settings.copyWith(avatarFramePreset: option.id),
                        ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBubbleSection() {
    return PMSectionCard(
      title: '气泡样式',
      subtitle: '只影响你发送的普通消息；别人的消息和匿名消息保持统一默认样式',
      children: [
        Padding(
          padding: const EdgeInsets.all(PMSpacing.l),
          child: _OptionGrid(
            minTileWidth: 160,
            itemCount: ChatCustomizationCatalog.bubbleStyles.length,
            itemBuilder: (context, index) {
              final option = ChatCustomizationCatalog.bubbleStyles[index];
              final selected = option.id == _settings.bubbleStylePreset;
              return _PresetTile(
                label: option.label,
                description: option.description,
                selected: selected,
                preview: PMBubbleStylePreview(
                  preset: option.id,
                  selected: selected,
                ),
                onTap: _saving
                    ? null
                    : () => _save(
                          _settings.copyWith(bubbleStylePreset: option.id),
                        ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  Future<void> _showCustomSolidColorSheet() async {
    final current = _settings.chatBackgroundPreset.startsWith('solid:#')
        ? _settings.chatBackgroundPreset.substring('solid:#'.length)
        : 'EAF4FF';
    final controller = TextEditingController(text: current);
    String? errorText;

    final preset = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            String normalizedHex() {
              final raw = controller.text.trim().replaceFirst('#', '');
              return raw.toUpperCase();
            }

            void submit() {
              final hex = normalizedHex();
              if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(hex)) {
                setSheetState(() => errorText = '请输入 6 位十六进制颜色，例如 EAF4FF');
                return;
              }
              Navigator.of(context).pop('solid:#$hex');
            }

            return Padding(
              padding: EdgeInsets.only(
                left: PMSpacing.l,
                right: PMSpacing.l,
                bottom: MediaQuery.of(context).viewInsets.bottom + PMSpacing.l,
              ),
              child: PMCard(
                padding: const EdgeInsets.all(PMSpacing.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PMDialogHeader(
                      title: '自定义纯色背景',
                      subtitle: '保存为 solid:#RRGGBB，可在聊天区叠加可读性蒙版',
                    ),
                    const SizedBox(height: PMSpacing.m),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 7,
                      decoration: InputDecoration(
                        labelText: '颜色',
                        prefixText: '#',
                        hintText: 'EAF4FF',
                        errorText: errorText,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => submit(),
                      onChanged: (_) {
                        if (errorText != null) {
                          setSheetState(() => errorText = null);
                        }
                      },
                    ),
                    const SizedBox(height: PMSpacing.s),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        PMButton(
                          label: '取消',
                          variant: PMButtonVariant.secondary,
                          compact: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: PMSpacing.s),
                        PMButton(
                          label: '应用',
                          icon: Icons.check,
                          compact: true,
                          onPressed: submit,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();
    if (preset == null) return;
    await _save(_settings.copyWith(
      chatBackgroundPreset: preset,
      chatBackgroundCustomUrl: '',
    ));
  }
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    required this.itemCount,
    required this.itemBuilder,
    required this.minTileWidth,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: minTileWidth + 40,
        mainAxisExtent: 194,
        crossAxisSpacing: PMSpacing.m,
        mainAxisSpacing: PMSpacing.m,
      ),
      itemBuilder: itemBuilder,
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.label,
    required this.description,
    required this.preview,
    required this.selected,
    this.onTap,
  });

  final String label;
  final String description;
  final Widget preview;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.s),
      elevated: selected,
      interactive: onTap != null,
      onTap: onTap,
      background: selected ? AppColors.pixelBlue : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: preview),
          const SizedBox(height: PMSpacing.s),
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selected)
                const PMChip(
                  label: '已选',
                  selected: true,
                  color: AppColors.primary,
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _SolidBackgroundChip extends StatelessWidget {
  const _SolidBackgroundChip({
    required this.preset,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String preset;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(
      'FF${preset.substring('solid:#'.length)}',
      radix: 16,
    ));
    final dark = color.computeLuminance() < 0.35;
    return Tooltip(
      message: label,
      child: PMCard(
        padding: const EdgeInsets.symmetric(
          horizontal: PMSpacing.m,
          vertical: PMSpacing.s,
        ),
        elevated: selected,
        interactive: onTap != null,
        onTap: onTap,
        background: selected ? AppColors.pixelBlue : Colors.white,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(PMRadius.s),
                border: Border.all(
                  color: dark ? AppColors.border : AppColors.borderLight,
                ),
              ),
            ),
            const SizedBox(width: PMSpacing.s),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: PMSpacing.s),
              const PMChip(
                label: '已选',
                selected: true,
                color: AppColors.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
