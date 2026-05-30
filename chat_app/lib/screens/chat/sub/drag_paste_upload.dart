part of '../chat_screen.dart';

extension _ChatScreenDragPasteUploadParts on _ChatScreenState {
  void _attachDropPasteHandlers() {
    if (_dropPasteController != null) return;
    _dropPasteController = attachChatDropPasteHandlers(
      onDragEntered: _showDragUploadOverlay,
      onDragExited: _hideDragUploadOverlay,
      onFilesDropped: _sendDroppedFiles,
      onPasteImage: (file) => _sendPickedFile(
        file,
        messageType: MessageType.image,
      ),
    );
  }

  void _showDragUploadOverlay(int fileCount) {
    _setViewState(() {
      _isDragUploadActive = true;
      _dragUploadFileCount = fileCount <= 0 ? 1 : fileCount;
    });
  }

  void _hideDragUploadOverlay() {
    _setViewState(() {
      _isDragUploadActive = false;
      _dragUploadFileCount = 0;
    });
  }

  Future<void> _sendDroppedFiles(List<PickedChatFile> files) async {
    _hideDragUploadOverlay();
    for (final file in files) {
      await _sendPickedFile(
        file,
        messageType: _messageTypeForPickedFile(file),
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

  Widget _buildDropPasteTarget(Widget child) {
    return DragTarget<List<PickedChatFile>>(
      key: const Key('chat-drop-target'),
      onWillAcceptWithDetails: (details) {
        _showDragUploadOverlay(details.data.length);
        return details.data.isNotEmpty;
      },
      onLeave: (_) => _hideDragUploadOverlay(),
      onAcceptWithDetails: (details) {
        unawaited(_sendDroppedFiles(details.data));
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
    final count = _dragUploadFileCount <= 0 ? 1 : _dragUploadFileCount;
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
                      '释放以发送 $count 个文件',
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
