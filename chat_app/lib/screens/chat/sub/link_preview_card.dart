part of '../chat_screen.dart';

extension _ChatScreenAttachmentParts on _ChatScreenState {
  Future<void> _openAttachment(Message message) async {
    if (message.hasPreviewImage) {
      await _showImagePreview(message);
      return;
    }
    if (message.isVideoMessage) {
      await _showVideoPreview(message);
      return;
    }
    await _downloadAttachment(message);
  }

  Future<void> _downloadAttachment(
    Message message, {
    DownloadedChatFile? downloaded,
  }) async {
    try {
      final file = downloaded ?? await _chatService.downloadFile(message);
      final saved = await file_save.saveBytesAsFile(
        bytes: file.bytes,
        name: _safeAttachmentFileName(message, file),
        mimeType: file.mimeType ?? message.fileType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? '已保存 ${_safeAttachmentFileName(message, file)}'
                : '已取回 ${file.name} (${_formatFileSize(file.bytes.length)})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('文件下载失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showImagePreview(Message message) async {
    final fileFuture = _chatService.downloadFile(message);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (dialogContext) => _ImagePreviewDialog(
        message: message,
        fileFuture: fileFuture,
        onDownload: (file) => _downloadAttachment(
          message,
          downloaded: file,
        ),
        onForward: (file) async {
          Navigator.of(dialogContext).pop();
          await _forwardAttachment(message, downloaded: file);
        },
      ),
    );
  }

  Future<void> _showVideoPreview(Message message) async {
    final fileFuture = _chatService.downloadFile(message);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (dialogContext) => ChatVideoPreviewDialog(
        message: message,
        fileFuture: fileFuture,
        onDownload: (file) => _downloadAttachment(
          message,
          downloaded: file,
        ),
        onForward: (file) async {
          Navigator.of(dialogContext).pop();
          await _forwardAttachment(message, downloaded: file);
        },
      ),
    );
  }

  Future<void> _forwardAttachment(
    Message message, {
    DownloadedChatFile? downloaded,
  }) async {
    final target = await _selectForwardTarget();
    if (target == null) return;

    try {
      final file = downloaded ?? await _chatService.downloadFile(message);
      final sent = await _chatService.sendFileMessage(
        target.id,
        PickedChatFile(
          name: _safeAttachmentFileName(message, file),
          size: file.bytes.length,
          mimeType: file.mimeType ?? message.fileType,
          bytes: file.bytes,
        ),
        messageType: message.type,
      );
      if (!mounted) return;
      if (target.id == _chat.id) {
        _upsertMessage(sent);
        _scrollToBottom();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已转发到 ${target.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('转发失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<Chat?> _selectForwardTarget() {
    return showDialog<Chat>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('转发到'),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: 420,
          height: 420,
          child: FutureBuilder<List<Chat>>(
            future: _chatService.getChatRooms(includeDetails: false),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        color: AppColors.textSecondary,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '会话列表加载失败',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                );
              }
              final chats = snapshot.data ?? const [];
              if (chats.isEmpty) {
                return const Center(
                  child: Text(
                    '暂无可转发会话',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                itemCount: chats.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      child: Icon(
                        chat.type == ChatType.group
                            ? Icons.groups
                            : Icons.person,
                        color: AppColors.primary,
                      ),
                    ),
                    title: Text(
                      chat.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      chat.id == _chat.id
                          ? '当前会话'
                          : chat.lastMessage?.resolvedFileLabel ?? ' ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(chat),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  String _safeAttachmentFileName(
    Message message,
    DownloadedChatFile file,
  ) {
    final candidates = [
      file.name,
      message.fileName,
      message.content,
      'attachment-${message.id}',
    ];
    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null &&
          value.isNotEmpty &&
          !value.startsWith('[') &&
          !value.contains('/') &&
          !value.contains('\\')) {
        return value;
      }
    }
    return 'attachment-${message.id}';
  }

  bool _isImageFile(PickedChatFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.startsWith('image/')) {
      return true;
    }
    final lowerName = file.name.toLowerCase();
    return lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.webp');
  }

  String _formatFileSize(int size) {
    if (size < 1024) {
      return '$size B';
    }
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _ImagePreviewDialog extends StatelessWidget {
  const _ImagePreviewDialog({
    required this.message,
    required this.fileFuture,
    required this.onDownload,
    required this.onForward,
  });

  final Message message;
  final Future<DownloadedChatFile> fileFuture;
  final Future<void> Function(DownloadedChatFile file) onDownload;
  final Future<void> Function(DownloadedChatFile file) onForward;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: FutureBuilder<DownloadedChatFile>(
          future: fileFuture,
          builder: (context, snapshot) {
            final file = snapshot.data;
            return Stack(
              children: [
                Positioned.fill(
                  child: _buildBody(context, snapshot),
                ),
                Positioned(
                  left: 16,
                  top: 12,
                  right: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          file?.name ??
                              message.fileName ??
                              message.resolvedFileLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      _PreviewIconButton(
                        tooltip: '保存图片',
                        icon: Icons.download,
                        onPressed: file == null
                            ? null
                            : () => unawaited(onDownload(file)),
                      ),
                      const SizedBox(width: 8),
                      _PreviewIconButton(
                        tooltip: '转发图片',
                        iconWidget: const _ForwardPreviewGlyph(),
                        onPressed: file == null
                            ? null
                            : () => unawaited(onForward(file)),
                      ),
                      const SizedBox(width: 8),
                      _PreviewIconButton(
                        tooltip: '关闭',
                        icon: Icons.close,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<DownloadedChatFile> snapshot,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (snapshot.hasError || !snapshot.hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
                size: 52,
              ),
              const SizedBox(height: 14),
              const Text(
                '图片加载失败',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.error?.toString() ?? '无法读取图片文件',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: InteractiveViewer(
        minScale: 0.6,
        maxScale: 5,
        child: Image.memory(
          Uint8List.fromList(snapshot.data!.bytes),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              '图片格式无法预览，请保存后查看',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewIconButton extends StatelessWidget {
  const _PreviewIconButton({
    required this.tooltip,
    this.icon,
    this.iconWidget,
    required this.onPressed,
  }) : assert(icon != null || iconWidget != null);

  final String tooltip;
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: iconWidget ?? Icon(icon!),
        color: Colors.white,
        disabledColor: Colors.white38,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.14),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.07),
        ),
      ),
    );
  }
}

class _ForwardPreviewGlyph extends StatelessWidget {
  const _ForwardPreviewGlyph();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 22),
      painter: _ForwardPreviewGlyphPainter(
        IconTheme.of(context).color ?? Colors.white,
      ),
    );
  }
}

class _ForwardPreviewGlyphPainter extends CustomPainter {
  const _ForwardPreviewGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final y = size.height * 0.54;
    final path = Path()
      ..moveTo(size.width * 0.18, y)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.18,
        size.width * 0.72,
        y,
      )
      ..lineTo(size.width * 0.78, y);
    canvas.drawPath(path, paint);

    final arrow = Path()
      ..moveTo(size.width * 0.62, size.height * 0.34)
      ..lineTo(size.width * 0.82, y)
      ..lineTo(size.width * 0.62, size.height * 0.74);
    canvas.drawPath(arrow, paint);
  }

  @override
  bool shouldRepaint(covariant _ForwardPreviewGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
