part of '../chat_screen.dart';

extension _ChatScreenComposerParts on _ChatScreenState {
  Future<void> _sendMessage() async {
    final typed = _messageController.text.trim();
    if (typed.isEmpty && !_hasPendingAttachments) return;
    // "/画图 …"、"/问 …" 这类快捷命令在这里执行或改写成 @，见 slash_commands.dart。
    final content = typed.isEmpty ? typed : _applySlashCommandOnSend(typed);
    if (content == null) return;
    // 粘贴进来的图片先排在发送栏里，这一下才真正发出去：每张立刻有自己的上传气泡，
    // 文字排在它们后面发。输入框马上清空——慢网下传图要好几分钟，
    // 等传完再清的话用户再按一次发送，这句话就发了两遍。
    final attachmentsSent = _sendPendingAttachments();
    if (content.isEmpty) {
      await attachmentsSent;
      return;
    }
    final replyToMessage = _replyingToMessage;
    final sendIdentity = _activeSendIdentity();

    _setViewState(() {
      _messageController.clear();
      _replyingToMessage = null;
      _isTyping = false;
      _mentionStartIndex = null;
      _mentionSuggestions = const [];
      _mentionSelectedIndex = 0;
    });

    await _deliverTextMessage(
      content,
      replyToMessage: replyToMessage,
      sendIdentity: sendIdentity,
      after: attachmentsSent,
    );
  }

  /// 先在列表里放一条"发送中"的本地消息（id 就是 clientMessageId），再发出去：
  /// 服务器推回正式消息时 [_upsertMessage] 按 clientMessageId 把它换掉；
  /// 服务器拒收或超时就把它标成失败并提示原因，气泡上可以重发。
  /// [after] 是同一次发送里排在前面的附件：等它们发完（或失败/取消）再发文字，保持先后顺序。
  Future<void> _deliverTextMessage(
    String content, {
    Message? replyToMessage,
    AnonymousIdentity? sendIdentity,
    Future<void>? after,
  }) async {
    final replyToId = replyToMessage?.id;
    final clientMessageId = WebSocketService.newClientMessageId();
    final currentUser = _authService.currentUser;
    final pending = Message(
      id: clientMessageId,
      clientMessageId: clientMessageId,
      content: content,
      senderId: currentUser?.id ?? '',
      senderName:
          sendIdentity?.anonymousName ?? currentUser?.displayName ?? '我',
      senderAvatar: sendIdentity?.anonymousAvatar ?? currentUser?.avatarUrl,
      chatRoomId: _chat.id,
      type: MessageType.text,
      status: MessageStatus.sending,
      timestamp: _nextLocalSendTime(),
      replyToMessage: replyToMessage,
      replyToMessageId: replyToId,
      isAnonymous: sendIdentity != null,
      anonymousName: sendIdentity?.anonymousName,
      anonymousAvatar: sendIdentity?.anonymousAvatar,
      // 匿名消息不能靠 senderId 认"我"，本地气泡直接标明是自己发的。
      sentByMe: true,
    );
    _upsertMessage(pending);
    _scrollToBottom();

    try {
      if (after != null) await after;
      // 双方都开了端到端加密的私聊：明文只留在本机，发出去的是密文信封。
      final encryptedContent = await _sealOutgoingText(
        content,
        anonymous: sendIdentity != null,
      );
      await _webSocketService.connect();
      final roomId = int.tryParse(_chat.id);
      final Message sent;
      if (roomId != null && _webSocketService.isConnected) {
        sent = await _webSocketService.sendTextMessageAwaitingEcho(
          roomId,
          content,
          clientMessageId: clientMessageId,
          isAnonymous: sendIdentity != null,
          replyToId: replyToId,
          encryptedContent: encryptedContent,
        );
      } else {
        sent = await _chatService.sendTextMessage(
          _chat.id,
          content,
          isAnonymous: sendIdentity != null,
          replyToId: replyToId,
          encryptedContent: encryptedContent,
        );
      }
      _afterOutgoingMessage();
      _upsertMessage(sent.copyWith(clientMessageId: clientMessageId));
    } catch (e) {
      if (!mounted) return;
      final stillPending = _messages.any((item) => item.id == clientMessageId);
      if (!stillPending) return; // 迟到的回显已经把它换成正式消息了
      _upsertMessage(pending.copyWith(status: MessageStatus.failed));
      final reason = e is TimeoutException ? '发送超时，请重试' : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发送失败: $reason'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _insertMessageNewline() {
    final value = _messageController.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final nextText = text.replaceRange(start, end, '\n');
    final nextOffset = start + 1;
    _messageController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    if (!_isTyping && nextText.isNotEmpty) {
      _setViewState(() => _isTyping = true);
    }
  }

  /// 发一个附件：列表里先出现发送端的上传气泡（进度、取消），传完换成正式消息。
  /// 这里原样发送（"文件"入口、语音）；相册/相机的图片先进发送栏，见 [_queuePickedImages]。
  Future<void> _sendPickedFile(
    PickedChatFile file, {
    MessageType? messageType,
  }) {
    final upload = _createOutgoingUpload(file: file, messageType: messageType);
    return _runOutgoingUpload(upload);
  }

  Future<void> _generateImageMessage(String prompt) async {
    final normalized = prompt.trim();
    if (normalized.isEmpty || _refuseAiInE2eeChat()) return;
    try {
      final message = await _chatService.generateImageMessage(
        _chat.id,
        prompt: normalized,
      );
      _upsertMessage(message);
      _scrollToBottom();
    } catch (e) {
      final currentUser = _authService.currentUser;
      _upsertMessage(Message(
        id: 'local-image-gen-${DateTime.now().microsecondsSinceEpoch}',
        content: normalized,
        senderId: currentUser?.id ?? '',
        senderName: currentUser?.displayName ?? '我',
        senderAvatar: currentUser?.avatarUrl,
        chatRoomId: _chat.id,
        type: MessageType.imageGeneration,
        status: MessageStatus.failed,
        timestamp: DateTime.now(),
        imageGenPrompt: normalized,
        imageGenStatus: 'FAILED',
      ));
      _scrollToBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('图片生成提交失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// 相册可以一次选多张（手机、桌面、网页都支持）。
  Future<List<PickedChatFile>> _pickImagesFromGallery() async {
    final images = await ImagePicker().pickMultiImage();
    return [for (final image in images) await _pickedChatFileFromXFile(image)];
  }

  Future<PickedChatFile> _pickedChatFileFromXFile(XFile image) async {
    return PickedChatFile(
      name: image.name,
      path: image.path,
      size: await image.length(),
      mimeType: image.mimeType,
      bytes: kIsWeb ? await image.readAsBytes() : null,
    );
  }

  bool get _cameraCaptureSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<PickedChatFile?> _pickImageFromCamera() async {
    final image = await ImagePicker().pickImage(source: ImageSource.camera);
    if (image == null) return null;
    return _pickedChatFileFromXFile(image);
  }

  Future<PickedChatFile?> _pickGenericFile() async {
    if (kIsWeb) {
      return pickGenericFileForCurrentPlatform();
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    return PickedChatFile(
      name: file.name,
      path: file.path,
      size: file.size,
      bytes: file.bytes,
    );
  }

  /// 相册：和微信一样，选好的图先放进发送栏（后台开始压缩、显示大小、可勾"原图"、可移除），
  /// 按发送键才发出。
  Future<void> _pickImagesIntoStrip() async {
    final List<PickedChatFile> files;
    try {
      final picker = widget.imagePicker;
      if (picker != null) {
        final file = await picker();
        files = [if (file != null) file];
      } else {
        files = await _pickImagesFromGallery();
      }
    } catch (error) {
      _showPickerError('无法打开相册', error);
      return;
    }
    _queuePickedImages(files);
  }

  Future<void> _pickAndSendFile() async {
    final picker = widget.filePicker ?? _pickGenericFile;
    final file = await picker();
    if (file != null) {
      await _sendPickedFile(file);
    }
  }

  /// 拍照：拍好的照片同样先进发送栏。
  Future<void> _takePhotoIntoStrip() async {
    final PickedChatFile? file;
    try {
      file = await (widget.cameraPicker ?? _pickImageFromCamera)();
    } catch (error) {
      _showPickerError('无法打开相机', error);
      return;
    }
    if (file != null) _queuePickedImages([file]);
  }

  void _queuePickedImages(List<PickedChatFile> files) {
    if (!mounted || files.isEmpty) return;
    for (final file in files) {
      _queuePendingAttachment(
        _PendingAttachment.file(file, messageType: MessageType.image),
        focusComposer: false,
      );
    }
    // 手机上选完图不弹键盘挡住发送栏；桌面/网页聚焦输入框，直接按 Enter 就能发。
    if (!_isNativeMobile) _focusComposerAfterStripChange();
  }

  bool get _isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void _showPickerError(String action, Object error) {
    if (!mounted) return;
    final denied = error is PlatformException &&
        error.code.toLowerCase().contains('denied');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            denied ? '$action：没有权限，请在系统设置里允许 PM chat 使用' : '$action：$error'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _pickAndSendVoiceFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.audio,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    await _sendPickedFile(
      PickedChatFile(
        name: file.name,
        path: file.path,
        size: file.size,
        bytes: file.bytes,
      ),
      messageType: MessageType.voice,
    );
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isStoppingVoice) return;
    if (_isRecordingVoice) {
      await _stopAndSendVoiceRecording();
    } else {
      await _startVoiceRecording();
    }
  }

  Future<void> _startVoiceRecording() async {
    try {
      await _voiceRecorder.start();
      if (!mounted) return;
      _voiceRecordingTimer?.cancel();
      _voiceRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecordingVoice) return;
        _setViewState(() {
          _voiceRecordingDuration += const Duration(seconds: 1);
        });
      });
      _setViewState(() {
        _isRecordingVoice = true;
        _voiceRecordingDuration = Duration.zero;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法开始录音: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _stopAndSendVoiceRecording() async {
    _setViewState(() => _isStoppingVoice = true);
    try {
      final recorded = await _voiceRecorder.stop();
      _voiceRecordingTimer?.cancel();
      if (!mounted) return;
      _setViewState(() {
        _isRecordingVoice = false;
        _voiceRecordingDuration = Duration.zero;
      });
      if (recorded == null || recorded.bytes.isEmpty) return;
      await _sendPickedFile(
        recorded.toPickedChatFile(),
        messageType: MessageType.voice,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('语音发送失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        _setViewState(() => _isStoppingVoice = false);
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    await _voiceRecorder.cancel();
    _voiceRecordingTimer?.cancel();
    if (!mounted) return;
    _setViewState(() {
      _isRecordingVoice = false;
      _isStoppingVoice = false;
      _voiceRecordingDuration = Duration.zero;
    });
  }

  Future<void> _sendLocationMessage() async {
    final controller = TextEditingController();
    final location = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送位置'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '位置名称或地图链接',
            hintText: '例如：公司会议室 / https://maps...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (location == null || location.isEmpty) return;

    try {
      final sent = await _chatService.sendTypedMessage(
        _chat.id,
        location,
        type: MessageType.location,
        isAnonymous: _shouldSendAnonymous(),
      );
      _afterOutgoingMessage();
      _upsertMessage(sent);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('位置发送失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildDesktopInputBar() {
    return Material(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _buildPendingAttachmentsStrip(),
            _buildReplyPreviewStrip(),
            _buildMentionPickerPanel(),
            _buildSlashCommandPanel(),
            _buildAnonymousIdentityHint(),
            _buildVoiceRecordingStrip(),
            _buildComposerToolbar(desktop: true),
            const SizedBox(height: PMSpacing.xs),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _buildComposerTextField(),
              const SizedBox(width: PMSpacing.s),
              _buildComposerSubmitButton(),
            ]),
          ]),
        ));
  }

  Widget _buildAnonymousIdentityHint() {
    return AnonymousIdentityHint(
      identity: _anonymousIdentity,
      quota: _anonymousQuota,
      visible: _shouldSendAnonymous(),
      rerolling: _isRerollingAnonymous,
      onReroll: _rerollAnonymousIdentity,
    );
  }

  Widget _buildVoiceRecordingStrip() {
    if (!_isRecordingVoice) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在录音 ${_formatVoiceRecordingDuration(_voiceRecordingDuration)}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _cancelVoiceRecording,
            icon: const PMSymbolIcon(
              PMSymbol.close,
              size: 14,
              color: AppColors.error,
            ),
            label: const Text('取消'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: _isStoppingVoice ? null : _stopAndSendVoiceRecording,
            icon: const PMSymbolIcon(
              PMSymbol.send,
              size: 14,
              color: Colors.white,
            ),
            label: Text(_isStoppingVoice ? '发送中' : '发送'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatVoiceRecordingDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
