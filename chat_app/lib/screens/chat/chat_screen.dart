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
import '../../services/chat_upload.dart';
import '../../services/memory_service.dart';
import '../../services/slash_command_parser.dart';
import '../../services/pending_call_invite.dart';
import '../../services/chat_call_service.dart';
import '../../services/contact_data_service.dart';
import '../../services/encryption_service.dart';
import '../../services/chat_drop_paste.dart'
    if (dart.library.js_interop) '../../services/chat_drop_paste_web.dart';
import '../../services/file_save.dart' as file_save;
import '../../services/image_upload/image_upload_preparer.dart';
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
import '../../widgets/e2ee_widgets.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_navigation_rail.dart';
import '../home/chat_list_page.dart';
import '../../widgets/pm_responsive.dart';
import '../../widgets/sticker_tile.dart';
import '../../widgets/typing_indicator.dart';
import 'chat_file_center_screen.dart';
import 'chat_room_bot_config_screen.dart';
import 'chat_room_settings_screen.dart';
import 'pinned_messages.dart';
import 'sticker_pack_upload_screen.dart';

part 'sub/message_composer_2.dart';
part 'sub/message_composer_3.dart';

part 'sub/chat_session_data.dart';
part 'sub/chat_session_actions.dart';
part 'sub/chat_session_view.dart';

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
part 'sub/outgoing_uploads.dart';
part 'sub/realtime_sync.dart';
part 'sub/e2ee_chat.dart';
part 'sub/slash_commands.dart';

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
    this.cameraPicker,
    this.filePicker,
    this.fileSaver,
    this.encryptionService,
    this.imageUploadPreparer,
  });

  final ChatDataService? chatService;
  final WebSocketService? webSocketService;
  final AuthService? authService;
  final UserProfileService? profileService;
  final ChatCallService? callService;
  final ContactDataService? contactService;
  final BotService? botService;
  final ChatAttachmentPicker? imagePicker;
  final ChatAttachmentPicker? cameraPicker;
  final ChatAttachmentPicker? filePicker;
  final file_save.FileSaver? fileSaver;
  final EncryptionService? encryptionService;

  /// 发图前的压缩/删元数据（测试注入假的，避免真的解码）。
  final ImageUploadPreparer? imageUploadPreparer;

  /// 测试用：强制打开/关闭网页端"发送栏变动后重新聚焦输入框"的处理（默认只在网页上开）。
  @visibleForTesting
  static bool? debugRepairComposerDomFocus;

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
  final GlobalKey<ScaffoldState> _desktopScaffoldKey =
      GlobalKey<ScaffoldState>();
  late final ChatDataService _chatService;
  late final WebSocketService _webSocketService;
  late final AuthService _authService;
  late final ChatCallService _callService;
  late final AnonymousService _anonymousService;
  late final BotService _botService;
  late final MemoryService _memoryService;
  late final UserProfileService _profileService;
  late final ContactDataService _contactService;
  late final EncryptionService _e2ee;
  E2eeRoomState _e2eeRoom = E2eeRoomState.none;
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
  bool _isRecordingVoice = false;
  bool _isStoppingVoice = false;
  Duration _voiceRecordingDuration = Duration.zero;
  bool _isLoadingRoomBots = false;
  bool _desktopInfoPanelCollapsed = true;
  int _desktopInfoPanelTab = 0;
  int _newMessagesBelow = 0;
  bool _showNewMessagesButton = false;
  List<User> _mentionMembers = const [];
  List<User> _mentionSuggestions = const [];
  int _mentionSelectedIndex = 0;
  int? _mentionStartIndex;
  bool _isLoadingMentionMembers = false;
  final _SlashPanelState _slashPanel = _SlashPanelState();
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

  /// 发送栏里的图片这次按"原图"发（只删元数据、不压缩）。每次发送后恢复成压缩。
  bool _pendingSendOriginal = false;
  bool _composerFocusRepairScheduled = false;
  late final ImageUploadPreparer _imagePreparer;

  /// 正在上传/上传失败的附件，按占位消息 id（= clientMessageId）索引。
  final Map<String, _OutgoingUpload> _outgoingUploads = {};
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
    _e2ee = widget.encryptionService ?? EncryptionService();
    _imagePreparer = widget.imageUploadPreparer ?? ImageUploadPreparer.shared;
    _e2ee.addListener(_handleE2eeChanged);
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
      _routeChatError = '没有找到这段对话，请返回消息列表重新打开。';
      return;
    }

    _isResolvingRouteChat = true;
    _isLoadingMessages = false;
    unawaited(_loadChatFromRoute(chatRoomId));
  }

  @override
  void dispose() {
    _e2ee.removeListener(_handleE2eeChanged);
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
    for (final upload in _outgoingUploads.values) {
      upload.stopWatching();
    }
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

  void _setViewState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    if (_didInitialize) {
      _syncAgentClientToolState();
    }
  }

  static bool _isLocalUnsentMessage(Message message) =>
      message.clientMessageId != null &&
      message.id == message.clientMessageId &&
      (message.status == MessageStatus.sending ||
          message.status == MessageStatus.failed);

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
        leadingWidth: 48,
        titleSpacing: 8,
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayChatTitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_chat.type == ChatType.private)
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _chatSubtitle(),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _privatePeer()?.onlineStatus ==
                                            OnlineStatus.online
                                        ? AppColors.online
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              if (_e2eeRoom.encrypts) ...[
                                const SizedBox(width: 8),
                                E2eeHeaderBadge(state: _e2eeRoom),
                              ],
                            ],
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
          if (MediaQuery.sizeOf(context).width >= 400)
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
          _buildE2eeNotice(),
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
                  _buildSlashCommandPanel(),
                  _buildAnonymousIdentityHint(),
                  _buildVoiceRecordingStrip(),
                  _buildMobileComposer(),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }
}
