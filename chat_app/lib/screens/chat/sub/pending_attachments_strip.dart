part of '../chat_screen.dart';

/// 等在发送栏里、还没发出去的附件（粘贴进来的图片）。
class _PendingAttachment {
  const _PendingAttachment.file(this.file, {this.messageType})
      : remoteUrl = null;

  const _PendingAttachment.remoteImage(this.remoteUrl)
      : file = null,
        messageType = MessageType.image;

  final PickedChatFile? file;
  final String? remoteUrl;
  final MessageType? messageType;

  String get label {
    if (file != null) return file!.name;
    final uri = Uri.tryParse(remoteUrl ?? '');
    final segments = uri?.pathSegments ?? const [];
    return segments.isEmpty ? '网页图片' : segments.last;
  }
}

extension _ChatScreenPendingAttachmentParts on _ChatScreenState {
  bool get _hasPendingAttachments => _pendingAttachments.isNotEmpty;

  void _queuePendingAttachment(_PendingAttachment attachment) {
    _setViewState(() => _pendingAttachments.add(attachment));
    _focusNode.requestFocus();
  }

  void _removePendingAttachment(int index) {
    if (index < 0 || index >= _pendingAttachments.length) return;
    _setViewState(() => _pendingAttachments.removeAt(index));
    // 移掉一张后焦点要留在输入框，不然接着打字打不进去。
    _focusNode.requestFocus();
  }

  /// 发送栏里排队的附件按顺序发出，随后清空。
  Future<void> _sendPendingAttachments() async {
    if (_pendingAttachments.isEmpty) return;
    final queued = List<_PendingAttachment>.of(_pendingAttachments);
    _setViewState(() => _pendingAttachments.clear());

    for (final attachment in queued) {
      final file = attachment.file;
      if (file != null) {
        await _sendPickedFile(
          file,
          messageType: attachment.messageType ?? _messageTypeForPickedFile(file),
        );
        continue;
      }
      final url = attachment.remoteUrl;
      if (url != null) {
        await _sendPastedImageUrl(url);
      }
    }
  }

  Widget _buildPendingAttachmentsStrip() {
    if (_pendingAttachments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PMCard(
        padding: const EdgeInsets.all(PMSpacing.s),
        background: AppColors.cloud,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: PMSpacing.xs,
                bottom: PMSpacing.s,
              ),
              child: Text(
                '${_pendingAttachments.length} 张待发送图片 · 按发送键发出',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingAttachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: PMSpacing.s),
                itemBuilder: (context, index) =>
                    _buildPendingAttachmentTile(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingAttachmentTile(int index) {
    final attachment = _pendingAttachments[index];
    return SizedBox(
      key: ValueKey('chat-pending-attachment-$index'),
      width: 72,
      height: 72,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PMRadius.s),
              child: ColoredBox(
                color: Colors.white,
                child: _buildPendingAttachmentPreview(attachment),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Tooltip(
              message: '移除 ${attachment.label}',
              child: InkWell(
                key: ValueKey('chat-pending-attachment-remove-$index'),
                onTap: () => _removePendingAttachment(index),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingAttachmentPreview(_PendingAttachment attachment) {
    final bytes = attachment.file?.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        Uint8List.fromList(bytes),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPendingAttachmentFallback(),
      );
    }
    final url = attachment.remoteUrl;
    if (url != null) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPendingAttachmentFallback(),
      );
    }
    return _buildPendingAttachmentFallback();
  }

  Widget _buildPendingAttachmentFallback() {
    return const Center(
      child: Icon(
        Icons.image_outlined,
        size: 26,
        color: AppColors.textSecondary,
      ),
    );
  }
}
