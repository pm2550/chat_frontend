part of '../chat_list_page.dart';

extension _ChatListData1Parts on _ChatListPageState {
  Future<void> _bootstrapChats(bool hasMemorySnapshot) async {
    if (!hasMemorySnapshot && widget.chatService == null) {
      final persisted = await _chatService.loadPersistedChatRooms();
      if (mounted && persisted != null && persisted.isNotEmpty) {
        _setViewState(() {
          _chats = List<Chat>.from(persisted);
          _sortChatsInPlace();
          _isLoading = false;
          _isShowingCachedData = true;
        });
        _syncDesktopUnreadBadge();
      }
    }
    await _loadChats(showLoading: _chats.isEmpty);
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
      final chats = await _chatService.getChatRooms(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      _setViewState(() {
        _chats = List<Chat>.from(chats);
        _sortChatsInPlace();
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
    _messageSubscription =
        _realtimeService.onMessage.listen(_handleRealtimeMessage);
    _messageUpdateSubscription =
        _realtimeService.onMessageUpdated.listen(_handleRealtimeMessageUpdate);
    _statusSubscription =
        _realtimeService.onStatusChange.listen(_handleStatusChange);
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

  void _handleRealtimeMessage(Message message) {
    if (!mounted || message.chatRoomId.isEmpty) return;

    final index = _chats.indexWhere((chat) => chat.id == message.chatRoomId);
    if (index == -1) {
      unawaited(_loadChats(showLoading: false));
      return;
    }

    final currentUserId = _currentUserId;
    final isIncoming =
        currentUserId != null && !message.isFromCurrentUser(currentUserId);
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

    _setViewState(() {
      _isShowingCachedData = false;
      _chats[index] = original.copyWith(
        lastMessage: shouldPromoteToLast ? message : currentLastMessage,
        unreadCount: nextUnreadCount,
        updatedAt: shouldPromoteToLast ? message.timestamp : original.updatedAt,
      );
      ChatDataService.patchCachedChatRoom(_chats[index]);
      if (_showMentionsOnly && message.mentionsUser(currentUserId)) {
        _mentionHits.insert(
            0, _MentionHit(chat: _chats[index], message: message));
      }
      _sortChatsInPlace();
    });
    _syncDesktopUnreadBadge();

    final mentionsMe = message.mentionsUser(currentUserId);
    if (isIncoming &&
        !message.isRemoved &&
        _messageNotificationsEnabled &&
        (!original.isMuted || mentionsMe)) {
      _showIncomingMessageNotice(
          _chats.firstWhere(
            (chat) => chat.id == message.chatRoomId,
            orElse: () => original,
          ),
          mentionOverride: mentionsMe);
    }
  }

  /// 编辑/撤回/删除/生成进度：只刷新会话预览（如果改的正是最后一条），
  /// 不加未读、不弹提醒。
  void _handleRealtimeMessageUpdate(Message message) {
    if (!mounted || message.chatRoomId.isEmpty) return;
    final index = _chats.indexWhere((chat) => chat.id == message.chatRoomId);
    if (index == -1) return;
    final original = _chats[index];
    if (original.lastMessage?.id != message.id) return;
    _setViewState(() {
      _chats[index] = original.copyWith(lastMessage: message);
      ChatDataService.patchCachedChatRoom(_chats[index]);
    });
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
      ]);
    } finally {
      _isRefreshingAfterResume = false;
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

  List<Chat> get _filteredChats {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _chats;
    }
    bool matches(String? value) =>
        value != null && value.toLowerCase().contains(query);
    return _chats.where((chat) {
      if (matches(chat.name) || matches(chat.lastMessage?.resolvedFileLabel)) {
        return true;
      }
      // 私聊的会话名可能是备注或旧昵称，也按对方的昵称/用户名匹配。
      return chat.type == ChatType.private &&
          chat.participants.any(
            (user) =>
                user.id != _currentUserId &&
                (matches(user.displayName) || matches(user.username)),
          );
    }).toList();
  }

  List<User> get _filteredFriends {
    final query = _searchQuery.trim().toLowerCase();
    final friends = _friends;
    if (query.isEmpty || friends == null) return const [];
    return friends
        .where((user) =>
            user.displayName.toLowerCase().contains(query) ||
            user.username.toLowerCase().contains(query))
        .toList();
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
