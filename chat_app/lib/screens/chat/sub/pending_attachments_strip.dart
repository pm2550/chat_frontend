part of '../chat_screen.dart';

/// 等在发送栏里、还没发出去的附件（粘贴进来的图片）。
class _PendingAttachment {
  _PendingAttachment.file(this.file, {this.messageType}) : remoteUrl = null;

  _PendingAttachment.remoteImage(this.remoteUrl)
      : file = null,
        messageType = MessageType.image;

  final PickedChatFile? file;
  final String? remoteUrl;
  final MessageType? messageType;

  /// 图片的本机处理结果，按"是否原图"各存一份：排进发送栏就开始压缩，
  /// 用户还在打字时就压好了；切换"原图"也不用重来。
  final Map<bool, Future<PreparedImageUpload>> _preparations = {};
  final Map<bool, PreparedImageUpload> _prepared = {};

  /// 本地图片才压缩；网页图片地址由服务器代抓、视频和文件原样发。
  bool get compressible =>
      file != null && isImage && ImageUploadPreparer.looksLikeImage(file!);

  Future<PreparedImageUpload> preparation(
    ImageUploadPreparer preparer, {
    required bool original,
    VoidCallback? onReady,
  }) {
    return _preparations.putIfAbsent(original, () {
      final future = preparer.prepare(file!, original: original);
      unawaited(future.then((result) {
        _prepared[original] = result;
        onReady?.call();
      }));
      return future;
    });
  }

  /// 按当前模式实际要上传的大小；还没处理完时为 null。
  int? uploadSize({required bool original}) => _prepared[original]?.uploadSize;

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

  void _queuePendingAttachment(
    _PendingAttachment attachment, {
    bool focusComposer = true,
  }) {
    _setViewState(() => _pendingAttachments.add(attachment));
    _startPendingPreparation(attachment);
    if (focusComposer) _focusComposerAfterStripChange();
  }

  /// 发送栏出现、增减会改动输入框上方的布局。网页版开着无障碍语义树时，这一变动会让浏览器焦点
  /// 从输入框背后的 DOM 元素掉到 <body>；Flutter 这边却仍认为输入框有焦点，requestFocus 什么都不做，
  /// 于是按 Enter 没反应，得再点一下输入框。网页上先让出焦点、下一帧再要回来，
  /// 引擎就会重新聚焦输入框对应的 DOM 元素。
  void _focusComposerAfterStripChange() {
    if (!mounted) return;
    final repairDomFocus = ChatScreen.debugRepairComposerDomFocus ?? kIsWeb;
    if (_composerFocusRepairScheduled) return; // 同一帧里连着加了好几个
    if (!repairDomFocus || !_focusNode.hasFocus) {
      _focusNode.requestFocus();
      return;
    }
    _composerFocusRepairScheduled = true;
    _focusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _composerFocusRepairScheduled = false;
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _startPendingPreparation(_PendingAttachment attachment) {
    if (!attachment.compressible) return;
    unawaited(attachment.preparation(
      _imagePreparer,
      original: _pendingSendOriginal,
      // 处理完刷新一下，缩略图角上显示实际要发的大小。
      onReady: () {
        if (mounted && _pendingAttachments.contains(attachment)) {
          _setViewState(() {});
        }
      },
    ));
  }

  bool get _hasCompressiblePendingImages =>
      _pendingAttachments.any((attachment) => attachment.compressible);

  void _togglePendingSendOriginal() {
    _setViewState(() => _pendingSendOriginal = !_pendingSendOriginal);
    _pendingAttachments.forEach(_startPendingPreparation);
  }

  void _removePendingAttachment(int index) {
    if (index < 0 || index >= _pendingAttachments.length) return;
    _setViewState(() => _pendingAttachments.removeAt(index));
    // 移掉一张后焦点要留在输入框，不然接着打字打不进去（手机上不主动弹键盘挡住发送栏）。
    if (!_isNativeMobile) _focusComposerAfterStripChange();
  }

  /// 发送栏里排队的附件：立刻清空发送栏、每个都先放出自己的上传气泡（排队中），
  /// 再按顺序一个个传，保证对方看到的先后和发送栏里一致。返回的 Future 在全部传完
  /// （成功、失败或被取消）后完成。
  Future<void> _sendPendingAttachments() {
    if (_pendingAttachments.isEmpty) return Future<void>.value();
    final queued = List<_PendingAttachment>.of(_pendingAttachments);
    final original = _pendingSendOriginal;
    _setViewState(() {
      _pendingAttachments.clear();
      // "原图"只管这一批，下次发送栏里的图默认还是压缩。
      _pendingSendOriginal = false;
    });

    final uploads = [
      for (final attachment in queued)
        if (attachment.file != null)
          _createOutgoingUpload(
            file: attachment.file,
            messageType: attachment.messageType ??
                _messageTypeForPickedFile(attachment.file!),
            preparation: attachment.compressible
                ? attachment.preparation(_imagePreparer, original: original)
                : null,
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _pendingAttachmentsSummary(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (_hasCompressiblePendingImages)
                    _buildPendingOriginalToggle(),
                ],
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

  /// "原图"开关：勾上后这一批图片按原图发（只删定位等元数据，不压缩），旁边写着原图总大小。
  Widget _buildPendingOriginalToggle() {
    final total = _pendingAttachments
        .where((attachment) => attachment.compressible)
        .fold<int>(0, (sum, attachment) => sum + attachment.file!.size);
    final selected = _pendingSendOriginal;
    return Tooltip(
      message: selected ? '按原图发送（只去掉定位等信息）' : '勾选后按原图发送，不压缩',
      child: InkWell(
        key: const ValueKey('chat-pending-original-toggle'),
        onTap: _togglePendingSendOriginal,
        borderRadius: BorderRadius.circular(PMRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                total > 0 ? '原图 (${_formatFileSize(total)})' : '原图',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 图片角上的大小：压缩模式显示压缩后的大小（还在压就写"压缩中"），原图模式显示原图大小。
  String? _pendingImageSizeLabel(_PendingAttachment attachment) {
    if (!attachment.compressible) return null;
    final size = attachment.uploadSize(original: _pendingSendOriginal);
    if (size != null) return _formatFileSize(size);
    return _pendingSendOriginal
        ? _formatFileSize(attachment.file!.size)
        : '压缩中';
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
          if (_pendingImageSizeLabel(attachment) case final label?)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(PMRadius.s),
                ),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Text(
                    label,
                    key: ValueKey('chat-pending-attachment-size-$index'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
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
