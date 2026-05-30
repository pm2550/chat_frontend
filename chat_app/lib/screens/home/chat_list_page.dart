import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../constants/api_constants.dart';
import '../../constants/app_brand.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/chat_data_service.dart';
import '../../services/desktop_notification_service.dart';
import '../../services/websocket_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({
    super.key,
    this.chatService,
    this.realtimeService,
    this.notificationService,
    this.currentUserId,
  });

  final ChatDataService? chatService;
  final ChatRealtimeService? realtimeService;
  final DesktopNotificationService? notificationService;
  final String? currentUserId;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final ChatDataService _chatService;
  late final ChatRealtimeService _realtimeService;
  late final DesktopNotificationService _notificationService;
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _statusSubscription;
  String _searchQuery = '';
  List<Chat> _chats = [];
  List<_MentionHit> _mentionHits = [];
  bool _isLoading = true;
  bool _showMentionsOnly = false;
  bool _isLoadingMentions = false;
  String? _errorMessage;
  String? _mentionErrorMessage;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('zh', timeago.ZhMessages());
    _chatService = widget.chatService ?? ChatDataService();
    _realtimeService = widget.realtimeService ?? WebSocketService();
    _notificationService =
        widget.notificationService ?? DesktopNotificationService();
    _loadChats();
    _connectRealtime();
  }

  Future<void> _loadChats({bool showLoading = true}) async {
    if (mounted && showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final chats = await _chatService.getChatRooms();
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _isLoading = false;
        _errorMessage = null;
      });
      _syncDesktopUnreadBadge();
      if (_showMentionsOnly) {
        unawaited(_loadMentionHits());
      }
    } catch (e) {
      if (!mounted) return;
      if (_isAuthenticationError(e)) {
        await AuthService().clearLocalSession();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登录状态已过期，请重新登录'),
            backgroundColor: AppColors.error,
          ),
        );
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
        return;
      }
      if (!showLoading) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _connectRealtime() async {
    _messageSubscription =
        _realtimeService.onMessage.listen(_handleRealtimeMessage);
    _statusSubscription =
        _realtimeService.onStatusChange.listen(_handleStatusChange);
    await _realtimeService.connect();
  }

  void _handleRealtimeMessage(Message message) {
    if (!mounted || message.chatRoomId.isEmpty) return;

    final index = _chats.indexWhere((chat) => chat.id == message.chatRoomId);
    if (index == -1) {
      unawaited(_loadChats(showLoading: false));
      return;
    }

    final currentUserId = _currentUserId;
    final isIncoming =
        currentUserId == null || message.senderId != currentUserId;
    final original = _chats[index];
    final currentLastMessage = original.lastMessage;
    final replacesLastMessage = currentLastMessage?.id == message.id;
    final shouldPromoteToLast = replacesLastMessage ||
        currentLastMessage == null ||
        !message.timestamp.isBefore(currentLastMessage.timestamp);
    final nextUnreadCount =
        isIncoming && !message.isRemoved && !replacesLastMessage
            ? original.unreadCount + 1
            : original.unreadCount;

    setState(() {
      _chats[index] = original.copyWith(
        lastMessage: shouldPromoteToLast ? message : currentLastMessage,
        unreadCount: nextUnreadCount,
        updatedAt: shouldPromoteToLast ? message.timestamp : original.updatedAt,
      );
      if (_showMentionsOnly && message.mentionsUser(currentUserId)) {
        _mentionHits.insert(
            0, _MentionHit(chat: _chats[index], message: message));
      }
      _sortChatsInPlace();
    });
    _syncDesktopUnreadBadge();

    final mentionsMe = message.mentionsUser(currentUserId);
    if (isIncoming && !message.isRemoved && (!original.isMuted || mentionsMe)) {
      _showIncomingMessageNotice(
          _chats.firstWhere(
            (chat) => chat.id == message.chatRoomId,
            orElse: () => original,
          ),
          mentionOverride: mentionsMe);
    }
  }

  void _handleStatusChange(Map<String, dynamic> event) {
    if (!mounted) return;
    final userId = event['userId']?.toString();
    final statusValue = event['onlineStatus'] ?? event['online_status'];
    if (userId == null || statusValue == null) return;

    final status = OnlineStatus.values.firstWhere(
      (value) =>
          value.name.toUpperCase() == statusValue.toString().toUpperCase(),
      orElse: () => OnlineStatus.offline,
    );

    var changed = false;
    final updatedChats = _chats.map((chat) {
      var chatChanged = false;
      final updatedParticipants = chat.participants.map((user) {
        if (user.id != userId) return user;
        chatChanged = true;
        changed = true;
        return user.copyWith(onlineStatus: status);
      }).toList();
      return chatChanged
          ? chat.copyWith(participants: updatedParticipants)
          : chat;
    }).toList();

    if (changed) {
      setState(() {
        _chats = updatedChats;
      });
    }
  }

  String? get _currentUserId =>
      widget.currentUserId ?? AuthService().currentUser?.id;

  bool _isAuthenticationError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('登录状态已过期') ||
        message.contains('unauthorized') ||
        message.contains('jwt') ||
        message.contains('token') ||
        message.contains('authentication');
  }

  void _sortChatsInPlace() {
    _chats.sort((a, b) {
      final aTime = a.lastMessage?.timestamp ?? a.updatedAt ?? a.createdAt;
      final bTime = b.lastMessage?.timestamp ?? b.updatedAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
  }

  void _syncDesktopUnreadBadge() {
    final totalUnread = _chats.fold<int>(
      0,
      (sum, chat) => sum + chat.unreadCount,
    );
    _notificationService.syncUnreadCount(totalUnread);
  }

  Future<void> _requestDesktopNotifications() async {
    final enabled = await _notificationService.requestPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(enabled ? '桌面通知已开启' : '浏览器没有允许桌面通知'),
        backgroundColor: enabled ? AppColors.success : AppColors.warning,
      ),
    );
  }

  void _showIncomingMessageNotice(
    Chat chat, {
    bool mentionOverride = false,
  }) {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final text = chat.lastMessage?.resolvedFileLabel ?? '收到新消息';
    _notificationService.notifyIncomingMessage(
      chatName: chat.name,
      body: text,
      muted: chat.isMuted && !mentionOverride,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${chat.name}: $text'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<Chat> get _filteredChats {
    if (_searchQuery.isEmpty) {
      return _chats;
    }
    return _chats.where((chat) {
      final lastMessageText = chat.lastMessage?.resolvedFileLabel ?? '';
      return chat.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          lastMessageText.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _toggleMentionsOnly() async {
    setState(() {
      _showMentionsOnly = !_showMentionsOnly;
      _mentionErrorMessage = null;
    });
    if (_showMentionsOnly && _mentionHits.isEmpty) {
      await _loadMentionHits();
    }
  }

  Future<void> _loadMentionHits() async {
    if (!mounted) return;
    setState(() {
      _isLoadingMentions = true;
      _mentionErrorMessage = null;
    });

    try {
      final hits = <_MentionHit>[];
      for (final chat in _chats) {
        final page = await _chatService.getMentionedMessages(chat.id);
        hits.addAll(page.messages.map((message) => _MentionHit(
              chat: chat,
              message: message,
            )));
      }
      hits.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
      if (!mounted) return;
      setState(() {
        _mentionHits = hits;
        _isLoadingMentions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mentionErrorMessage = e.toString();
        _isLoadingMentions = false;
      });
    }
  }

  void _focusSearch() {
    _searchFocusNode.requestFocus();
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新聊天列表'),
              onTap: () {
                Navigator.pop(context);
                _loadChats();
              },
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('搜索聊天'),
              onTap: () {
                Navigator.pop(context);
                _focusSearch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('清除搜索'),
              onTap: () {
                Navigator.pop(context);
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (PMBreakpoints.isDesktop(context)) {
      return _buildDesktopScaffold();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            PMChatMark(size: 34),
            SizedBox(width: 10),
            Text(AppBrand.name),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _focusSearch,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMoreMenu,
          ),
        ],
      ),
      body: PMChatPattern(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: const [AppColors.cardShadow],
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: '搜索消息、群聊或联系人',
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.textSecondary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PMChip(
                  label: '@我',
                  icon: Icons.alternate_email,
                  selected: _showMentionsOnly,
                  color: AppColors.primary,
                  onTap: () => unawaited(_toggleMentionsOnly()),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _loadChats,
                          child: _showMentionsOnly
                              ? _buildMentionHitsList()
                              : _filteredChats.isEmpty
                                  ? ListView(
                                      children: [
                                        SizedBox(
                                          height: MediaQuery.of(context)
                                                  .size
                                                  .height *
                                              0.55,
                                          child: _buildEmptyState(),
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      padding:
                                          const EdgeInsets.only(bottom: 14),
                                      itemCount: _filteredChats.length,
                                      itemBuilder: (context, index) {
                                        final chat = _filteredChats[index];
                                        return _buildChatItem(chat);
                                      },
                                    ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopScaffold() {
    final chats = _filteredChats;
    final unreadTotal = _chats.fold<int>(
      0,
      (sum, chat) => sum + chat.unreadCount,
    );
    final pinnedCount = _chats.where((chat) => chat.isPinned).length;

    return Scaffold(
      body: PMChatPattern(
        dense: true,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                PMDesktopHeader(
                  title: '消息工作台',
                  subtitle: '管理群聊、私聊、文件消息和实时协作上下文',
                  icon: Icons.forum,
                  actions: [
                    _buildDesktopHeaderButton(
                      icon: Icons.search,
                      label: '搜索',
                      onTap: _focusSearch,
                    ),
                    const SizedBox(width: 10),
                    _buildDesktopHeaderButton(
                      icon: Icons.notifications_active,
                      label: '通知',
                      onTap: _requestDesktopNotifications,
                    ),
                    const SizedBox(width: 10),
                    _buildDesktopHeaderButton(
                      icon: Icons.refresh,
                      label: '刷新',
                      onTap: _loadChats,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        icon: Icons.forum,
                        label: '会话',
                        value: _chats.length.toString(),
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildMetricCard(
                        icon: Icons.mark_chat_unread,
                        label: '未读',
                        value: unreadTotal.toString(),
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildMetricCard(
                        icon: Icons.push_pin,
                        label: '置顶',
                        value: pinnedCount.toString(),
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: PMDesktopCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildDesktopSearchBox(),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: PMChip(
                                  label: '@我',
                                  icon: Icons.alternate_email,
                                  selected: _showMentionsOnly,
                                  color: AppColors.primary,
                                  onTap: () => unawaited(_toggleMentionsOnly()),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.borderLight),
                        Expanded(
                          child: _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                              : _errorMessage != null
                                  ? _buildErrorState()
                                  : RefreshIndicator(
                                      onRefresh: _loadChats,
                                      child: _showMentionsOnly
                                          ? _buildMentionHitsList()
                                          : chats.isEmpty
                                              ? ListView(
                                                  children: [
                                                    SizedBox(
                                                      height: 420,
                                                      child: _buildEmptyState(),
                                                    ),
                                                  ],
                                                )
                                              : ListView.separated(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  itemBuilder:
                                                      (context, index) {
                                                    return _buildChatItem(
                                                      chats[index],
                                                    );
                                                  },
                                                  separatorBuilder: (_, __) =>
                                                      const SizedBox(height: 6),
                                                  itemCount: chats.length,
                                                ),
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopHeaderButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    );
  }

  Widget _buildDesktopSearchBox() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
      decoration: InputDecoration(
        hintText: '搜索消息、群聊或联系人',
        prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return PMDesktopCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
              '聊天列表加载失败',
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
              onPressed: _loadChats,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PMChatMark(size: 78),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? '暂无聊天记录' : '没有找到相关聊天',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '点击右下角按钮开始新的聊天',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMentionHitsList() {
    if (_isLoadingMentions) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_mentionErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.alternate_email,
                size: 56,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              const Text(
                '@我消息加载失败',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                _mentionErrorMessage!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadMentionHits,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_mentionHits.isEmpty) {
      return ListView(
        children: const [
          SizedBox(
            height: 360,
            child: Center(
              child: Text(
                '暂无 @ 我消息',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _mentionHits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final hit = _mentionHits[index];
        return PMListRow(
          leading: _buildChatAvatar(hit.chat),
          title: Text(hit.chat.name),
          subtitle: Text(
            hit.message.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          badge: '@我',
          badgeColor: AppColors.primary,
          trailing: Text(
            timeago.format(hit.message.timestamp, locale: 'zh'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          onTap: () async {
            await Navigator.pushNamed(
              context,
              '/chat/${hit.chat.id}',
              arguments: hit.chat,
            );
            if (mounted) {
              _loadChats();
            }
          },
        );
      },
    );
  }

  Widget _buildChatItem(Chat chat) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: chat.isPinned ? AppColors.accentGold : AppColors.borderLight,
        ),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: ListTile(
        onTap: () async {
          await Navigator.pushNamed(
            context,
            '/chat/${chat.id}',
            arguments: chat,
          );
          if (mounted) {
            _loadChats();
          }
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            _buildChatAvatar(chat),
            if (chat.type == ChatType.private &&
                chat.participants.isNotEmpty &&
                chat.participants.first.onlineStatus == OnlineStatus.online)
              Positioned(
                right: 2,
                bottom: 2,
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
            if (chat.isPinned)
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: AppColors.warning,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.push_pin,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                chat.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (chat.lastMessage != null)
              Text(
                timeago.format(chat.lastMessage!.timestamp, locale: 'zh'),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                chat.lastMessage?.resolvedFileLabel ?? '暂无消息',
                style: TextStyle(
                  color: chat.unreadCount > 0
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: chat.unreadCount > 0
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (chat.unreadCount > 0) ...[
              const SizedBox(width: 8),
              if (_hasUnreadMention(chat)) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Text(
                    '@',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: chat.isMuted
            ? const Icon(
                Icons.volume_off,
                size: 16,
                color: AppColors.textSecondary,
              )
            : null,
      ),
    );
  }

  Widget _buildChatAvatar(Chat chat) {
    if (chat.avatarUrl != null) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.pixelBlue,
        backgroundImage:
            NetworkImage(ApiConstants.resolveFileUrl(chat.avatarUrl!)),
      );
    }

    final label = chat.type == ChatType.group
        ? '群'
        : chat.name.isNotEmpty
            ? chat.name[0].toUpperCase()
            : '?';
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: chat.type == ChatType.group
            ? AppColors.primaryGradient
            : AppColors.accentGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }

  bool _hasUnreadMention(Chat chat) {
    final currentUserId = _currentUserId;
    return chat.unreadCount > 0 &&
        currentUserId != null &&
        chat.lastMessage?.mentionsUser(currentUserId) == true;
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
