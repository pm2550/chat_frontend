part of '../chat_list_page.dart';

extension _ChatListActions1Parts on _ChatListPageState {
  /// 全局"消息通知"开关：关掉后不弹前台提示和桌面通知（离线推送由服务器按同一开关拦截）。
  bool get _messageNotificationsEnabled =>
      UserSettingsCache.forUser(_currentUserId)?.messageNotificationsEnabled ??
      true;

  void _requestMobileNotificationPermission() {
    if (kIsWeb) return;
    if (_notificationService.isSupported &&
        !_notificationService.hasPermission) {
      unawaited(_notificationService.requestPermission());
    }
    unawaited(NativePushService().initialize());
  }

  Future<void> _requestDesktopNotifications() async {
    final enabled = await _notificationService.requestPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(enabled
            ? '桌面通知已开启'
            : kIsWeb
                ? '浏览器没有允许桌面通知'
                : '系统没有允许 PM chat 发通知，请到系统设置里打开'),
        backgroundColor: enabled ? AppColors.success : AppColors.warning,
      ),
    );
  }

  void _showIncomingMessageNotice(
    Chat chat, {
    bool mentionOverride = false,
  }) {
    final route = ModalRoute.of(context);
    final onChatList = route == null || route.isCurrent;
    if (!onChatList && !_notificationService.notifiesWhileInsideChat) return;

    final text = chat.lastMessage?.resolvedFileLabel ?? '收到新消息';
    final title = chat.titleFor(_currentUserId);
    _notificationService.notifyIncomingMessage(
      chatName: title,
      body: text,
      chatRoomId: chat.id,
      muted: chat.isMuted && !mentionOverride,
    );
    if (!onChatList) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $text'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onSearchChanged(String value) {
    _setViewState(() {
      _searchQuery = value;
    });
    _messageSearchTimer?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _messageSearchGeneration++;
      _setViewState(() {
        _messageHits = const [];
        _isSearchingMessages = false;
        _messageSearchError = null;
      });
      return;
    }
    unawaited(_ensureFriendsLoaded());
    _setViewState(() => _isSearchingMessages = true);
    _messageSearchTimer = Timer(
      _ChatListPageState._messageSearchDebounce,
      () => unawaited(_searchMessages(query)),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  Future<void> _ensureFriendsLoaded() async {
    if (_friends != null || _isLoadingFriends) return;
    _isLoadingFriends = true;
    try {
      final friends =
          await (widget.contactService ?? ContactDataService()).getFriends();
      if (!mounted) return;
      _setViewState(() => _friends = friends);
    } catch (_) {
      // 好友只是搜索的附加结果；拿不到时仍能搜到有私聊的人、会话和消息。
    } finally {
      _isLoadingFriends = false;
    }
  }

  Future<void> _searchMessages(String query) async {
    final generation = ++_messageSearchGeneration;
    _setViewState(() {
      _isSearchingMessages = true;
      _messageSearchError = null;
    });
    try {
      final page = await _chatService.searchAllMessages(query);
      if (!mounted || generation != _messageSearchGeneration) return;
      _setViewState(() {
        _messageHits = page.messages;
        _isSearchingMessages = false;
      });
    } catch (e) {
      if (!mounted || generation != _messageSearchGeneration) return;
      _setViewState(() {
        _messageHits = const [];
        _messageSearchError = e.toString();
        _isSearchingMessages = false;
      });
    }
  }

  Future<void> _openChatFromSearch(Chat chat, {Message? focus}) async {
    final open = widget.onOpenChat;
    if (open != null) {
      await open(ChatScreenArguments(chat: chat, focusMessage: focus));
    } else {
      await Navigator.pushNamed(context, '/chat/${chat.id}',
          arguments: focus == null
              ? chat
              : ChatScreenArguments(chat: chat, focusMessage: focus));
    }
    if (mounted) {
      unawaited(_loadChats(showLoading: false));
    }
  }

  Future<void> _openMessageHit(Message message) async {
    if (_openingSearchTarget != null) return;
    _setViewState(() => _openingSearchTarget = 'message:${message.id}');
    try {
      final resolved = _directory.conversations.roomById(message.chatRoomId) ??
          _directory.privateChats.roomById(message.chatRoomId) ??
          await _chatService.getChatRoom(message.chatRoomId);
      if (!mounted) return;
      await _openChatFromSearch(resolved, focus: message);
    } catch (e) {
      _showSnackBar('打开聊天失败: $e');
    } finally {
      if (mounted) _setViewState(() => _openingSearchTarget = null);
    }
  }

  /// 打开和这个人的私聊：已有会话直接进，没有就新建。
  Future<void> _openPersonChat(_PersonHit person) async {
    if (_openingSearchTarget != null) return;
    final user = person.user;
    _setViewState(() => _openingSearchTarget = 'user:${user.id}');
    try {
      final chat = person.chat ??
          await (widget.contactService ?? ContactDataService())
              .createPrivateChat(user.id);
      if (!mounted) return;
      _directory.privateChats.upsert(chat);
      await _openChatFromSearch(chat);
    } catch (e) {
      _showSnackBar('打开私聊失败: $e');
    } finally {
      if (mounted) _setViewState(() => _openingSearchTarget = null);
    }
  }

  Future<void> _openHiddenChats() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HiddenChatsScreen(chatService: _chatService),
      ),
    );
    if (mounted) {
      unawaited(_loadChats(showLoading: false, forceRefresh: true));
    }
  }

  Future<void> _toggleMentionsOnly() async {
    _setViewState(() {
      _showMentionsOnly = !_showMentionsOnly;
      _mentionErrorMessage = null;
    });
    if (_showMentionsOnly && _mentionHits.isEmpty) {
      await _loadMentionHits();
    }
  }

  void _focusSearch() {
    _searchFocusNode.requestFocus();
  }

  void _showMoreMenu() {
    showModalBottomSheet(
        context: context,
        builder: (sheetContext) => SafeArea(
                child: Padding(
              padding: const EdgeInsets.all(PMSpacing.m),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                PMListRow(
                    leading: const Icon(Icons.refresh),
                    title: const Text('刷新聊天列表'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _loadChats();
                    }),
                PMListRow(
                    leading: const Icon(Icons.search),
                    title: const Text('搜索聊天'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _focusSearch();
                    }),
                PMListRow(
                    leading: const Icon(Icons.clear_all),
                    title: const Text('清除搜索'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _clearSearch();
                    }),
                if (_notificationService.isSupported)
                  PMListRow(
                      leading: const Icon(Icons.notifications_none),
                      title: const Text('桌面消息通知'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _requestDesktopNotifications();
                      }),
                PMListRow(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: const Text('已移出的聊天'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_openHiddenChats());
                    }),
              ]),
            )));
  }

  Future<void> _showDesktopChatMenu(Chat chat, Offset position) async {
    final action = await showMenu<_ChatRoomMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: _chatMenuItems(chat),
    );
    if (action != null) {
      await _handleChatMenuAction(chat, action);
    }
  }

  void _showMobileChatMenu(Chat chat) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              ),
              title: Text(chat.isPinned ? '取消置顶' : '置顶'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_handleChatMenuAction(
                  chat,
                  _ChatRoomMenuAction.togglePin,
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清空聊天记录'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_handleChatMenuAction(
                  chat,
                  _ChatRoomMenuAction.clearHistory,
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('移出列表'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_handleChatMenuAction(
                  chat,
                  _ChatRoomMenuAction.hide,
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.error),
              title: const Text(
                '屏蔽',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_handleChatMenuAction(
                  chat,
                  _ChatRoomMenuAction.block,
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<_ChatRoomMenuAction>> _chatMenuItems(Chat chat) {
    return [
      PopupMenuItem(
        value: _ChatRoomMenuAction.togglePin,
        child: _menuRow(
          chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
          chat.isPinned ? '取消置顶' : '置顶',
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: _ChatRoomMenuAction.clearHistory,
        child: _menuRow(Icons.cleaning_services_outlined, '清空聊天记录'),
      ),
      PopupMenuItem(
        value: _ChatRoomMenuAction.hide,
        child: _menuRow(Icons.visibility_off_outlined, '移出列表'),
      ),
      PopupMenuItem(
        value: _ChatRoomMenuAction.block,
        child: _menuRow(Icons.block, '屏蔽', color: AppColors.error),
      ),
    ];
  }

  Widget _menuRow(IconData icon, String label, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? AppColors.textSecondary),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color ?? AppColors.textPrimary)),
      ],
    );
  }

  Future<void> _handleChatMenuAction(
    Chat chat,
    _ChatRoomMenuAction action,
  ) async {
    switch (action) {
      case _ChatRoomMenuAction.togglePin:
        await _toggleChatPinned(chat);
      case _ChatRoomMenuAction.clearHistory:
        final confirmed = await _confirmChatAction(
          title: '清空聊天记录',
          message: '只会清空你在「${chat.titleFor(_currentUserId)}」里的本地可见历史，不影响其他成员。',
          confirmLabel: '清空',
        );
        if (confirmed) {
          await _runChatStateAction(
            chat,
            () => _chatService.clearChatHistory(chat.id),
            successMessage: '已清空 ${chat.titleFor(_currentUserId)} 的聊天记录',
            removeFromList: false,
          );
        }
      case _ChatRoomMenuAction.hide:
        await _runChatStateAction(
          chat,
          () => _chatService.hideChatRoom(chat.id),
          successMessage: '已从消息列表移出 ${chat.titleFor(_currentUserId)}',
          removeFromList: true,
          undo: () => _chatService.restoreChatRoom(chat.id),
        );
      case _ChatRoomMenuAction.block:
        final confirmed = await _confirmChatAction(
          title: '屏蔽会话',
          message: '屏蔽后新消息不会回到消息列表，也不会计入未读。你仍可在联系人里找到它。',
          confirmLabel: '屏蔽',
          destructive: true,
        );
        if (confirmed) {
          await _runChatStateAction(
            chat,
            () => _chatService.blockChatRoom(chat.id),
            successMessage: '已屏蔽 ${chat.titleFor(_currentUserId)}',
            removeFromList: true,
          );
        }
    }
  }

  Future<bool> _confirmChatAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
