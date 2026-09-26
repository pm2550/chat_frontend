part of '../chat_list_page.dart';

extension _ChatListData1Parts on _ChatListPageState {
  Future<void> _bootstrapChats(bool hasMemorySnapshot) async {
    if (!hasMemorySnapshot && widget.chatService == null) {
      final persisted = await _chatService.loadPersistedChatRooms(
        excludeType: ChatType.private,
      );
      if (mounted &&
          persisted != null &&
          persisted.isNotEmpty &&
          !_directory.conversations.hasLoaded) {
        _directory.conversations.replaceAll(persisted);
        _setViewState(() {
          _isLoading = false;
          _isShowingCachedData = true;
        });
      }
    }
    await _loadChats(showLoading: _chats.isEmpty);
    // 私聊不在这里显示，但系统角标和私聊的新消息提醒要用到。
    unawaited(_directory.privateChats.ensureLoaded());
  }

  Future<void> _loadChats({
    bool showLoading = true,
    bool forceRefresh = false,
  }) async {
    if (mounted && showLoading && _chats.isEmpty) {
      _setViewState(() {
        _isLoading = true;
        _errorMessage = null;
        _isShowingCachedData = false;
      });
    } else if (mounted && showLoading) {
      _setViewState(() {
        _errorMessage = null;
      });
    }

    try {
      await _directory.conversations.load(forceRefresh: forceRefresh);
      if (!mounted) return;
      _setViewState(() {
        _isLoading = false;
        _errorMessage = null;
        _isShowingCachedData = false;
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
      if (_chats.isNotEmpty) {
        _setViewState(() {
          _isLoading = false;
          _errorMessage = null;
          _isShowingCachedData = true;
        });
        return;
      }
      if (!showLoading) return;
      _setViewState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _connectRealtime() async {
    await _realtimeService.connect();
  }

  void _loadNotificationPreference() {
    if (UserSettingsCache.forUser(_currentUserId) != null) return;
    final profileService = widget.profileService ??
        (widget.chatService == null ? UserProfileService() : null);
    if (profileService == null) return;
    unawaited(profileService.getSettings().then<void>((_) {}, onError: (_) {
      // 读不到设置时按默认（开启）处理，不影响聊天列表本身。
    }));
  }

  /// 目录里任一份会话变了（新消息、已读、置顶、移出……）：刷新列表和系统角标。
  void _onDirectoryChanged() {
    runOutsideBuild(() {
      if (!mounted) return;
      _setViewState(() {
        final conversations = _directory.conversations;
        _mentionHits.removeWhere((hit) => !conversations.contains(hit.chat.id));
        if (conversations.hasLoaded && _chats.isNotEmpty) _isLoading = false;
      });
      _syncDesktopUnreadBadge();
    });
  }

  /// 新消息已经记进目录：消息页负责弹提醒（私聊的也在这里提醒）。
  void _handleMessageActivity(ChatRoomMessageActivity activity) {
    if (!mounted) return;
    final message = activity.message;
    final currentUserId = _currentUserId;
    final mentionsMe = message.mentionsUser(currentUserId);
    if (activity.scope == ChatRoomScope.conversations) {
      _setViewState(() {
        _isShowingCachedData = false;
        if (_showMentionsOnly && mentionsMe) {
          _mentionHits.insert(
              0, _MentionHit(chat: activity.chat, message: message));
        }
      });
    }
    final original = activity.previous;
    if (activity.isIncoming &&
        !message.isRemoved &&
        !original.isBlocked &&
        _messageNotificationsEnabled &&
        (!original.isMuted || mentionsMe)) {
      _showIncomingMessageNotice(activity.chat, mentionOverride: mentionsMe);
    }
  }

  Future<void> _refreshAfterResume() async {
    if (_isRefreshingAfterResume) return;
    _isRefreshingAfterResume = true;
    try {
      final reconnect = _realtimeService is WebSocketService
          ? _realtimeService.reconnect()
          : Future<void>.value();
      await Future.wait<void>([
        reconnect,
        _loadChats(showLoading: false, forceRefresh: true),
        _refreshPrivateChatsQuietly(),
      ]);
    } finally {
      _isRefreshingAfterResume = false;
    }
  }

  Future<void> _refreshPrivateChatsQuietly() async {
    try {
      await _directory.privateChats.load(forceRefresh: true);
    } catch (_) {
      // 私聊只影响角标和提醒；拉不到时下次事件或回到前台再试。
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

  /// 系统 / 桌面 / 图标角标算全部未读：消息页不再显示私聊，但私聊未读不能丢。
  void _syncDesktopUnreadBadge() {
    _notificationService.syncUnreadCount(_directory.totalUnread);
  }

  List<Chat> get _filteredChats {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _chats;
    }
    bool matches(String? value) =>
        value != null && value.toLowerCase().contains(query);
    return _chats
        .where((chat) =>
            matches(chat.name) || matches(chat.lastMessage?.resolvedFileLabel))
        .toList();
  }

  /// 搜索里的"联系人"：好友和所有私聊的对方（非好友也在内），按人去重。
  List<_PersonHit> get _filteredPeople {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final currentUserId = _currentUserId;
    final chatsByPeer = <String, Chat>{};
    final peers = <String, User>{};
    for (final chat in _directory.privateChats.rooms) {
      final peer = chat.peerFor(currentUserId);
      if (peer == null) continue;
      chatsByPeer.putIfAbsent(peer.id, () => chat);
      peers.putIfAbsent(peer.id, () => peer);
    }
    for (final friend in _friends ?? const <User>[]) {
      peers[friend.id] = friend;
    }
    bool matches(User user) =>
        user.displayName.toLowerCase().contains(query) ||
        user.username.toLowerCase().contains(query);
    return [
      for (final user in peers.values)
        if (matches(user)) _PersonHit(user: user, chat: chatsByPeer[user.id]),
    ];
  }

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  Future<void> _loadMentionHits() async {
    if (!mounted) return;
    _setViewState(() {
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
      _setViewState(() {
        _mentionHits = hits;
        _isLoadingMentions = false;
      });
    } catch (e) {
      if (!mounted) return;
      _setViewState(() {
        _mentionErrorMessage = e.toString();
        _isLoadingMentions = false;
      });
    }
  }

  bool _hasUnreadMention(Chat chat) {
    final currentUserId = _currentUserId;
    return chat.unreadCount > 0 &&
        currentUserId != null &&
        chat.lastMessage?.mentionsUser(currentUserId) == true;
  }
}
