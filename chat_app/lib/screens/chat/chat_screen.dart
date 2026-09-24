import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/call_state.dart';
import '../../models/chat.dart';
import '../../models/chat_room_member.dart';
import '../../models/chat_customization.dart';
import '../../models/message.dart';
import '../../models/sticker.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/agent_client_tools.dart';
import '../../services/anonymous_service.dart';
import '../../services/bot_service.dart';
import '../../services/chat_data_service.dart';
import '../../services/memory_service.dart';
import '../../services/pending_call_invite.dart';
import '../../services/chat_call_service.dart';
import '../../services/contact_data_service.dart';
import '../../services/chat_drop_paste.dart'
    if (dart.library.js_interop) '../../services/chat_drop_paste_web.dart';
import '../../services/file_save.dart' as file_save;
import '../../services/typing_indicator_sender.dart';
import '../../services/os_dropped_files.dart';
import '../../services/platform_chat_file_picker.dart'
    if (dart.library.js_interop) '../../services/platform_chat_file_picker_web.dart';
import '../../services/user_profile_service.dart';
import '../../services/voice_playback.dart';
import '../../services/voice_recorder.dart'
    if (dart.library.js_interop) '../../services/voice_recorder_web.dart';
import '../../services/websocket_service.dart';
import 'sub/memory_panel.dart';
import '../../widgets/anonymous_toggle_button.dart';
import '../../widgets/anonymous_identity_hint.dart';
import '../../widgets/call_grid_view.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/chat_video_thumbnail.dart';
import '../../widgets/chat_video_preview_dialog.dart';
import '../../widgets/desktop_drop_paste_region.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import '../../widgets/sticker_tile.dart';
import '../../widgets/typing_indicator.dart';
import 'chat_file_center_screen.dart';
import 'chat_room_bot_config_screen.dart';
import 'chat_room_settings_screen.dart';
import 'pinned_messages.dart';
import 'sticker_pack_upload_screen.dart';

part 'sub/chat_app_bar.dart';
part 'sub/message_list.dart';
part 'sub/message_composer.dart';
part 'sub/message_actions_sheet.dart';
part 'sub/members_panel.dart';
part 'sub/files_panel.dart';
part 'sub/bots_panel.dart';
part 'sub/mention_picker.dart';
part 'sub/reply_preview_strip.dart';
part 'sub/reaction_bar.dart';
part 'sub/poll_card.dart';
part 'sub/link_preview_card.dart';
part 'sub/announcement_banner.dart';
part 'sub/drag_paste_upload.dart';
part 'sub/pending_attachments_strip.dart';
part 'sub/realtime_sync.dart';

typedef ChatAttachmentPicker = Future<PickedChatFile?> Function();

class ChatScreenArguments {
  const ChatScreenArguments({
    required this.chat,
    this.startCall,
    this.focusMessage,
  });

  final Chat chat;
  final CallMediaKind? startCall;

  /// 打开后定位并高亮这条消息（例如从“我的收藏”跳转过来）。
  final Message? focusMessage;
}

class _CachedChatMessages {
  const _CachedChatMessages({
    required this.messages,
    required this.hasMoreMessages,
    required this.nextMessagePage,
  });

  final List<Message> messages;
  final bool hasMoreMessages;
  final int nextMessagePage;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.chatService,
    this.webSocketService,
    this.authService,
    this.profileService,
    this.callService,
    this.contactService,
    this.botService,
    this.imagePicker,
    this.filePicker,
    this.fileSaver,
  });

  final ChatDataService? chatService;
  final WebSocketService? webSocketService;
  final AuthService? authService;
  final UserProfileService? profileService;
  final ChatCallService? callService;
  final ContactDataService? contactService;
  final BotService? botService;
  final ChatAttachmentPicker? imagePicker;
  final ChatAttachmentPicker? filePicker;
  final file_save.FileSaver? fileSaver;

  @visibleForTesting
  static void clearMessageCacheForTesting() {
    _messageCache.clear();
  }

  static final Map<String, _CachedChatMessages> _messageCache = {};

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late Chat _chat;
  late final ChatDataService _chatService;
  late final WebSocketService _webSocketService;
  late final AuthService _authService;
  late final ChatCallService _callService;
  late final AnonymousService _anonymousService;
  late final BotService _botService;
  late final MemoryService _memoryService;
  late final UserProfileService _profileService;
  late final ContactDataService _contactService;
  late final bool _ownsCallService;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<Message>? _messageUpdateSubscription;
  StreamSubscription<MessageActionEvent>? _messageActionSubscription;
  StreamSubscription<Map<String, dynamic>>? _statusSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;
  StreamSubscription<Map<String, dynamic>>? _callSubscription;
  Timer? _messageHighlightTimer;
  Timer? _voiceRecordingTimer;
  Timer? _initialBottomAnchorTimer;
  Timer? _messageReconciliationTimer;
  int _initialBottomAnchorGeneration = 0;
  bool _initialBottomAnchorActive = false;
  final VoiceRecorder _voiceRecorder = VoiceRecorder();
  late final TypingIndicatorSender _typingSender;
  bool _removedFromRoom = false;

  /// 每个读者在本会话里已经计入到哪条（来自实时已读回执），重复或乱序的回执不会重复加已读数。
  final Map<String, int> _readerMarks = {};

  List<Message> _messages = [];
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<String, Future<LinkPreview?>> _linkPreviewFutures = {};
  final Set<String> _viewportReadMarkedMessageIds = {};
  final Set<String> _friendUserIds = {};
  final Set<String> _pendingFriendRequestUserIds = {};
  final Set<String> _sendingFriendRequestUserIds = {};
  final Set<String> _openingPrivateChatUserIds = {};
  int _pollRefreshEpoch = 0;
  List<BotConfig> _roomBots = [];
  bool _isTyping = false;
  bool _isLoadingMessages = true;
  bool _isLoadingOlderMessages = false;
  bool _hasMoreMessages = false;
  bool _isSendingAttachment = false;
  bool _isRecordingVoice = false;
  bool _isStoppingVoice = false;
  Duration _voiceRecordingDuration = Duration.zero;
  bool _isLoadingRoomBots = false;
  bool _desktopInfoPanelCollapsed = false;
  int _desktopInfoPanelTab = 0;
  int _newMessagesBelow = 0;
  bool _showNewMessagesButton = false;
  List<User> _mentionMembers = const [];
  List<User> _mentionSuggestions = const [];
  int _mentionSelectedIndex = 0;
  int? _mentionStartIndex;
  bool _isLoadingMentionMembers = false;
  AnonymousIdentity? _anonymousIdentity;
  AnonymousQuota? _anonymousQuota;
  bool _anonymousPerMessageMode = false;
  bool _anonymousNextMessage = false;
  bool _isRerollingAnonymous = false;
  List<String> _typingUserNames = const [];
  Message? _replyingToMessage;
  String? _highlightedMessageId;
  int _nextMessagePage = 1;
  String? _errorMessage;
  bool _didInitialize = false;
  bool _incomingCallDialogVisible = false;
  BuildContext? _incomingCallDialogContext;
  CallMediaKind? _pendingStartCall;
  Message? _pendingFocusMessage;
  late final PinnedMessagesController _pinnedMessages;
  bool _isResolvingRouteChat = false;
  String? _routeChatIdToResolve;
  String? _routeChatError;
  bool _showAnnouncementBanner = false;
  String? _announcementSeenKey;
  ChatDropPasteController? _dropPasteController;
  final List<_PendingAttachment> _pendingAttachments = [];
  final VoicePlayback _voicePlayback = VoicePlayback();
  String? _playingVoiceMessageId;
  bool _isDragUploadActive = false;
  int _dragUploadFileCount = 0;
  UserAppSettings _appSettings = const UserAppSettings();
  bool _restoredMessagesFromCache = false;
  bool _wasBackgrounded = false;
  bool _isRefreshingAfterResume = false;
  bool _isReconcilingMessages = false;

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatDataService();
    _webSocketService = widget.webSocketService ?? WebSocketService();
    _authService = widget.authService ?? AuthService();
    _anonymousService = AnonymousService();
    _botService = widget.botService ?? BotService();
    _memoryService = MemoryService(authService: _authService);
    _profileService =
        widget.profileService ?? UserProfileService(authService: _authService);
    _contactService = widget.contactService ?? ContactDataService();
    _ownsCallService = widget.callService == null;
    _callService = widget.callService ??
        ChatCallService(
          webSocketService: _webSocketService,
          authService: _authService,
        );
    _pinnedMessages = PinnedMessagesController(
      chatService: _chatService,
      roomId: () => _chat.id,
    );
    _scrollController.addListener(_handleScroll);
    _typingSender = TypingIndicatorSender(send: _sendTypingState);
    _messageController.addListener(_handleComposerTextForTyping);
    _focusNode.addListener(_handleComposerFocusForTyping);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialize) return;
    final route = ModalRoute.of(context);
    final routeArgs = route?.settings.arguments;
    if (routeArgs is ChatScreenArguments) {
      _initializeResolvedChat(
        routeArgs.chat,
        startCall: routeArgs.startCall,
        focusMessage: routeArgs.focusMessage,
      );
      return;
    }
    if (routeArgs is Chat) {
      _initializeResolvedChat(routeArgs);
      return;
    }

    final chatRoomId = _chatRoomIdFromRoute(route?.settings);
    _chat = _placeholderChat(chatRoomId);
    _didInitialize = true;
    _routeChatIdToResolve = chatRoomId;
    if (chatRoomId == null) {
      _isLoadingMessages = false;
      _routeChatError = '缺少聊天室编号。请从消息工作台打开会话，或使用 /chat/房间ID 这样的链接。';
      return;
    }

    _isResolvingRouteChat = true;
    _isLoadingMessages = false;
    unawaited(_loadChatFromRoute(chatRoomId));
  }

  void _initializeResolvedChat(
    Chat chat, {
    CallMediaKind? startCall,
    Message? focusMessage,
  }) {
    _chat = chat;
    _pendingStartCall = startCall;
    _pendingFocusMessage = focusMessage;
    _didInitialize = true;
    _syncAgentClientToolState();
    _startChatSession();
  }

  Future<LinkPreview?> _loadLinkPreview(String url) {
    return _linkPreviewFutures.putIfAbsent(url, () async {
      try {
        return await _chatService.fetchUrlPreview(url);
      } catch (_) {
        return null;
      }
    });
  }

  void _startChatSession() {
    _restoreCachedMessages();
    unawaited(_loadCustomizationSettings());
    unawaited(_loadAnonymousModePreference());
    unawaited(_prepareAnnouncementBanner());
    _attachDropPasteHandlers();
    _syncPinPermissions();
    unawaited(_pinnedMessages.load());
    unawaited(_bootstrapMessages().then((_) => _focusPendingMessage()));
    unawaited(_loadMentionMembers());
    _loadRoomBots();
    _loadFriendshipState();
    _connectRealtime();
    _startMessageReconciliation();
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

  void _focusPendingMessage() {
    final message = _pendingFocusMessage;
    if (message == null || !mounted) return;
    _pendingFocusMessage = null;
    // 首屏的“滚到最新”会和定位抢滚动位置，先停掉它。
    _cancelInitialBottomAnchor();
    _openSearchResult(message);
  }

  void _startMessageReconciliation() {
    _messageReconciliationTimer?.cancel();
    _messageReconciliationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_reconcileMessages()),
    );
  }

  Future<void> _reconcileMessages() async {
    if (!mounted ||
        _wasBackgrounded ||
        _isReconcilingMessages ||
        !_didInitialize ||
        _chat.id.trim().isEmpty) {
      return;
    }
    _isReconcilingMessages = true;
    try {
      await _loadMessageDelta();
    } finally {
      _isReconcilingMessages = false;
    }
  }

  Future<void> _loadCustomizationSettings() async {
    if (_authService.accessToken == null) return;
    try {
      final settings = await _profileService.getSettings();
      if (!mounted) return;
      _setViewState(() => _appSettings = settings);
    } catch (_) {
      // Chat rendering falls back to bundled presets when settings are unavailable.
    }
  }

  Future<void> _loadAnonymousModePreference() async {
    final roomId = int.tryParse(_chat.id);
    if (roomId == null) return;
    final mode = await _anonymousService.getMode(roomId);
    if (!mounted) return;
    _setViewState(() {
      _anonymousPerMessageMode = mode == ChatAnonymousMode.perMessage;
      _anonymousNextMessage = false;
    });
  }

  String? _chatRoomIdFromRoute(RouteSettings? settings) {
    final candidates = [
      settings?.name,
      Uri.base.fragment,
    ];

    for (final raw in candidates) {
      if (raw == null || raw.trim().isEmpty) continue;
      final normalized = raw.startsWith('/') ? raw : '/$raw';
      final uri = Uri.tryParse(normalized);
      if (uri == null) continue;

      final queryId = uri.queryParameters['chatRoomId'] ??
          uri.queryParameters['roomId'] ??
          uri.queryParameters['id'];
      if (queryId != null && queryId.trim().isNotEmpty) {
        return queryId.trim();
      }

      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments.first == 'chat') {
        final id = segments[1].trim();
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  Chat _placeholderChat(String? id) {
    return Chat(
      id: id ?? '',
      name: '正在打开聊天',
      type: ChatType.group,
      createdAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _typingSender.stop();
    _messageController.removeListener(_handleComposerTextForTyping);
    _focusNode.removeListener(_handleComposerFocusForTyping);
    _voicePlayback.dispose();
    _pinnedMessages.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _messageSubscription?.cancel();
    _messageUpdateSubscription?.cancel();
    _messageActionSubscription?.cancel();
    _statusSubscription?.cancel();
    _typingSubscription?.cancel();
    _callSubscription?.cancel();
    _messageHighlightTimer?.cancel();
    _voiceRecordingTimer?.cancel();
    _messageReconciliationTimer?.cancel();
    _cancelInitialBottomAnchor();
    _voiceRecorder.dispose();
    _dropPasteController?.dispose();
    if (_ownsCallService) {
      _callService.dispose();
    }
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_wasBackgrounded) {
        _wasBackgrounded = false;
        unawaited(_refreshAfterResume());
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _wasBackgrounded = true;
    }
  }

  Future<void> _refreshAfterResume() async {
    if (_isRefreshingAfterResume ||
        !_didInitialize ||
        _chat.id.trim().isEmpty) {
      return;
    }
    _isRefreshingAfterResume = true;
    try {
      await Future.wait<void>([
        _webSocketService.reconnect(),
        _reconcileMessages(),
      ]);
    } finally {
      _isRefreshingAfterResume = false;
    }
  }

  void _setViewState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    if (_didInitialize) {
      _syncAgentClientToolState();
    }
  }

  void _restoreCachedMessages() {
    final cached = ChatScreen._messageCache[_chat.id];
    if (cached == null) return;
    _messages = List<Message>.from(cached.messages);
    _hasMoreMessages = cached.hasMoreMessages;
    _nextMessagePage = cached.nextMessagePage;
    _isLoadingMessages = false;
    _errorMessage = null;
    _restoredMessagesFromCache = true;
    _startInitialBottomAnchor();
  }

  Future<void> _bootstrapMessages() async {
    if (!_restoredMessagesFromCache && widget.chatService == null) {
      final persisted = await _chatService.loadPersistedMessages(_chat.id);
      if (mounted && persisted != null && persisted.isNotEmpty) {
        setState(() {
          _messages = List<Message>.from(persisted);
          _hasMoreMessages = persisted.length >= 50;
          _nextMessagePage = 1;
          _isLoadingMessages = false;
          _errorMessage = null;
          _restoredMessagesFromCache = true;
        });
        _startInitialBottomAnchor();
      }
    }

    if (_restoredMessagesFromCache) {
      // Cached messages are only a fast first paint. Always reconcile them
      // with the authoritative latest page so a bad/missed delta cursor can
      // never strand the room on an old snapshot.
      await _loadInitialMessages(
        showBlockingLoader: false,
        anchorToLatest: true,
      );
      return;
    }
    await _loadInitialMessages();
  }

  Future<void> _loadMessageDelta() async {
    final newestNumericId = _messages
        .map((message) => int.tryParse(message.id))
        .whereType<int>()
        .fold<int?>(null, (current, id) {
      if (current == null || id > current) return id;
      return current;
    });
    if (newestNumericId == null) {
      await _loadInitialMessages(showBlockingLoader: false);
      return;
    }

    try {
      final delta = await _chatService.getMessageDelta(
        _chat.id,
        afterMessageId: newestNumericId.toString(),
      );
      if (!mounted) return;
      final wasNearBottom = _isNearBottom();
      if (delta.isNotEmpty) {
        setState(() {
          final byId = <String, Message>{
            for (final message in _messages) message.id: message,
            for (final message in delta) message.id: message,
          };
          _messages = byId.values.toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        });
        _saveMessageCache();
      }
      if (wasNearBottom) _jumpToBottom();
      unawaited(_markAllRead());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMessages = false;
        _errorMessage = null;
      });
      // The cursor endpoint is an optimization. A transient cursor failure or
      // malformed cached cursor must not leave the visible room permanently
      // stale, so fall back to the authoritative newest page.
      await _loadInitialMessages(showBlockingLoader: false);
    }
  }

  Future<void> _loadInitialMessages({
    bool showBlockingLoader = true,
    bool anchorToLatest = false,
  }) async {
    setState(() {
      if (showBlockingLoader) {
        _isLoadingMessages = true;
      }
      _errorMessage = null;
    });

    try {
      final page = await _chatService.getMessagePage(_chat.id);
      if (!mounted) return;
      final wasNearBottom = _isNearBottom();
      setState(() {
        // 还在发送中/发送失败的本地消息服务器那边没有，整页刷新时要留着，
        // 否则回显或失败提示到来时已经找不到它，消息就无声无息地没了。
        _messages = [
          ...page.messages,
          ..._messages.where(_isLocalUnsentMessage),
        ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _hasMoreMessages = page.hasNext;
        _nextMessagePage = page.currentPage + 1;
        _isLoadingMessages = false;
        _errorMessage = null;
      });
      _saveMessageCache();
      if (showBlockingLoader || anchorToLatest) {
        _startInitialBottomAnchor();
      } else if (wasNearBottom) {
        _jumpToBottom();
      }
      unawaited(_markAllRead());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markViewportMessagesRead();
      });
    } catch (e) {
      if (!mounted) return;
      if (_messages.isNotEmpty) {
        setState(() {
          _isLoadingMessages = false;
          _errorMessage = null;
        });
        return;
      }
      setState(() {
        _errorMessage = e.toString();
        _isLoadingMessages = false;
      });
    }
  }

  /// 别人置顶/取消置顶、自己在别的设备上收藏/取消收藏：实时同步到这个聊天。
  void _handleMessageAction(MessageActionEvent event) {
    if (event.chatRoomId != _chat.id) return;
    if (event.isPinChange) {
      final pins = event.pins;
      if (pins != null) {
        _pinnedMessages.applyServerPins(pins);
      } else {
        unawaited(_pinnedMessages.load());
      }
      return;
    }
    final messageId = event.messageId;
    if (event.isStarChange && messageId != null) {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index < 0) return;
      _setViewState(() {
        _messages[index] = _messages[index]
            .copyWith(starredByMe: event.action == 'star_added');
      });
    }
  }

  Future<void> _connectRealtime() async {
    _messageSubscription =
        _webSocketService.onMessage.listen(_handleRealtimeMessage);
    _messageUpdateSubscription =
        _webSocketService.onMessageUpdated.listen(_handleRealtimeMessageUpdate);
    _messageActionSubscription =
        _webSocketService.onMessageAction.listen(_handleMessageAction);
    _statusSubscription =
        _webSocketService.onStatusChange.listen(_handleRealtimeStatus);
    _typingSubscription =
        _webSocketService.onTyping.listen(_handleRealtimeTyping);
    _callSubscription = _webSocketService.onCallSignal.listen((signal) {
      unawaited(_handleCallSignal(signal));
    });
    // 从"来电"通知点进来的：按正常来电流程弹出接听框。
    final pendingInvite = PendingCallInvite.takeFor(_chat.id);
    if (pendingInvite != null) {
      unawaited(_handleCallSignal(pendingInvite));
    }
    await _webSocketService.connect();
  }

  void _handleScroll() {
    if (_initialBottomAnchorActive) {
      _syncNewMessageButton();
      return;
    }
    if (!_scrollController.hasClients ||
        _isLoadingMessages ||
        _isLoadingOlderMessages ||
        !_hasMoreMessages) {
      _syncNewMessageButton();
      return;
    }
    if (_scrollController.position.pixels <= 80) {
      unawaited(_loadOlderMessages());
    }
    _syncNewMessageButton();
    _markViewportMessagesRead();
  }

  void _syncNewMessageButton() {
    if (!_scrollController.hasClients) return;
    final distanceFromBottom = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    final shouldShow = distanceFromBottom > 200 && _newMessagesBelow > 0;
    if (shouldShow != _showNewMessagesButton ||
        (!shouldShow && _newMessagesBelow != 0)) {
      setState(() {
        _showNewMessagesButton = shouldShow;
        if (!shouldShow && distanceFromBottom <= 80) {
          _newMessagesBelow = 0;
        }
      });
    }
  }

  void _markViewportMessagesRead() {
    final currentUserId = _authService.currentUser?.id;
    if (currentUserId == null || !_scrollController.hasClients) return;
    final screenHeight = MediaQuery.sizeOf(context).height;
    for (final message in _messages) {
      if (message.isFromCurrentUser(currentUserId) ||
          _viewportReadMarkedMessageIds.contains(message.id)) {
        continue;
      }
      final key = _messageKeys[message.id];
      final messageContext = key?.currentContext;
      if (messageContext == null) continue;
      final box = messageContext.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom < 0 || top > screenHeight) continue;
      _viewportReadMarkedMessageIds.add(message.id);
      unawaited(_chatService.markMessageRead(message.id));
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
      _saveMessageCache();
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
    final isOwnMessage =
        message.isFromCurrentUser(_authService.currentUser?.id);
    _upsertMessage(message);
    if (_isNearBottom()) {
      _scrollToBottom();
    } else if (!isOwnMessage) {
      setState(() {
        _newMessagesBelow += 1;
        _showNewMessagesButton = true;
      });
    }
    unawaited(_markAllRead());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _markViewportMessagesRead();
    });
  }

  /// 已有消息被编辑/撤回/删除/状态变化：原地替换，不算新消息、不挪滚动位置。
  /// 本页没加载到的旧消息不插进来（否则历史里会凭空多出一条）。
  void _handleRealtimeMessageUpdate(Message message) {
    if (message.chatRoomId != _chat.id || !mounted) return;
    if (!_messages.any((item) => item.id == message.id)) return;
    _upsertMessage(message);
  }

  void _handleRealtimeStatus(Map<String, dynamic> event) {
    if (!mounted) return;
    // 在线状态事件不带房间号，按用户匹配当前会话里的成员。
    if (event['type'] == 'status') {
      _applyRealtimePresence(event);
      return;
    }
    final roomId = event['chatRoomId']?.toString();
    if (roomId != _chat.id) return;
    if (event['type'] == 'room_membership_removed') {
      _handleRemovedFromRoom(event['reason']?.toString());
      return;
    }
    if (event['type'] == 'read_receipt') {
      _applyRealtimeReadReceipt(event);
      return;
    }
    if (event['type'] == 'room_updated') {
      final chatRoomJson = event['chatRoom'];
      if (chatRoomJson is Map) {
        setState(() {
          _chat = _chat.withRoomUpdate(Map<String, dynamic>.from(chatRoomJson));
        });
      }
      return;
    }
    if (event['type'] == 'poll_voted') {
      setState(() => _pollRefreshEpoch += 1);
      return;
    }
    if (event['type'] != 'reaction_changed') return;
    final messageId = event['messageId']?.toString();
    final reactionsJson = event['reactions'];
    if (messageId == null || reactionsJson is! List) return;
    final reactions = reactionsJson
        .whereType<Map<String, dynamic>>()
        .map(MessageReaction.fromJson)
        .toList();
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index == -1) return;
    _upsertMessage(_messages[index].copyWith(reactions: reactions));
  }

  void _handleRealtimeTyping(Map<String, dynamic> event) {
    final roomId = event['chatRoomId']?.toString();
    if (roomId != _chat.id || !mounted) return;
    final namesValue = event['userNames'];
    if (namesValue is List) {
      // 服务器把输入者本人也算在快照里；自己（包括自己的其他设备）不显示。
      final idsValue = event['userIds'];
      final currentUserId = _authService.currentUser?.id;
      final names = <String>[];
      for (var i = 0; i < namesValue.length; i++) {
        final id = idsValue is List && i < idsValue.length
            ? idsValue[i]?.toString()
            : null;
        if (currentUserId != null && id == currentUserId) continue;
        names.add(namesValue[i].toString());
      }
      _setViewState(() => _typingUserNames = names);
      return;
    }
    final userName =
        event['userName']?.toString() ?? event['username']?.toString();
    final isTyping = event['isTyping'] != false;
    if (userName == null || userName.isEmpty) return;
    final names = List<String>.from(_typingUserNames);
    if (isTyping && !names.contains(userName)) {
      names.add(userName);
    } else if (!isTyping) {
      names.remove(userName);
    }
    _setViewState(() => _typingUserNames = names);
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final distanceFromBottom = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    return distanceFromBottom < 120;
  }

  Future<void> _markAllRead() async {
    try {
      await _chatService.markAllRead(_chat.id);
    } catch (_) {
      // Read receipts are best-effort for this first real-chat slice.
    }
  }

  void _upsertMessage(Message message) {
    if (!mounted) return;
    setState(() {
      // 服务器回显的正式消息替换掉同一 clientMessageId 的本地"发送中"气泡。
      final clientMessageId = message.clientMessageId;
      if (clientMessageId != null && clientMessageId != message.id) {
        _messages.removeWhere((m) => m.id == clientMessageId);
      }
      final index = _messages.indexWhere((m) => m.id == message.id);
      final merged = _withReplyQuote(
        message,
        previous: index == -1 ? null : _messages[index],
      );
      if (index == -1) {
        _messages.add(merged);
      } else {
        _messages[index] = merged;
      }
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
    _saveMessageCache();
  }

  /// 消息只带了 replyToMessageId 而没带被引用的内容时（老服务器、缓存），
  /// 用本地已有的那条补上，不要让气泡误显示"原消息已删除"。
  Message _withReplyQuote(Message message, {Message? previous}) {
    if (message.replyToMessage != null) return message;
    final replyId = message.replyToMessageId ?? message.replyToId;
    if (replyId == null || replyId.isEmpty) return message;
    if (previous?.replyToMessage?.id == replyId) {
      return message.copyWith(replyToMessage: previous!.replyToMessage);
    }
    for (final candidate in _messages) {
      if (candidate.id == replyId) {
        return message.copyWith(replyToMessage: candidate);
      }
    }
    return message;
  }

  static bool _isLocalUnsentMessage(Message message) =>
      message.clientMessageId != null &&
      message.id == message.clientMessageId &&
      (message.status == MessageStatus.sending ||
          message.status == MessageStatus.failed);

  void _scrollToBottom() {
    _scheduleScrollToBottom(animated: true);
  }

  void _jumpToBottom() {
    _scheduleScrollToBottom(animated: false);
  }

  void _startInitialBottomAnchor() {
    final generation = ++_initialBottomAnchorGeneration;
    _initialBottomAnchorTimer?.cancel();
    _initialBottomAnchorActive = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _initialBottomAnchorGeneration) return;
      _beginInitialBottomAnchorPasses(generation);
    });
  }

  void _cancelInitialBottomAnchor() {
    _initialBottomAnchorGeneration += 1;
    _initialBottomAnchorTimer?.cancel();
    _initialBottomAnchorTimer = null;
    _initialBottomAnchorActive = false;
  }

  void _beginInitialBottomAnchorPasses(int generation) {
    if (!_snapInitialHistoryToBottom(generation)) return;

    var ticks = 0;
    var stablePasses = 0;
    var previousExtent = _scrollController.position.maxScrollExtent;
    _initialBottomAnchorTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (timer) {
        ticks += 1;
        if (!mounted || generation != _initialBottomAnchorGeneration) {
          timer.cancel();
          return;
        }
        if (!_snapInitialHistoryToBottom(generation)) {
          timer.cancel();
          return;
        }

        final extent = _scrollController.position.maxScrollExtent;
        if ((extent - previousExtent).abs() <= 1) {
          stablePasses += 1;
        } else {
          stablePasses = 0;
        }
        previousExtent = extent;

        if (ticks >= 75 || (ticks >= 25 && stablePasses >= 6)) {
          timer.cancel();
          _initialBottomAnchorTimer = null;
          _initialBottomAnchorActive = false;
        }
      },
    );
  }

  bool _snapInitialHistoryToBottom(int generation) {
    if (!mounted ||
        generation != _initialBottomAnchorGeneration ||
        !_scrollController.hasClients) {
      return false;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions || !position.maxScrollExtent.isFinite) {
      return false;
    }
    final extent = position.maxScrollExtent;
    _scrollController.jumpTo(extent);
    if (extent <= 0) {
      _initialBottomAnchorActive = false;
      return false;
    }
    return true;
  }

  void _scheduleScrollToBottom({
    required bool animated,
    int attempts = 5,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) {
        if (attempts > 0) {
          _scheduleScrollToBottom(animated: animated, attempts: attempts - 1);
        }
        return;
      }
      final maxScrollExtent = position.maxScrollExtent;
      if (!maxScrollExtent.isFinite) return;
      if (animated) {
        _scrollController.animateTo(
          maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(maxScrollExtent);
      }
      final remainingDistance = _scrollController.position.maxScrollExtent -
          _scrollController.position.pixels;
      if (attempts > 0 && remainingDistance.abs() > 2) {
        _scheduleScrollToBottom(animated: false, attempts: attempts - 1);
      }
    });
  }

  void _saveMessageCache() {
    ChatScreen._messageCache[_chat.id] = _CachedChatMessages(
      messages: List<Message>.from(_messages),
      hasMoreMessages: _hasMoreMessages,
      nextMessagePage: _nextMessagePage,
    );
    unawaited(_chatService.persistMessages(_chat.id, _messages));
    _syncAgentClientToolState();
  }

  void _syncAgentClientToolState() {
    if (!_didInitialize) return;
    final tabName = switch (_desktopInfoPanelTab) {
      0 => 'members',
      1 => 'files',
      _ => 'bots',
    };
    AgentClientToolState().updateRoom(
      roomId: int.tryParse(_chat.id),
      muted: _chat.isMuted,
      pinnedToTop: _chat.isPinned,
      notificationLevel: _chat.isMuted ? 'none' : 'all',
      messages: _messages,
      rightSidebarOpen: !_desktopInfoPanelCollapsed,
      rightSidebarTab: tabName,
      membersPanelOpen:
          !_desktopInfoPanelCollapsed && _desktopInfoPanelTab == 0,
      settingsOpen: false,
    );
  }

  Color? _parseAnonymousColor(String? value) {
    if (value == null || !value.startsWith('#')) return null;
    final hex = value.substring(1);
    if (hex.length != 6 && hex.length != 8) return null;
    final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  String get _effectiveBackgroundPreset {
    return _appSettings.chatBackgroundPreset;
  }

  String? get _effectiveBackgroundUrl {
    final userUrl = _appSettings.chatBackgroundCustomUrl?.trim();
    return userUrl == null || userUrl.isEmpty ? null : userUrl;
  }

  @override
  Widget build(BuildContext context) {
    if (_isResolvingRouteChat || _routeChatError != null) {
      return _buildRouteResolutionScaffold();
    }

    if (PMBreakpoints.isDesktop(context)) {
      return _buildDesktopChatScaffold();
    }

    return _buildDropPasteTarget(Scaffold(
      appBar: AppBar(
        title: Tooltip(
          message: _chat.type == ChatType.group ? '群信息 / 设置' : '聊天信息',
          child: InkWell(
            onTap: _openRoomSettings,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Stack(
                    children: [
                      _buildChatAvatar(),
                      if (_chat.type == ChatType.private &&
                          _privatePeer()?.onlineStatus == OnlineStatus.online)
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
                          _displayChatTitle(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_chat.type == ChatType.private)
                          Text(
                            _chatSubtitle(),
                            style: TextStyle(
                              fontSize: 12,
                              color: _privatePeer()?.onlineStatus ==
                                      OnlineStatus.online
                                  ? AppColors.online
                                  : AppColors.textSecondary,
                            ),
                          )
                        else if (_chat.type == ChatType.group)
                          Text(
                            '${_chat.effectiveMemberCount}人',
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
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '语音通话',
            icon: const PMSymbolIcon(PMSymbol.call),
            onPressed: () => _startCall(CallMediaKind.audio),
          ),
          IconButton(
            tooltip: '视频通话',
            icon: const PMSymbolIcon(PMSymbol.video),
            onPressed: () => _startCall(CallMediaKind.video),
          ),
          IconButton(
            tooltip: _chat.type == ChatType.group ? '群设置' : '聊天信息',
            icon: const PMSymbolIcon(PMSymbol.settings),
            onPressed: _openRoomSettings,
          ),
          IconButton(
            tooltip: '更多',
            icon: const PMSymbolIcon(PMSymbol.more),
            onPressed: () {
              _showChatOptions();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCallPanel(),
          _buildAnonymousBanner(),
          _buildAnnouncementBanner(),
          _buildPinnedMessagesBar(),
          Expanded(
            child: _buildMessageArea(),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              border: const Border(
                top: BorderSide(color: AppColors.borderLight),
              ),
              boxShadow: const [AppColors.appBarShadow],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPendingAttachmentsStrip(),
                  _buildReplyPreviewStrip(),
                  _buildMentionPickerPanel(),
                  _buildAnonymousIdentityHint(),
                  _buildVoiceRecordingStrip(),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 400) {
                        return _buildCompactMobileInputRow();
                      }
                      return _buildFullMobileInputRow();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildFullMobileInputRow() {
    return Row(
      children: [
        _buildInputIconButton(
          symbol: PMSymbol.emoji,
          onPressed: _showEmojiPanel,
          tooltip: '表情',
        ),
        _buildInputIconButton(
          symbol: PMSymbol.sticker,
          onPressed: _showStickerPanel,
          tooltip: '贴纸',
        ),
        _buildInputIconButton(
          symbol: PMSymbol.terminal,
          onPressed: _insertSystemAgentMention,
          tooltip: '插入 AI 助手',
        ),
        _buildInputIconButton(
          symbol: PMSymbol.add,
          onPressed: _showInputOptions,
          tooltip: '附件',
        ),
        _buildAnonymousToggle(),
        _buildComposerTextField(),
        const SizedBox(width: 8),
        _buildComposerSubmitButton(),
      ],
    );
  }

  Widget _buildCompactMobileInputRow() {
    return Row(
      children: [
        _buildInputIconButton(
          symbol: PMSymbol.add,
          onPressed: _showInputOptions,
          tooltip: '其它操作',
        ),
        _buildAnonymousToggle(compact: true),
        _buildComposerTextField(),
        const SizedBox(width: 8),
        _buildComposerSubmitButton(),
      ],
    );
  }

  Widget _buildAnonymousToggle({bool compact = false}) {
    return AnonymousToggleButton(
      chatRoomId: int.tryParse(_chat.id) ?? 0,
      anonymousEnabled: _chat.anonymousEnabled,
      perMessageMode: _anonymousPerMessageMode,
      nextMessageAnonymous: _anonymousNextMessage,
      onPerMessageModeChanged: _setAnonymousMode,
      currentIdentity: _anonymousIdentity,
      compact: compact,
      onAnonymousChanged: (identity) {
        _applyAnonymousIdentity(identity);
      },
    );
  }

  Widget _buildComposerTextField() {
    return Expanded(
      child: Container(
        key: const ValueKey('chat-composer-text-field-shell'),
        decoration: BoxDecoration(
          color: AppColors.cloud,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: _buildMessageTextField(
          hintText: '输入消息...',
        ),
      ),
    );
  }

  Widget _buildComposerSubmitButton() {
    return _isTyping || _hasPendingAttachments
        ? _buildInputIconButton(
            symbol: PMSymbol.send,
            onPressed: _sendMessage,
            tooltip: '发送',
            filled: true,
          )
        : _buildInputIconButton(
            symbol: _isRecordingVoice ? PMSymbol.send : PMSymbol.mic,
            onPressed: _toggleVoiceRecording,
            tooltip: _isRecordingVoice ? '停止并发送语音' : '录音说话',
            filled: _isRecordingVoice,
          );
  }

  AttachmentType _attachmentTypeForMessage(Message message) {
    if (message.isImageMessage) return AttachmentType.image;
    if (message.isVideoMessage) return AttachmentType.video;
    if (message.isVoiceMessage) return AttachmentType.voice;
    if (message.isLocationMessage) return AttachmentType.location;
    return AttachmentType.file;
  }
}
