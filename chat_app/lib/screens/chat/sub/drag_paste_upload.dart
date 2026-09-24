part of '../chat_screen.dart';

extension _ChatScreenDragPasteUploadParts on _ChatScreenState {
  void _attachDropPasteHandlers() {
    if (_dropPasteController != null) return;
    _dropPasteController = attachChatDropPasteHandlers(
      onDragEntered: _showDragUploadOverlay,
      onDragExited: _hideDragUploadOverlay,
      onFilesDropped: _queueDroppedFiles,
      // 粘贴的图片先排进发送栏，由用户按发送键决定什么时候发出。
      onPasteImage: (file) async => _queuePendingAttachment(
        _PendingAttachment.file(file, messageType: MessageType.image),
      ),
      onPasteImageUrl: _queuePastedImageUrl,
    );
  }

  /// 粘贴网页图片时剪贴板里只有第三方地址，浏览器读不到跨域字节，
  /// 先让服务端代取回来，好在发送栏里显示真实缩略图；取不到就先占位排队。
  Future<void> _queuePastedImageUrl(String url) async {
    try {
      final file = await _chatService.fetchRemoteImage(url);
      _queuePendingAttachment(
        _PendingAttachment.file(file, messageType: MessageType.image),
      );
    } catch (_) {
      _queuePendingAttachment(_PendingAttachment.remoteImage(url));
    }
  }

  /// 粘贴网页图片时剪贴板里只有第三方地址，浏览器取不到，交服务端代抓。
  Future<void> _sendPastedImageUrl(String url) async {
    _setViewState(() {
      _isSendingAttachment = true;
    });
    try {
      final sent = await _chatService.sendImageFromUrl(_chat.id, url);
      _upsertMessage(sent);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('粘贴的图片没能发出去: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        _setViewState(() {
          _isSendingAttachment = false;
        });
      }
    }
  }

  void _showDragUploadOverlay(int fileCount) {
    _setViewState(() {
      _isDragUploadActive = true;
      // 0 = 不知道几个（桌面端系统拖放进入时不告诉数量）。
      _dragUploadFileCount = fileCount < 0 ? 0 : fileCount;
    });
  }

  void _hideDragUploadOverlay() {
    _setViewState(() {
      _isDragUploadActive = false;
      _dragUploadFileCount = 0;
    });
  }

  /// 拖进来的文件和粘贴一样，先排进发送栏，由用户按发送键决定何时发出。
  Future<void> _queueDroppedFiles(List<PickedChatFile> files) async {
    _hideDragUploadOverlay();
    for (final file in files) {
      _queuePendingAttachment(
        _PendingAttachment.file(
          file,
          messageType: _messageTypeForPickedFile(file),
        ),
      );
    }
  }

  MessageType? _messageTypeForPickedFile(PickedChatFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (_isImageFile(file)) return MessageType.image;
    if (mimeType != null && mimeType.startsWith('video/')) {
      return MessageType.video;
    }
    return null;
  }

  /// 桌面端从系统拖进来/从剪贴板粘进来的文件，同样排进发送栏。
  void _queueOsFiles(DroppedFileBatch batch) {
    final skipped = batch.skippedMessage;
    if (skipped != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(skipped)));
    }
    unawaited(_queueDroppedFiles([
      for (final file in batch.files) _pickedChatFileFromDropped(file),
    ]));
  }

  PickedChatFile _pickedChatFileFromDropped(DroppedFile file) {
    return PickedChatFile(
      name: file.name,
      size: file.size,
      path: file.path,
      mimeType: file.mimeType,
      bytes: file.bytes,
    );
  }

  Widget _buildDropPasteTarget(Widget child) {
    // 原生桌面端：接系统拖放和 Ctrl/⌘+V（网页版在 document 上监听，手机端原样返回）。
    return DesktopDropPasteRegion(
      onDragActiveChanged: (active) =>
          active ? _showDragUploadOverlay(0) : _hideDragUploadOverlay(),
      onFiles: _queueOsFiles,
      onPasteImage: (file) => _queuePendingAttachment(
        _PendingAttachment.file(
          _pickedChatFileFromDropped(file),
          messageType: MessageType.image,
        ),
      ),
      child: _buildInAppDropTarget(child),
    );
  }

  Widget _buildInAppDropTarget(Widget child) {
    return DragTarget<List<PickedChatFile>>(
      key: const Key('chat-drop-target'),
      onWillAcceptWithDetails: (details) {
        _showDragUploadOverlay(details.data.length);
        return details.data.isNotEmpty;
      },
      onLeave: (_) => _hideDragUploadOverlay(),
      onAcceptWithDetails: (details) {
        unawaited(_queueDroppedFiles(details.data));
      },
      builder: (context, candidateData, rejectedData) {
        return Stack(
          children: [
            child,
            if (_isDragUploadActive) _buildDragUploadOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildDragUploadOverlay() {
    final count = _dragUploadFileCount;
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: AppColors.primary.withValues(alpha: 0.08),
          child: CustomPaint(
            painter: const _DropUploadBorderPainter(AppColors.primary),
            child: Center(
              child: PMCard(
                elevated: true,
                background: Colors.white.withValues(alpha: 0.95),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_upload_rounded,
                      size: 42,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: PMSpacing.m),
                    Text(
                      count > 0 ? '释放以发送 $count 个文件' : '释放以发送文件',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropUploadBorderPainter extends CustomPainter {
  const _DropUploadBorderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    const dash = 18.0;
    const gap = 10.0;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(18),
      ));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DropUploadBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
