import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../models/call_state.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/anonymous_service.dart';
import '../../services/chat_data_service.dart';
import '../../services/chat_call_service.dart';
import '../../services/platform_chat_file_picker.dart'
    if (dart.library.js_interop) '../../services/platform_chat_file_picker_web.dart';
import '../../services/websocket_service.dart';
import '../../widgets/anonymous_toggle_button.dart';
import '../../widgets/call_media_view.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import 'chat_file_center_screen.dart';
import 'chat_room_settings_screen.dart';

typedef ChatAttachmentPicker = Future<PickedChatFile?> Function();

class ChatScreenArguments {
  const ChatScreenArguments({
    required this.chat,
    this.startCall,
  });

  final Chat chat;
  final CallMediaKind? startCall;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.chatService,
    this.webSocketService,
    this.authService,
    this.callService,
    this.imagePicker,
    this.filePicker,
  });

  final ChatDataService? chatService;
  final WebSocketService? webSocketService;
  final AuthService? authService;
  final ChatCallService? callService;
  final ChatAttachmentPicker? imagePicker;
  final ChatAttachmentPicker? filePicker;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late Chat _chat;
  late final ChatDataService _chatService;
  late final WebSocketService _webSocketService;
  late final AuthService _authService;
  late final ChatCallService _callService;
  late final bool _ownsCallService;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _callSubscription;

  List<Message> _messages = [];
  bool _isTyping = false;
  bool _isLoadingMessages = true;
  bool _isLoadingOlderMessages = false;
  bool _hasMoreMessages = false;
  bool _isSendingAttachment = false;
  AnonymousIdentity? _anonymousIdentity;
  int _nextMessagePage = 1;
  String? _errorMessage;
  bool _didInitialize = false;
  bool _incomingCallDialogVisible = false;
  CallMediaKind? _pendingStartCall;

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatDataService();
    _webSocketService = widget.webSocketService ?? WebSocketService();
    _authService = widget.authService ?? AuthService();
    _ownsCallService = widget.callService == null;
    _callService = widget.callService ??
        ChatCallService(
          webSocketService: _webSocketService,
          authService: _authService,
        );
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialize) return;
    final routeArgs = ModalRoute.of(context)!.settings.arguments;
    if (routeArgs is ChatScreenArguments) {
      _chat = routeArgs.chat;
      _pendingStartCall = routeArgs.startCall;
    } else {
      _chat = routeArgs as Chat;
    }
    _didInitialize = true;
    _loadInitialMessages();
    _connectRealtime();
    final startCall = _pendingStartCall;
    if (startCall != null) {
      _pendingStartCall = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_startCall(startCall));
        }
      });
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _callSubscription?.cancel();
    if (_ownsCallService) {
      _callService.dispose();
    }
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitialMessages() async {
    setState(() {
      _isLoadingMessages = true;
      _errorMessage = null;
    });

    try {
      final page = await _chatService.getMessagePage(_chat.id);
      if (!mounted) return;
      setState(() {
        _messages = List<Message>.from(page.messages);
        _hasMoreMessages = page.hasNext;
        _nextMessagePage = page.currentPage + 1;
        _isLoadingMessages = false;
      });
      _scrollToBottom();
      unawaited(_markAllRead());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoadingMessages = false;
      });
    }
  }

  Future<void> _connectRealtime() async {
    _messageSubscription =
        _webSocketService.onMessage.listen(_handleRealtimeMessage);
    _callSubscription = _webSocketService.onCallSignal.listen((signal) {
      unawaited(_handleCallSignal(signal));
    });
    await _webSocketService.connect();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoadingMessages ||
        _isLoadingOlderMessages ||
        !_hasMoreMessages) {
      return;
    }
    if (_scrollController.position.pixels <= 80) {
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadOlderMessages() async {
    setState(() {
      _isLoadingOlderMessages = true;
    });

    try {
      final page = await _chatService.getMessagePage(
        _chat.id,
        page: _nextMessagePage,
      );
      if (!mounted) return;
      setState(() {
        final existingIds = _messages.map((message) => message.id).toSet();
        _messages = [
          ...page.messages
              .where((message) => !existingIds.contains(message.id)),
          ..._messages,
        ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _hasMoreMessages = page.hasNext;
        _nextMessagePage = page.currentPage + 1;
        _isLoadingOlderMessages = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOlderMessages = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('加载更早消息失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _handleRealtimeMessage(Message message) {
    if (message.chatRoomId != _chat.id || !mounted) {
      return;
    }
    _upsertMessage(message);
    _scrollToBottom();
    unawaited(_markAllRead());
  }

  Future<void> _handleCallSignal(Map<String, dynamic> signal) async {
    if (signal['chatRoomId']?.toString() != _chat.id || !mounted) {
      return;
    }
    final action = signal['action']?.toString();
    try {
      await _callService.handleSignal(signal);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('通话信令处理失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    if (action == 'invite' && _callService.state.phase == CallPhase.incoming) {
      _showIncomingCallDialog();
    } else if (action == 'reject' || action == 'hangup') {
      final label = _callService.state.statusLabel;
      if (label != '未通话') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(label)),
        );
      }
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _chatService.markAllRead(_chat.id);
    } catch (_) {
      // Read receipts are best-effort for this first real-chat slice.
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _messageController.clear();
      _isTyping = false;
    });

    try {
      await _webSocketService.connect();
      final roomId = int.tryParse(_chat.id);
      if (roomId != null &&
          _webSocketService.sendTextMessage(
            roomId,
            content,
            isAnonymous: _anonymousIdentity != null,
          )) {
        return;
      }

      final sent = await _chatService.sendTextMessage(
        _chat.id,
        content,
        isAnonymous: _anonymousIdentity != null,
      );
      _upsertMessage(sent);
      _scrollToBottom();
    } catch (e) {
      final currentUser = _authService.currentUser;
      _upsertMessage(Message(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        content: content,
        senderId: currentUser?.id ?? '',
        senderName: _anonymousIdentity?.anonymousName ??
            currentUser?.displayName ??
            '我',
        senderAvatar:
            _anonymousIdentity?.anonymousAvatar ?? currentUser?.avatarUrl,
        chatRoomId: _chat.id,
        type: MessageType.text,
        status: MessageStatus.failed,
        timestamp: DateTime.now(),
        isAnonymous: _anonymousIdentity != null,
        anonymousName: _anonymousIdentity?.anonymousName,
        anonymousAvatar: _anonymousIdentity?.anonymousAvatar,
      ));
      _scrollToBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _sendPickedFile(
    PickedChatFile file, {
    MessageType? messageType,
  }) async {
    setState(() {
      _isSendingAttachment = true;
    });

    try {
      final sent = await _chatService.sendFileMessage(
        _chat.id,
        file,
        messageType: messageType,
      );
      _upsertMessage(sent);
      _scrollToBottom();
    } catch (e) {
      final currentUser = _authService.currentUser;
      _upsertMessage(Message(
        id: 'local-file-${DateTime.now().microsecondsSinceEpoch}',
        content: file.name,
        senderId: currentUser?.id ?? '',
        senderName: currentUser?.displayName ?? '我',
        senderAvatar: currentUser?.avatarUrl,
        chatRoomId: _chat.id,
        type: messageType ??
            (_isImageFile(file) ? MessageType.image : MessageType.file),
        status: MessageStatus.failed,
        timestamp: DateTime.now(),
        fileName: file.name,
        fileSize: file.size,
        fileType: file.mimeType,
      ));
      _scrollToBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('文件发送失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingAttachment = false;
        });
      }
    }
  }

  Future<PickedChatFile?> _pickImageFromGallery() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    return PickedChatFile(
      name: image.name,
      path: image.path,
      size: await image.length(),
      mimeType: image.mimeType,
      bytes: kIsWeb ? await image.readAsBytes() : null,
    );
  }

  Future<PickedChatFile?> _pickImageFromCamera() async {
    final image = await ImagePicker().pickImage(source: ImageSource.camera);
    if (image == null) return null;
    return PickedChatFile(
      name: image.name,
      path: image.path,
      size: await image.length(),
      mimeType: image.mimeType,
      bytes: kIsWeb ? await image.readAsBytes() : null,
    );
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

  Future<void> _pickAndSendImage() async {
    final picker = widget.imagePicker ?? _pickImageFromGallery;
    final file = await picker();
    if (file != null) {
      await _sendPickedFile(file);
    }
  }

  Future<void> _pickAndSendFile() async {
    final picker = widget.filePicker ?? _pickGenericFile;
    final file = await picker();
    if (file != null) {
      await _sendPickedFile(file);
    }
  }

  Future<void> _pickAndSendCameraImage() async {
    final file = await _pickImageFromCamera();
    if (file != null) {
      await _sendPickedFile(file, messageType: MessageType.image);
    }
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
        isAnonymous: _anonymousIdentity != null,
      );
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

  Future<void> _startCall(CallMediaKind mediaKind) async {
    final label = '${mediaKind.label}通话';
    final roomId = int.tryParse(_chat.id);
    if (roomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label启动失败: 会话编号无效'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    try {
      await _webSocketService.connect();
      await _callService.startOutgoingCall(
        chatRoomId: roomId,
        mediaKind: mediaKind,
        peerName: _chat.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label已发起')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label启动失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showIncomingCallDialog() {
    if (_incomingCallDialogVisible || !mounted) return;
    final state = _callService.state;
    _incomingCallDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('${state.peerName ?? '联系人'} 的${state.mediaKind.label}来电'),
        content: Text(
          _callService.isSupported
              ? '接听后浏览器会请求麦克风${state.isVideo ? '和摄像头' : ''}权限。'
              : '当前平台暂不支持实时通话。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _callService.rejectIncoming();
            },
            child: const Text('拒绝'),
          ),
          FilledButton.icon(
            onPressed: _callService.isSupported
                ? () {
                    Navigator.of(dialogContext).pop();
                    unawaited(_callService.acceptIncoming());
                  }
                : null,
            icon: Icon(state.isVideo ? Icons.videocam : Icons.call),
            label: const Text('接听'),
          ),
        ],
      ),
    ).whenComplete(() {
      _incomingCallDialogVisible = false;
    });
  }

  Future<void> _updateRoomPreference({bool? muted, bool? pinned}) async {
    final nextMuted = muted ?? _chat.isMuted;
    final nextPinned = pinned ?? _chat.isPinned;
    setState(() {
      _chat = _chat.copyWith(isMuted: nextMuted, isPinned: nextPinned);
    });
    try {
      await _chatService.updateNotificationSettings(
        _chat.id,
        muted: muted,
        pinned: pinned,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chat = _chat.copyWith(
          isMuted: muted == null ? _chat.isMuted : !nextMuted,
          isPinned: pinned == null ? _chat.isPinned : !nextPinned,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('偏好更新失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _clearChatHistoryAndLeave() async {
    try {
      await _chatService.clearChatHistory(_chat.id);
      if (!mounted) return;
      setState(() {
        _messages = [];
      });
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('聊天记录已清空')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清空失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openAttachment(Message message) async {
    try {
      final fileUrl = message.fileUrl;
      if (fileUrl != null &&
          fileUrl.isNotEmpty &&
          !ApiConstants.requiresAuthHeaderForFile(fileUrl)) {
        final uri = Uri.parse(ApiConstants.resolveFileUrl(fileUrl));
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      }
      final file = await _chatService.downloadFile(message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已下载 ${file.name} (${_formatFileSize(file.bytes.length)})',
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

  void _upsertMessage(Message message) {
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index == -1) {
        _messages.add(message);
      } else {
        _messages[index] = message;
      }
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
  }

  Future<void> _recallMessage(Message message) async {
    try {
      final updated = await _chatService.recallMessage(message.id);
      _upsertMessage(updated.chatRoomId.isEmpty
          ? updated.copyWith(chatRoomId: _chat.id)
          : updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('撤回失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteMessage(Message message) async {
    try {
      final updated = await _chatService.deleteMessage(message.id);
      _upsertMessage(updated.chatRoomId.isEmpty
          ? updated.copyWith(chatRoomId: _chat.id)
          : updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildCallPanel() {
    return AnimatedBuilder(
      animation: _callService,
      builder: (context, _) {
        final state = _callService.state;
        if (state.isIdle) {
          return const SizedBox.shrink();
        }
        final isDesktop = PMBreakpoints.isDesktop(context);
        final isTerminal =
            state.phase == CallPhase.ended || state.phase == CallPhase.failed;
        final panel = Container(
          margin: EdgeInsets.fromLTRB(
            isDesktop ? 20 : 12,
            isDesktop ? 14 : 10,
            isDesktop ? 20 : 12,
            0,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [AppColors.appBarShadow],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    state.isVideo ? Icons.videocam : Icons.call,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${state.peerName ?? _chat.name} · ${state.mediaKind.label} · ${state.statusLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: isTerminal ? '关闭' : '挂断',
                    onPressed: isTerminal
                        ? _callService.clear
                        : () => unawaited(_callService.hangUp()),
                    icon: Icon(
                      isTerminal ? Icons.close : Icons.call_end,
                      color: isTerminal ? Colors.white70 : Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          isTerminal ? Colors.white12 : AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (state.isVideo)
                SizedBox(
                  height: isDesktop ? 260 : 190,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CallMediaView(
                            viewId: state.remoteViewId,
                            label: state.statusLabel,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        width: isDesktop ? 168 : 116,
                        height: isDesktop ? 112 : 82,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white24),
                            ),
                            child: CallMediaView(
                              viewId: state.localViewId,
                              label: state.cameraOff ? '摄像头已关' : '本机',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.graphic_eq,
                          color: Colors.white70, size: 42),
                      const SizedBox(height: 8),
                      Text(
                        state.statusLabel,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              if (!isTerminal) ...[
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _buildCallControlButton(
                      icon: state.microphoneMuted ? Icons.mic_off : Icons.mic,
                      label: state.microphoneMuted ? '开麦' : '静音',
                      onPressed: _callService.toggleMicrophone,
                    ),
                    if (state.isVideo)
                      _buildCallControlButton(
                        icon: state.cameraOff
                            ? Icons.videocam_off
                            : Icons.videocam,
                        label: state.cameraOff ? '开摄像头' : '关摄像头',
                        onPressed: _callService.toggleCamera,
                      ),
                    _buildCallControlButton(
                      icon: Icons.call_end,
                      label: '挂断',
                      danger: true,
                      onPressed: () => unawaited(_callService.hangUp()),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
        return panel;
      },
    );
  }

  Widget _buildCallControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    return Tooltip(
      message: label,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: danger ? AppColors.error : Colors.white12,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PMBreakpoints.isDesktop(context)) {
      return _buildDesktopChatScaffold();
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Stack(
              children: [
                _buildChatAvatar(),
                if (_chat.type == ChatType.private &&
                    _chat.participants.isNotEmpty &&
                    _chat.participants.first.onlineStatus ==
                        OnlineStatus.online)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _chat.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_chat.type == ChatType.private &&
                      _chat.participants.isNotEmpty)
                    Text(
                      _chat.participants.first.onlineStatus ==
                              OnlineStatus.online
                          ? '在线'
                          : _chat.participants.first.lastSeen != null
                              ? '最后在线 ${timeago.format(_chat.participants.first.lastSeen!, locale: 'zh')}'
                              : '离线',
                      style: TextStyle(
                        fontSize: 12,
                        color: _chat.participants.first.onlineStatus ==
                                OnlineStatus.online
                            ? AppColors.online
                            : AppColors.textSecondary,
                      ),
                    )
                  else if (_chat.type == ChatType.group)
                    Text(
                      '${_chat.participants.length}人',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => _startCall(CallMediaKind.audio),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _startCall(CallMediaKind.video),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showChatOptions();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCallPanel(),
          Expanded(
            child: PMChatPattern(
              dense: true,
              child: _isLoadingMessages
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? _buildMessageLoadError()
                      : _messages.isEmpty
                          ? _buildEmptyMessages()
                          : _buildMessageList(),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              border:
                  const Border(top: BorderSide(color: AppColors.borderLight)),
              boxShadow: const [AppColors.appBarShadow],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  _buildInputIconButton(
                    icon: Icons.add,
                    onPressed: _showInputOptions,
                    tooltip: '附件',
                  ),

                  AnonymousToggleButton(
                    chatRoomId: int.tryParse(_chat.id) ?? 0,
                    anonymousEnabled: _chat.anonymousEnabled,
                    onAnonymousChanged: (identity) {
                      setState(() => _anonymousIdentity = identity);
                    },
                  ),

                  // 文本输入框
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.cloud,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        maxLines: 4,
                        minLines: 1,
                        decoration: const InputDecoration(
                          hintText: '输入消息...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (text) {
                          setState(() {
                            _isTyping = text.isNotEmpty;
                          });
                        },
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 发送/语音按钮
                  _isTyping
                      ? _buildInputIconButton(
                          icon: Icons.send,
                          onPressed: _sendMessage,
                          tooltip: '发送',
                          filled: true,
                        )
                      : _buildInputIconButton(
                          icon: Icons.mic,
                          onPressed: _pickAndSendVoiceFile,
                          tooltip: '语音',
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopChatScaffold() {
    return Scaffold(
      body: Row(
        children: [
          _buildDesktopRoomPanel(),
          Expanded(
            child: Column(
              children: [
                _buildDesktopConversationHeader(),
                _buildCallPanel(),
                Expanded(
                  child: PMChatPattern(
                    dense: true,
                    child: _isLoadingMessages
                        ? const Center(child: CircularProgressIndicator())
                        : _errorMessage != null
                            ? _buildMessageLoadError()
                            : _messages.isEmpty
                                ? _buildEmptyMessages()
                                : _buildMessageList(),
                  ),
                ),
                _buildDesktopInputBar(),
              ],
            ),
          ),
          _buildDesktopInfoPanel(),
        ],
      ),
    );
  }

  Widget _buildDesktopRoomPanel() {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.borderLight)),
        boxShadow: [AppColors.appBarShadow],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 6),
                  const PMChatLogo(size: 34, showWordmark: true),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  width: 78,
                  height: 78,
                  child: FittedBox(child: _buildChatAvatar()),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _chat.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _chatSubtitle(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              _buildDesktopActionTile(
                icon: Icons.call,
                title: '语音通话',
                onTap: () => _startCall(CallMediaKind.audio),
              ),
              _buildDesktopActionTile(
                icon: Icons.videocam,
                title: '视频通话',
                onTap: () => _startCall(CallMediaKind.video),
              ),
              _buildDesktopActionTile(
                icon: Icons.search,
                title: '搜索记录',
                onTap: _showSearchSheet,
              ),
              const Spacer(),
              _buildInfoTile(
                Icons.schedule,
                '最近消息',
                _messages.isEmpty
                    ? '暂无消息'
                    : timeago.format(_messages.last.timestamp, locale: 'zh'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopConversationHeader() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _chat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _chatSubtitle(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          _buildDesktopHeaderIcon(Icons.call, '语音', () {
            _startCall(CallMediaKind.audio);
          }),
          const SizedBox(width: 8),
          _buildDesktopHeaderIcon(Icons.videocam, '视频', () {
            _startCall(CallMediaKind.video);
          }),
          const SizedBox(width: 8),
          _buildDesktopHeaderIcon(Icons.more_horiz, '更多', _showChatOptions),
        ],
      ),
    );
  }

  Widget _buildDesktopHeaderIcon(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.pixelBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
      ),
    );
  }

  Widget _buildDesktopInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
        boxShadow: [AppColors.appBarShadow],
      ),
      child: Row(
        children: [
          _buildInputIconButton(
            icon: Icons.add,
            onPressed: _showInputOptions,
            tooltip: '附件',
          ),
          AnonymousToggleButton(
            chatRoomId: int.tryParse(_chat.id) ?? 0,
            anonymousEnabled: _chat.anonymousEnabled,
            onAnonymousChanged: (identity) {
              setState(() => _anonymousIdentity = identity);
            },
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.cloud,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                maxLines: 4,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: '输入消息，Enter 发送',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (text) =>
                    setState(() => _isTyping = text.isNotEmpty),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _isTyping
              ? _buildInputIconButton(
                  icon: Icons.send,
                  onPressed: _sendMessage,
                  tooltip: '发送',
                  filled: true,
                )
              : _buildInputIconButton(
                  icon: Icons.mic,
                  onPressed: _pickAndSendVoiceFile,
                  tooltip: '语音',
                ),
        ],
      ),
    );
  }

  Widget _buildDesktopInfoPanel() {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: AppColors.borderLight)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const PMSectionHeader(
              title: '房间信息',
              subtitle: '当前会话的上下文与快捷入口',
            ),
            const SizedBox(height: 16),
            _buildInfoTile(Icons.people, '成员', _chatSubtitle()),
            _buildInfoTile(
              Icons.notifications,
              '通知',
              _chat.isMuted ? '已免打扰' : '正常接收',
            ),
            _buildInfoTile(
              Icons.push_pin,
              '置顶',
              _chat.isPinned ? '已置顶' : '未置顶',
            ),
            const SizedBox(height: 18),
            _buildDesktopActionTile(
              icon: Icons.folder_open,
              title: '聊天文件',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatFileCenterScreen(
                      chatRoomId: _chat.id,
                      chatRoomName: _chat.name,
                      chatService: _chatService,
                    ),
                  ),
                );
              },
            ),
            _buildDesktopActionTile(
              icon: _chat.isMuted ? Icons.volume_up : Icons.volume_off,
              title: _chat.isMuted ? '开启通知' : '消息免打扰',
              onTap: () => _updateRoomPreference(muted: !_chat.isMuted),
            ),
            _buildDesktopActionTile(
              icon: Icons.push_pin,
              title: _chat.isPinned ? '取消置顶' : '置顶聊天',
              onTap: () => _updateRoomPreference(pinned: !_chat.isPinned),
            ),
            _buildDesktopActionTile(
              icon: Icons.settings,
              title: _chat.type == ChatType.group ? '群聊设置' : '聊天信息',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatRoomSettingsScreen(
                      chatRoomId: int.tryParse(_chat.id) ?? 0,
                      chatRoomName: _chat.name,
                      isAdmin: _chat.createdBy == _authService.currentUser?.id,
                      isGroup: _chat.type == ChatType.group,
                      currentUserId: _authService.currentUser?.id,
                      chatService: _chatService,
                      initialAnonymousEnabled: _chat.anonymousEnabled,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cloud,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pixelMint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.secondaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _chatSubtitle() {
    if (_chat.type == ChatType.private && _chat.participants.isNotEmpty) {
      final participant = _chat.participants.first;
      if (participant.onlineStatus == OnlineStatus.online) {
        return '在线';
      }
      if (participant.lastSeen != null) {
        return '最后在线 ${timeago.format(participant.lastSeen!, locale: 'zh')}';
      }
      return '离线';
    }
    if (_chat.type == ChatType.group) {
      return '${_chat.participants.length}人';
    }
    return '会话';
  }

  Widget _buildChatAvatar() {
    final fallback = _chat.type == ChatType.group
        ? '群'
        : _chat.name.isNotEmpty
            ? _chat.name[0].toUpperCase()
            : '?';
    return CircleAvatar(
      radius: 20,
      backgroundColor:
          _chat.type == ChatType.group ? AppColors.primary : AppColors.accent,
      backgroundImage: _chat.avatarUrl != null
          ? NetworkImage(
              ApiConstants.resolveFileUrl(_chat.avatarUrl!),
            )
          : null,
      child: _chat.avatarUrl == null
          ? Text(
              fallback,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }

  Widget _buildInputIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    bool filled = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          gradient: filled ? AppColors.messageGradient : null,
          color: filled ? null : AppColors.pixelBlue,
          borderRadius: BorderRadius.circular(8),
          border: filled ? null : Border.all(color: AppColors.borderLight),
        ),
        child: IconButton(
          icon: Icon(icon, size: 20),
          color: filled ? Colors.white : AppColors.primary,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    final currentUserId = _authService.currentUser?.id;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      itemCount: _messages.length + (_isLoadingOlderMessages ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoadingOlderMessages && index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final messageIndex = index - (_isLoadingOlderMessages ? 1 : 0);
        final message = _messages[messageIndex];
        final isMe = currentUserId != null && message.senderId == currentUserId;
        final showTime = messageIndex == 0 ||
            _messages[messageIndex - 1]
                    .timestamp
                    .difference(message.timestamp)
                    .inMinutes
                    .abs() >
                5;

        return Column(
          children: [
            if (showTime)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Text(
                  _formatMessageTime(message.timestamp),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            GestureDetector(
              onLongPress: () => _showMessageActions(message, isMe),
              child: MessageBubble(
                message: message,
                isMe: isMe,
                showAvatar: !isMe && _chat.type == ChatType.group,
                onOpenAttachment: _openAttachment,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMessageLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              '消息加载失败',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialMessages,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyMessages() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PMChatMark(size: 54),
            SizedBox(height: 12),
            Text(
              '暂无消息',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '发出第一条消息，PM chat 会把上下文留在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMessageTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      return '今天 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return '昨天 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return '${weekdays[timestamp.weekday - 1]} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.month}月${timestamp.day}日 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  void _showMessageActions(Message message, bool isMe) {
    if (message.id.startsWith('local-') || message.isRemoved) {
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (isMe)
                _buildChatOption(
                  icon: Icons.undo,
                  title: '撤回消息',
                  onTap: () {
                    Navigator.pop(context);
                    _recallMessage(message);
                  },
                ),
              _buildChatOption(
                icon: Icons.delete_outline,
                title: '删除消息',
                color: AppColors.error,
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchSheet() {
    _searchController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        var isSearching = false;
        var searched = false;
        String? error;
        List<Message> results = const [];

        Future<void> runSearch(StateSetter setSheetState) async {
          final keyword = _searchController.text.trim();
          if (keyword.isEmpty) {
            return;
          }
          setSheetState(() {
            isSearching = true;
            searched = true;
            error = null;
          });
          try {
            final page = await _chatService.searchMessages(_chat.id, keyword);
            setSheetState(() {
              results = page.messages;
              isSearching = false;
            });
          } catch (e) {
            setSheetState(() {
              error = e.toString();
              isSearching = false;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.82,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜索聊天记录',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () => runSearch(setSheetState),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) => runSearch(setSheetState),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isSearching)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (error != null)
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              '搜索失败: $error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (searched && results.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            '没有找到相关消息',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemBuilder: (context, index) {
                            final message = results[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                message.resolvedFileLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${message.senderName} · ${_formatMessageTime(message.timestamp)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _upsertMessage(message);
                              },
                            );
                          },
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemCount: results.length,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInputOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: [
                    _buildInputOption(
                      icon: Icons.photo_camera,
                      label: '拍照',
                      onTap: () {
                        final sendFuture = _pickAndSendCameraImage();
                        Navigator.pop(context);
                        unawaited(sendFuture);
                      },
                    ),
                    _buildInputOption(
                      icon: Icons.photo_library,
                      label: '相册',
                      onTap: () {
                        final sendFuture = _pickAndSendImage();
                        Navigator.pop(context);
                        unawaited(sendFuture);
                      },
                    ),
                    _buildInputOption(
                      icon: Icons.attach_file,
                      label: '文件',
                      onTap: () {
                        final sendFuture = _pickAndSendFile();
                        Navigator.pop(context);
                        unawaited(sendFuture);
                      },
                    ),
                    _buildInputOption(
                      icon: Icons.location_on,
                      label: '位置',
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_sendLocationMessage());
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _isSendingAttachment && (label == '相册' || label == '文件')
                  ? Icons.hourglass_empty
                  : icon,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildChatOption(
                      icon: Icons.info_outline,
                      title: _chat.type == ChatType.group ? '群聊设置' : '聊天信息',
                      onTap: () async {
                        Navigator.pop(context);
                        final roomId = int.tryParse(_chat.id);
                        if (roomId == null) return;
                        final left = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatRoomSettingsScreen(
                              chatRoomId: roomId,
                              chatRoomName: _chat.name,
                              isGroup: _chat.type == ChatType.group,
                              currentUserId: _authService.currentUser?.id,
                              chatService: _chatService,
                              initialAnonymousEnabled: _chat.anonymousEnabled,
                            ),
                          ),
                        );
                        if (left == true && context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.search,
                      title: '搜索聊天记录',
                      onTap: () {
                        Navigator.pop(context);
                        _showSearchSheet();
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.volume_off,
                      title: _chat.isMuted ? '取消静音' : '静音通知',
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(
                          _updateRoomPreference(muted: !_chat.isMuted),
                        );
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.push_pin,
                      title: _chat.isPinned ? '取消置顶' : '置顶聊天',
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(
                          _updateRoomPreference(pinned: !_chat.isPinned),
                        );
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.delete_outline,
                      title: '删除聊天',
                      color: AppColors.error,
                      onTap: () {
                        Navigator.pop(context);
                        _showDeleteDialog();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatOption({
    required IconData icon,
    required String title,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        color: color ?? AppColors.textPrimary,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除聊天'),
        content: const Text('确定要删除这个聊天吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_clearChatHistoryAndLeave());
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
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
