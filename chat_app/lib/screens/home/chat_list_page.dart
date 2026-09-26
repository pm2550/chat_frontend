import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/chat_data_service.dart';
import '../../services/contact_data_service.dart';
import '../../services/desktop_notification_service.dart';
import '../../services/native_push_service.dart';
import '../../services/user_profile_service.dart';
import '../../services/websocket_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_welcome_art.dart';
import '../../widgets/pm_responsive.dart';
import '../chat/chat_screen.dart' show ChatScreenArguments;
import 'hidden_chats_screen.dart';

part 'sub/chat_list_data.dart';
part 'sub/chat_list_actions_1.dart';
part 'sub/chat_list_actions_2.dart';
part 'sub/chat_list_view.dart';

enum _ChatRoomMenuAction { togglePin, clearHistory, hide, block }

class ChatListPage extends StatefulWidget {
  const ChatListPage({
    super.key,
    this.chatService,
    this.realtimeService,
    this.notificationService,
    this.profileService,
    this.currentUserId,
    this.contactService,
    this.compact = false,
    this.selectedChatId,
    this.onOpenChat,
  });

  final bool compact;
  final String? selectedChatId;
  final Future<void> Function(ChatScreenArguments)? onOpenChat;

  final ChatDataService? chatService;
  final ContactDataService? contactService;
  final ChatRealtimeService? realtimeService;
  final DesktopNotificationService? notificationService;

  /// 用来读取"消息通知"开关；测试里可注入。
  final UserProfileService? profileService;
  final String? currentUserId;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage>
    with AutomaticKeepAliveClientMixin<ChatListPage>, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final ChatDataService _chatService;
  late final ChatRealtimeService _realtimeService;
  late final DesktopNotificationService _notificationService;
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<Message>? _messageUpdateSubscription;
  StreamSubscription<Map<String, dynamic>>? _statusSubscription;
  String _searchQuery = '';
  List<Chat> _chats = [];
  List<_MentionHit> _mentionHits = [];
  bool _isLoading = true;
  bool _showMentionsOnly = false;
  bool _unreadOnly = false;
  bool _isLoadingMentions = false;
  bool _isShowingCachedData = false;
  String? _errorMessage;
  String? _mentionErrorMessage;
  bool _wasBackgrounded = false;
  bool _isRefreshingAfterResume = false;

  // 搜索：本地过滤会话 + 好友，并在服务器上搜索全部聊天里的消息。
  static const Duration _messageSearchDebounce = Duration(milliseconds: 350);
  Timer? _messageSearchTimer;
  int _messageSearchGeneration = 0;
  List<Message> _messageHits = const [];
  bool _isSearchingMessages = false;
  String? _messageSearchError;
  List<User>? _friends;
  bool _isLoadingFriends = false;
  String? _openingSearchTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timeago.setLocaleMessages('zh', timeago.ZhCnMessages());
    _chatService = widget.chatService ?? ChatDataService();
    _realtimeService = widget.realtimeService ?? WebSocketService();
    _notificationService =
        widget.notificationService ?? DesktopNotificationService();
    final cachedChats = widget.chatService == null
        ? ChatDataService.cachedChatRoomsSnapshot()
        : null;
    if (cachedChats != null) {
      _chats = cachedChats;
      _isLoading = false;
    }
    _requestMobileNotificationPermission();
    _loadNotificationPreference();
    unawaited(_bootstrapChats(cachedChats != null));
    _connectRealtime();
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

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.compact || !PMBreakpoints.isDesktop(context)) {
      return Scaffold(
          backgroundColor: AppColors.surface, body: _buildConversationList());
    }
    return Scaffold(
        body: Row(children: [
      SizedBox(
          key: const ValueKey('desktop-conversation-list'),
          width: PMDesktopLayout.conversationListWidth(context),
          child: _buildConversationList()),
      const VerticalDivider(width: 1),
      Expanded(
          child: PMChatPattern(
              child: Center(
                  child: SingleChildScrollView(
        padding: const EdgeInsets.all(PMSpacing.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const PMWelcomeArt(size: 248),
          const SizedBox(height: PMSpacing.xl),
          const Text('从一句问候开始',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: PMSpacing.m),
          const Text('选一段对话，继续分享生活中的小事。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          const SizedBox(height: PMSpacing.xxl),
          Wrap(
              spacing: PMSpacing.m,
              runSpacing: PMSpacing.m,
              alignment: WrapAlignment.center,
              children: [
                PMButton(
                    label: '找朋友聊聊',
                    icon: Icons.person_add_alt_1_outlined,
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/home/contacts')),
                PMButton(
                    label: '探索 AI 助手',
                    icon: Icons.auto_awesome_outlined,
                    variant: PMButtonVariant.secondary,
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/home/ai/bots')),
              ]),
        ]),
      )))),
    ]));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSubscription?.cancel();
    _messageUpdateSubscription?.cancel();
    _statusSubscription?.cancel();
    _messageSearchTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _setViewState(VoidCallback change) {
    if (mounted) setState(change);
  }
}

class _MentionHit {
  const _MentionHit({
    required this.chat,
    required this.message,
  });

  final Chat chat;
  final Message message;
}
