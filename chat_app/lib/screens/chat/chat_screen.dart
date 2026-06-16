import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/call_state.dart';
import '../../models/chat.dart';
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
import '../../services/chat_call_service.dart';
import '../../services/contact_data_service.dart';
import '../../services/chat_drop_paste.dart'
    if (dart.library.js_interop) '../../services/chat_drop_paste_web.dart';
import '../../services/file_save.dart' as file_save;
import '../../services/platform_chat_file_picker.dart'
    if (dart.library.js_interop) '../../services/platform_chat_file_picker_web.dart';
import '../../services/user_profile_service.dart';
import '../../services/websocket_service.dart';
import 'sub/memory_panel.dart';
import '../../widgets/anonymous_toggle_button.dart';
import '../../widgets/anonymous_identity_hint.dart';
import '../../widgets/call_grid_view.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import '../../widgets/typing_indicator.dart';
import 'chat_file_center_screen.dart';
import 'chat_room_bot_config_screen.dart';
import 'chat_room_settings_screen.dart';
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

typedef ChatAttachmentPicker = Future<PickedChatFile?> Function();

class ChatScreenArguments {
  const ChatScreenArguments({
    required this.chat,
    this.startCall,
  });

  final Chat chat;
  final CallMediaKind? startCall;
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

  @visibleForTesting
  static void clearMessageCacheForTesting() {
    _messageCache.clear();
  }

  static final Map<String, _CachedChatMessages> _messageCache = {};

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
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
  StreamSubscription<Map<String, dynamic>>? _statusSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;
  StreamSubscription<Map<String, dynamic>>? _callSubscription;
  Timer? _messageHighlightTimer;

  List<Message> _messages = [];
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<String, Future<LinkPreview?>> _linkPreviewFutures = {};
  final Set<String> _viewportReadMarkedMessageIds = {};
  final Set<String> _friendUserIds = {};
  final Set<String> _pendingFriendRequestUserIds = {};
  final Set<String> _sendingFriendRequestUserIds = {};
  int _pollRefreshEpoch = 0;
  List<BotConfig> _roomBots = [];
  bool _isTyping = false;
  bool _isLoadingMessages = true;
  bool _isLoadingOlderMessages = false;
  bool _hasMoreMessages = false;
  bool _isSendingAttachment = false;
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
  bool _isResolvingRouteChat = false;
  String? _routeChatIdToResolve;
  String? _routeChatError;
  bool _showAnnouncementBanner = false;
  String? _announcementSeenKey;
  ChatDropPasteController? _dropPasteController;
  bool _isDragUploadActive = false;
  int _dragUploadFileCount = 0;
  UserAppSettings _appSettings = const UserAppSettings();
  bool _restoredMessagesFromCache = false;

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
    _scrollController.addListener(_handleScroll);
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
  }) {
    _chat = chat;
    _pendingStartCall = startCall;
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
    _loadInitialMessages(showBlockingLoader: !_restoredMessagesFromCache);
    unawaited(_loadMentionMembers());
    _loadRoomBots();
    _loadFriendshipState();
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
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _typingSubscription?.cancel();
    _callSubscription?.cancel();
    _messageHighlightTimer?.cancel();
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
    _jumpToBottom();
  }

  Future<void> _loadInitialMessages({bool showBlockingLoader = true}) async {
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
        _messages = List<Message>.from(page.messages);
        _hasMoreMessages = page.hasNext;
        _nextMessagePage = page.currentPage + 1;
        _isLoadingMessages = false;
        _errorMessage = null;
      });
      _saveMessageCache();
      if (showBlockingLoader || wasNearBottom) {
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

  Future<void> _connectRealtime() async {
    _messageSubscription =
        _webSocketService.onMessage.listen(_handleRealtimeMessage);
    _statusSubscription =
        _webSocketService.onStatusChange.listen(_handleRealtimeStatus);
    _typingSubscription =
        _webSocketService.onTyping.listen(_handleRealtimeTyping);
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
      if (message.senderId == currentUserId ||
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

  void _handleRealtimeStatus(Map<String, dynamic> event) {
    final roomId = event['chatRoomId']?.toString();
    if (roomId != _chat.id || !mounted) return;
    if (event['type'] == 'room_updated') {
      final chatRoomJson = event['chatRoom'];
      if (chatRoomJson is Map<String, dynamic>) {
        final updated = Chat.fromJson(chatRoomJson);
        setState(() {
          _chat = _chat.copyWith(
            name: updated.name,
            description: updated.description,
            announcement: updated.announcement,
            avatarUrl: updated.avatarUrl,
            anonymousEnabled: updated.anonymousEnabled,
            anonymousTheme: updated.anonymousTheme,
            customBackgroundPreset: updated.customBackgroundPreset,
            customBackgroundUrl: updated.customBackgroundUrl,
          );
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
      _setViewState(() {
        _typingUserNames = namesValue.map((item) => item.toString()).toList();
      });
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
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index == -1) {
        _messages.add(message);
      } else {
        _messages[index] = message;
      }
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
    _saveMessageCache();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      final maxScrollExtent = position.maxScrollExtent;
      if (!maxScrollExtent.isFinite) return;
      _scrollController.animateTo(
        maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      final maxScrollExtent = position.maxScrollExtent;
      if (!maxScrollExtent.isFinite) return;
      _scrollController.jumpTo(maxScrollExtent);
    });
  }

  void _saveMessageCache() {
    ChatScreen._messageCache[_chat.id] = _CachedChatMessages(
      messages: List<Message>.from(_messages),
      hasMoreMessages: _hasMoreMessages,
      nextMessagePage: _nextMessagePage,
    );
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
    final roomPreset = _chat.customBackgroundPreset?.trim();
    if (roomPreset != null && roomPreset.isNotEmpty) return roomPreset;
    return _appSettings.chatBackgroundPreset;
  }

  String? get _effectiveBackgroundUrl {
    final roomUrl = _chat.customBackgroundUrl?.trim();
    if (roomUrl != null && roomUrl.isNotEmpty) return roomUrl;
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
                            _privatePeer()?.onlineStatus == OnlineStatus.online
                                ? '在线'
                                : _privatePeer()?.lastSeen != null
                                    ? '最后在线 ${timeago.format(_privatePeer()!.lastSeen!, locale: 'zh')}'
                                    : '离线',
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
                  _buildReplyPreviewStrip(),
                  _buildMentionPickerPanel(),
                  _buildAnonymousIdentityHint(),
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
    return _isTyping
        ? _buildInputIconButton(
            symbol: PMSymbol.send,
            onPressed: _sendMessage,
            tooltip: '发送',
            filled: true,
          )
        : _buildInputIconButton(
            symbol: PMSymbol.mic,
            onPressed: _pickAndSendVoiceFile,
            tooltip: '语音消息',
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
