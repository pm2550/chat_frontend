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

  /// 缩略图能不能直接画出来（远程图已在入队时取回字节，所以只看本地文件）。
  bool get isImage {
    if (remoteUrl != null) return true;
    final mimeType = file?.mimeType?.toLowerCase();
    if (mimeType != null) return mimeType.startsWith('image/');
    return messageType == MessageType.image;
  }

  bool get isVideo {
    final mimeType = file?.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.startsWith('video/')) return true;
    return messageType == MessageType.video;
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

  /// 发送栏里排队的附件：立刻清空发送栏、每个都先放出自己的上传气泡（排队中），
  /// 再按顺序一个个传，保证对方看到的先后和发送栏里一致。返回的 Future 在全部传完
  /// （成功、失败或被取消）后完成。
  Future<void> _sendPendingAttachments() {
    if (_pendingAttachments.isEmpty) return Future<void>.value();
    final queued = List<_PendingAttachment>.of(_pendingAttachments);
    _setViewState(() => _pendingAttachments.clear());

    final uploads = [
      for (final attachment in queued)
        if (attachment.file != null)
          _createOutgoingUpload(
            file: attachment.file,
            messageType: attachment.messageType ??
                _messageTypeForPickedFile(attachment.file!),
          )
        else if (attachment.remoteUrl != null)
          _createOutgoingUpload(remoteUrl: attachment.remoteUrl),
    ];
    return () async {
      for (final upload in uploads) {
        await _runOutgoingUpload(upload);
      }
    }();
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
                _pendingAttachmentsSummary(),
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

  String _pendingAttachmentsSummary() {
    final count = _pendingAttachments.length;
    final allImages = _pendingAttachments.every((item) => item.isImage);
    final unit = allImages ? '张待发送图片' : '个待发送文件';
    return '$count$unit · 按发送键发出';
  }

  Widget _buildPendingAttachmentTile(int index) {
    final attachment = _pendingAttachments[index];
    return SizedBox(
      key: ValueKey('chat-pending-attachment-$index'),
      width: attachment.isImage ? 72 : 132,
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
    if (!attachment.isImage) {
      return _buildPendingFileCard(attachment);
    }
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

  Widget _buildPendingFileCard(_PendingAttachment attachment) {
    final size = attachment.file?.size ?? 0;
    return Padding(
      padding: const EdgeInsets.all(PMSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            attachment.isVideo
                ? Icons.videocam_rounded
                : Icons.insert_drive_file_rounded,
            size: 22,
            color: AppColors.primary,
          ),
          const SizedBox(height: PMSpacing.xs),
          Text(
            attachment.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (size > 0)
            Text(
              _formatFileSize(size),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
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
