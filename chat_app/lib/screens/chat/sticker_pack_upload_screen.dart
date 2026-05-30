import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../services/chat_data_service.dart';
import '../../services/sticker_file_picker.dart'
    if (dart.library.js_interop) '../../services/sticker_file_picker_web.dart';
import '../../services/sticker_file_picker_types.dart';

class StickerPackUploadScreen extends StatefulWidget {
  const StickerPackUploadScreen({
    super.key,
    this.chatService,
    this.filePicker,
  });

  final ChatDataService? chatService;
  final StickerFilePicker? filePicker;

  @override
  State<StickerPackUploadScreen> createState() =>
      _StickerPackUploadScreenState();
}

class _StickerPackUploadScreenState extends State<StickerPackUploadScreen> {
  static const int _maxFiles = 24;
  static const int _maxBytes = 256 * 1024;
  static const List<String> _extensions = ['png', 'webp', 'gif'];

  late final ChatDataService _chatService =
      widget.chatService ?? ChatDataService();
  late final StickerFilePicker _filePicker =
      widget.filePicker ?? pickStickerFilesForCurrentPlatform;
  final TextEditingController _nameController =
      TextEditingController(text: '我的贴纸包');
  final List<PickedChatFile> _stickers = [];
  PickedChatFile? _cover;
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final file = await _pickSingleImage();
    if (file == null) return;
    if (!mounted) return;
    setState(() {
      _cover = file;
      _error = null;
    });
  }

  Future<void> _pickStickers() async {
    final files = await _filePicker(
      allowMultiple: true,
      allowedExtensions: _extensions,
    );
    if (!mounted || files.isEmpty) return;
    final next = <PickedChatFile>[];
    for (final file in files) {
      final picked = _toStickerFile(file);
      if (picked == null) continue;
      next.add(picked);
    }
    setState(() {
      _stickers
        ..addAll(next)
        ..sort((a, b) => a.name.compareTo(b.name));
      if (_stickers.length > _maxFiles) {
        _stickers.removeRange(_maxFiles, _stickers.length);
        _error = '单个贴纸包最多 $_maxFiles 张，已保留前 $_maxFiles 张';
      } else {
        _error = null;
      }
      _cover ??= _stickers.isEmpty ? null : _stickers.first;
    });
  }

  Future<PickedChatFile?> _pickSingleImage() async {
    final result = await _filePicker(
      allowMultiple: false,
      allowedExtensions: _extensions,
    );
    if (result.isEmpty) return null;
    return _toStickerFile(result.first);
  }

  PickedChatFile? _toStickerFile(PickedChatFile file) {
    final lower = file.name.toLowerCase();
    final supported = _extensions.any((ext) => lower.endsWith('.$ext'));
    if (!supported) {
      if (mounted) {
        setState(() => _error = '仅支持 png、webp、gif 贴纸图片');
      }
      return null;
    }
    if (file.size > _maxBytes) {
      if (mounted) {
        setState(() => _error = '单张贴纸不能超过 256KB：${file.name}');
      }
      return null;
    }
    return PickedChatFile(
      name: file.name,
      path: file.path,
      bytes: file.bytes,
      size: file.size,
      mimeType: _mimeType(file.name),
    );
  }

  Future<void> _submit() async {
    if (_stickers.isEmpty) {
      setState(() => _error = '至少选择 1 张贴纸图片');
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await _chatService.uploadStickerPack(
        name: _nameController.text,
        cover: _cover,
        stickers: _stickers,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloud,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(PMSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PMPageHeader(
                    title: '上传贴纸包',
                    subtitle: '最多 24 张 png、webp 或 gif，每张不超过 256KB',
                    leading: const PMSymbolIcon(
                      PMSymbol.sticker,
                      size: 44,
                      color: AppColors.primary,
                    ),
                    actions: [
                      PMButton(
                        label: '返回',
                        variant: PMButtonVariant.secondary,
                        onPressed: _uploading
                            ? null
                            : () => Navigator.maybePop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: PMSpacing.xl),
                  PMCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _nameController,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            labelText: '贴纸包名称',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: PMSpacing.m),
                        Wrap(
                          spacing: PMSpacing.m,
                          runSpacing: PMSpacing.m,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            PMButton(
                              label: _cover == null ? '选择封面' : '更换封面',
                              icon: Icons.image_outlined,
                              variant: PMButtonVariant.secondary,
                              onPressed: _uploading ? null : _pickCover,
                            ),
                            PMButton(
                              label: '添加贴纸图片',
                              icon: Icons.add_photo_alternate_outlined,
                              onPressed: _uploading ? null : _pickStickers,
                            ),
                            PMChip(
                              label: '${_stickers.length}/$_maxFiles 张',
                              selected: _stickers.isNotEmpty,
                            ),
                          ],
                        ),
                        if (_cover != null) ...[
                          const SizedBox(height: PMSpacing.l),
                          _FilePreviewRow(
                            title: '封面',
                            file: _cover!,
                            onRemove: _uploading
                                ? null
                                : () => setState(() => _cover = null),
                          ),
                        ],
                        const SizedBox(height: PMSpacing.l),
                        _StickerGrid(
                          files: _stickers,
                          onRemove: _uploading
                              ? null
                              : (file) {
                                  setState(() {
                                    _stickers.remove(file);
                                    if (_cover == file) {
                                      _cover = _stickers.isEmpty
                                          ? null
                                          : _stickers.first;
                                    }
                                  });
                                },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: PMSpacing.m),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (_uploading) ...[
                          const SizedBox(height: PMSpacing.l),
                          const LinearProgressIndicator(),
                        ],
                        const SizedBox(height: PMSpacing.l),
                        Align(
                          alignment: Alignment.centerRight,
                          child: PMButton(
                            label: '上传贴纸包',
                            loading: _uploading,
                            onPressed: _uploading ? null : _submit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _mimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }
}

class _StickerGrid extends StatelessWidget {
  const _StickerGrid({
    required this.files,
    required this.onRemove,
  });

  final List<PickedChatFile> files;
  final ValueChanged<PickedChatFile>? onRemove;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const PMEmptyState(
        icon: Icons.image_outlined,
        title: '还没有选择贴纸',
        subtitle: '添加 png、webp 或 gif 后即可上传。',
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: PMSpacing.m,
        crossAxisSpacing: PMSpacing.m,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return Stack(
          children: [
            Positioned.fill(
              child: PMCard(
                padding: const EdgeInsets.all(PMSpacing.s),
                child: Column(
                  children: [
                    Expanded(child: _StickerThumb(file: file)),
                    const SizedBox(height: PMSpacing.xs),
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => onRemove!(file),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FilePreviewRow extends StatelessWidget {
  const _FilePreviewRow({
    required this.title,
    required this.file,
    required this.onRemove,
  });

  final String title;
  final PickedChatFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return PMListRow(
      leading: SizedBox.square(
        dimension: 44,
        child: _StickerThumb(file: file),
      ),
      title: Text(title),
      subtitle: Text(file.name),
      trailing: onRemove == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
    );
  }
}

class _StickerThumb extends StatelessWidget {
  const _StickerThumb({required this.file});

  final PickedChatFile file;

  @override
  Widget build(BuildContext context) {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(PMRadius.s),
        child: Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.pixelBlue,
        borderRadius: BorderRadius.circular(PMRadius.s),
      ),
      child: const Center(
        child: PMSymbolIcon(
          PMSymbol.sticker,
          color: AppColors.primary,
          size: 28,
        ),
      ),
    );
  }
}
