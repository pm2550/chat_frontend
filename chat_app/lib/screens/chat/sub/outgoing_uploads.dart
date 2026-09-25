part of '../chat_screen.dart';

/// 连续多少秒一个字节都没发出去，就提示“网络较慢”。
const Duration _uploadStallThreshold = Duration(seconds: 30);

DateTime _lastLocalSendTime = DateTime.fromMillisecondsSinceEpoch(0);

/// 本地占位消息的时间戳：严格递增。同一毫秒里连发几张图再跟一句话，
/// 列表按时间排序时也不会把先后顺序打乱。
DateTime _nextLocalSendTime() {
  var now = DateTime.now();
  if (!now.isAfter(_lastLocalSendTime)) {
    now = _lastLocalSendTime.add(const Duration(milliseconds: 1));
  }
  _lastLocalSendTime = now;
  return now;
}

enum _UploadPhase { queued, compressing, uploading, failed }

/// 发送端一条正在上传（或上传失败）的附件。列表里对应一条占位消息，
/// id 同时作为 clientMessageId 交给服务器，正式消息回来时按它换掉占位气泡。
class _OutgoingUpload {
  _OutgoingUpload({
    required this.placeholder,
    this.file,
    this.remoteUrl,
    this.messageType,
    this.preparation,
  });

  final Message placeholder;
  final PickedChatFile? file;

  /// 图片先在本机压缩/删元数据（见 ImageUploadPreparer），完成后才开始上传。
  final Future<PreparedImageUpload>? preparation;

  /// 处理好的待上传文件；重试时直接用它，不再压缩一遍。
  PickedChatFile? prepared;

  /// 粘贴网页图片时只有地址，由服务器代抓：没有字节进度可报。
  final String? remoteUrl;
  final MessageType? messageType;
  final UploadCancelToken cancelToken = UploadCancelToken();

  _UploadPhase phase = _UploadPhase.queued;
  int sentBytes = 0;
  int totalBytes = 0;
  bool stalled = false;
  String? failure;
  Timer? _stallTimer;

  String get id => placeholder.id;

  bool get isServerFetch => remoteUrl != null;

  /// 服务器代抓那一步发出去就收不回来了，只在排队时能取消。
  bool get canCancel => !isServerFetch || phase == _UploadPhase.queued;

  double? get fraction =>
      totalBytes > 0 ? (sentBytes / totalBytes).clamp(0.0, 1.0) : null;

  int get percent => ((fraction ?? 0) * 100).floor();

  bool get allBytesSent => totalBytes > 0 && sentBytes >= totalBytes;

  ImageProvider? _thumbnail;
  List<int>? _thumbnailSource;

  /// 气泡里的小图：压缩好以后换成压缩后的字节（原生平台选的图一开始只有路径）。
  ImageProvider? get thumbnail {
    final source = prepared?.bytes ?? file?.bytes;
    if (!identical(source, _thumbnailSource)) {
      _thumbnailSource = source;
      _thumbnail = _buildThumbnail(prepared ?? file);
    }
    return _thumbnail;
  }

  ImageProvider? _buildThumbnail(PickedChatFile? file) {
    final bytes = file?.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final mimeType = file?.mimeType?.toLowerCase();
    final isImage = mimeType != null
        ? mimeType.startsWith('image/')
        : placeholder.type == MessageType.image;
    if (!isImage) return null;
    // 只解码缩略图大小；同一个 provider 反复重建也命中图片缓存。
    return ResizeImage(
      MemoryImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes)),
      width: 144,
    );
  }

  void watchForStall(VoidCallback onStall) {
    _stallTimer?.cancel();
    _stallTimer = Timer(_uploadStallThreshold, onStall);
  }

  void stopWatching() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  /// 不再需要这次请求了（正式消息已到或用户取消）：停表并中止请求。
  void settle() {
    stopWatching();
    cancelToken.cancel();
  }
}

extension _ChatScreenOutgoingUploadParts on _ChatScreenState {
  /// 先在列表里放一个发送端的上传气泡，再由 [_runOutgoingUpload] 真正上传。
  _OutgoingUpload _createOutgoingUpload({
    PickedChatFile? file,
    String? remoteUrl,
    MessageType? messageType,
    Future<PreparedImageUpload>? preparation,
  }) {
    final id = WebSocketService.newClientMessageId();
    final currentUser = _authService.currentUser;
    final placeholderType = messageType ??
        (file == null
            ? MessageType.image
            : _messageTypeForPickedFile(file) ?? MessageType.file);
    final upload = _OutgoingUpload(
      placeholder: Message(
        id: id,
        clientMessageId: id,
        content: file?.name ?? remoteUrl ?? '',
        senderId: currentUser?.id ?? '',
        senderName: currentUser?.displayName ?? '我',
        senderAvatar: currentUser?.avatarUrl,
        chatRoomId: _chat.id,
        type: placeholderType,
        status: MessageStatus.sending,
        timestamp: _nextLocalSendTime(),
        fileName: file?.name,
        fileSize: file?.size,
        fileType: file?.mimeType,
        sentByMe: true,
      ),
      file: file,
      remoteUrl: remoteUrl,
      messageType: messageType,
      preparation: preparation,
    );
    _outgoingUploads[id] = upload;
    _upsertMessage(upload.placeholder);
    _scrollToBottom();
    return upload;
  }

  bool _isLiveUpload(_OutgoingUpload upload) =>
      mounted && identical(_outgoingUploads[upload.id], upload);

  /// 上传一个附件。成功后正式消息换掉气泡；失败把气泡标成失败（可重试）；
  /// 取消或服务器已先推回正式消息时什么都不做——气泡那边已经处理过了。
  Future<void> _runOutgoingUpload(_OutgoingUpload upload) async {
    if (!_isLiveUpload(upload) || upload.cancelToken.isCancelled) return;
    final preparation = upload.preparation;
    if (preparation != null && upload.prepared == null) {
      _setViewState(() => upload.phase = _UploadPhase.compressing);
      // 压缩不会抛异常（出错时退回原图），这里只防万一。
      final prepared = await preparation.then<PickedChatFile?>(
        (result) => result.file,
        onError: (Object _) => null,
      );
      if (!_isLiveUpload(upload) || upload.cancelToken.isCancelled) return;
      upload.prepared = prepared ?? upload.file;
    }
    _setViewState(() {
      upload.phase = _UploadPhase.uploading;
      upload.sentBytes = 0;
      upload.totalBytes = 0;
      upload.stalled = false;
      upload.failure = null;
    });
    _watchUploadStall(upload);

    try {
      final sent = await _performOutgoingUpload(upload);
      upload.stopWatching();
      if (!mounted) return;
      _outgoingUploads.remove(upload.id);
      _upsertMessage(sent.copyWith(clientMessageId: upload.id));
      _scrollToBottom();
    } on UploadCancelledException {
      upload.stopWatching();
    } catch (error) {
      upload.stopWatching();
      if (!_isLiveUpload(upload)) return;
      _setViewState(() {
        upload.phase = _UploadPhase.failed;
        upload.stalled = false;
        upload.failure = _uploadFailureReason(error);
      });
      _upsertMessage(upload.placeholder.copyWith(status: MessageStatus.failed));
    }
  }

  Future<Message> _performOutgoingUpload(_OutgoingUpload upload) async {
    void onProgress(int sent, int total) =>
        _handleUploadProgress(upload, sent, total);

    final file = upload.prepared ?? upload.file;
    if (file != null) {
      return _chatService.sendFileMessage(
        _chat.id,
        file,
        messageType: upload.messageType,
        chat: _chat,
        clientMessageId: upload.id,
        onProgress: onProgress,
        cancelToken: upload.cancelToken,
      );
    }
    final url = upload.remoteUrl!;
    if (_chat.type == ChatType.private && await _e2ee.shouldEncrypt(_chat)) {
      // 加密私聊：先把图片取回本机，再按普通附件加密上传（服务器只存密文）。
      final image = await _chatService.fetchRemoteImage(url);
      if (upload.cancelToken.isCancelled) {
        throw const UploadCancelledException();
      }
      return _chatService.sendFileMessage(
        _chat.id,
        image,
        messageType: MessageType.image,
        chat: _chat,
        clientMessageId: upload.id,
        onProgress: onProgress,
        cancelToken: upload.cancelToken,
      );
    }
    // 粘贴网页图片时剪贴板里只有第三方地址，浏览器取不到，交服务端代抓。
    return _chatService.sendImageFromUrl(
      _chat.id,
      url,
      clientMessageId: upload.id,
    );
  }

  void _handleUploadProgress(_OutgoingUpload upload, int sent, int total) {
    if (!_isLiveUpload(upload) || upload.phase != _UploadPhase.uploading) {
      return;
    }
    final advanced = sent > upload.sentBytes;
    _setViewState(() {
      upload.sentBytes = sent;
      if (total > 0) upload.totalBytes = total;
      if (advanced) upload.stalled = false;
    });
    if (advanced) _watchUploadStall(upload);
  }

  void _watchUploadStall(_OutgoingUpload upload) {
    if (upload.allBytesSent) {
      // 字节都发完了，在等服务器处理，不是网络慢。
      upload.stopWatching();
      return;
    }
    upload.watchForStall(() {
      if (!_isLiveUpload(upload) || upload.phase != _UploadPhase.uploading) {
        return;
      }
      _setViewState(() => upload.stalled = true);
    });
  }

  String _uploadFailureReason(Object error) {
    if (error is TimeoutException) return '网络超时';
    if (error is ChatDataException) return error.message;
    return '$error'.replaceFirst(RegExp(r'^Exception: '), '');
  }

  void _cancelOutgoingUpload(_OutgoingUpload upload) {
    upload.settle();
    _removeOutgoingUpload(upload);
  }

  void _removeOutgoingUpload(_OutgoingUpload upload) {
    upload.stopWatching();
    _setViewState(() {
      _outgoingUploads.remove(upload.id);
      _messages.removeWhere((message) => message.id == upload.id);
    });
    _saveMessageCache();
  }

  /// 重试：原样再发同一个文件（新的 clientMessageId，气泡挪到最底下）。
  Future<void> _retryOutgoingUpload(_OutgoingUpload upload) async {
    _removeOutgoingUpload(upload);
    final retry = _createOutgoingUpload(
      file: upload.prepared ?? upload.file,
      remoteUrl: upload.remoteUrl,
      messageType: upload.messageType,
    );
    await _runOutgoingUpload(retry);
  }

  String _uploadStatusText(_OutgoingUpload upload) {
    switch (upload.phase) {
      case _UploadPhase.queued:
        return '等待发送';
      case _UploadPhase.compressing:
        return '正在压缩…';
      case _UploadPhase.failed:
        return '发送失败：${upload.failure ?? '未知错误'}';
      case _UploadPhase.uploading:
        break;
    }
    if (upload.fraction == null) {
      if (upload.stalled) return '网络较慢，仍在发送…';
      return upload.isServerFetch ? '正在发送（服务器取图中）…' : '正在发送…';
    }
    if (upload.allBytesSent) return '正在发送 100% · 等待服务器确认';
    if (upload.stalled) return '网络较慢，仍在上传… ${upload.percent}%';
    return '正在发送 ${upload.percent}%';
  }

  IconData _uploadFileIcon(_OutgoingUpload upload) {
    switch (upload.placeholder.type) {
      case MessageType.image:
        return Icons.image_outlined;
      case MessageType.video:
        return Icons.videocam_rounded;
      case MessageType.voice:
      case MessageType.audio:
        return Icons.graphic_eq_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  /// 发送端的上传气泡：缩略图/文件名、真实进度、取消；失败时显示原因和重试。
  Widget _buildOutgoingUploadBubble(_OutgoingUpload upload) {
    final failed = upload.phase == _UploadPhase.failed;
    final thumbnail = upload.thumbnail;
    final name = upload.file?.name ??
        (upload.isServerFetch ? '网页图片' : upload.placeholder.content);
    final accent = failed ? AppColors.error : AppColors.primary;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          key: ValueKey('chat-upload-${upload.id}'),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    child: SizedBox.square(
                      dimension: 48,
                      child: thumbnail != null
                          ? Image(
                              image: thumbnail,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildUploadIconTile(upload),
                            )
                          : _buildUploadIconTile(upload),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _uploadStatusText(upload),
                          key: ValueKey('chat-upload-status-${upload.id}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: failed || upload.stalled
                                ? AppColors.error
                                : AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!failed) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    // 压缩中不知道要多久：不定进度条。上传进度按压缩后的大小算。
                    value: upload.phase == _UploadPhase.queued
                        ? 0
                        : upload.phase == _UploadPhase.compressing
                            ? null
                            : upload.fraction,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  ),
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (failed) ...[
                    TextButton(
                      key: ValueKey('chat-upload-remove-${upload.id}'),
                      onPressed: () => _removeOutgoingUpload(upload),
                      child: const Text('移除'),
                    ),
                    TextButton(
                      key: ValueKey('chat-upload-retry-${upload.id}'),
                      onPressed: () => _retryOutgoingUpload(upload),
                      child: const Text('重试'),
                    ),
                  ] else if (upload.canCancel)
                    TextButton(
                      key: ValueKey('chat-upload-cancel-${upload.id}'),
                      onPressed: () => _cancelOutgoingUpload(upload),
                      child: const Text('取消'),
                    )
                  else
                    const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadIconTile(_OutgoingUpload upload) {
    return ColoredBox(
      color: AppColors.primary.withValues(alpha: 0.1),
      child: Center(
        child: Icon(
          _uploadFileIcon(upload),
          size: 24,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
