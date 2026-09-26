part of '../chat_screen.dart';

extension _ChatSessionData1Parts on _ChatScreenState {
  Future<LinkPreview?> _loadLinkPreview(String url) {
    return _linkPreviewFutures.putIfAbsent(url, () async {
      try {
        return await _chatService.fetchUrlPreview(url);
      } catch (_) {
        return null;
      }
    });
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
        _setViewState(() {
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
        _setViewState(() {
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
      _setViewState(() {
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
    _setViewState(() {
      if (showBlockingLoader) {
        _isLoadingMessages = true;
      }
      _errorMessage = null;
    });

    try {
      final page = await _chatService.getMessagePage(_chat.id);
      if (!mounted) return;
      final wasNearBottom = _isNearBottom();
      _setViewState(() {
        // 还在发送中/发送失败的本地消息服务器那边没有，整页刷新时要留着，
        // 否则回显或失败提示到来时已经找不到它，消息就无声无息地没了。
        _messages = [
          ...page.messages,
          ..._messages.where(_ChatScreenState._isLocalUnsentMessage),
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
        _setViewState(() {
          _isLoadingMessages = false;
          _errorMessage = null;
        });
        return;
      }
      _setViewState(() {
        _errorMessage = e.toString();
        _isLoadingMessages = false;
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

  void _syncNewMessageButton() {
    if (!_scrollController.hasClients) return;
    final distanceFromBottom = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    final shouldShow = distanceFromBottom > 200 && _newMessagesBelow > 0;
    if (shouldShow != _showNewMessagesButton ||
        (!shouldShow && _newMessagesBelow != 0)) {
      _setViewState(() {
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
    _setViewState(() {
      _isLoadingOlderMessages = true;
    });

    try {
      final page = await _chatService.getMessagePage(
        _chat.id,
        page: _nextMessagePage,
      );
      if (!mounted) return;
      _setViewState(() {
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
      _setViewState(() {
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
      _setViewState(() {
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
        _setViewState(() {
          _chat = _chat.withRoomUpdate(Map<String, dynamic>.from(chatRoomJson));
        });
      }
      return;
    }
    if (event['type'] == 'poll_voted') {
      _setViewState(() => _pollRefreshEpoch += 1);
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
    _setViewState(() {
      // 服务器回显的正式消息替换掉同一 clientMessageId 的本地"发送中"气泡。
      final clientMessageId = message.clientMessageId;
      if (clientMessageId != null && clientMessageId != message.id) {
        _messages.removeWhere((m) => m.id == clientMessageId);
        // 附件的正式消息到了（REST 返回或服务器推回），上传气泡功成身退。
        _outgoingUploads.remove(clientMessageId)?.settle();
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

  void _saveMessageCache() {
    // 上传气泡只活在这一屏：离开后没人能取消/重试它，缓存里不留。
    final messages = _outgoingUploads.isEmpty
        ? _messages
        : _messages
            .where((message) => !_outgoingUploads.containsKey(message.id))
            .toList();
    ChatScreen._messageCache[_chat.id] = _CachedChatMessages(
      messages: List<Message>.from(messages),
      hasMoreMessages: _hasMoreMessages,
      nextMessagePage: _nextMessagePage,
    );
    unawaited(_chatService.persistMessages(_chat.id, messages));
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

  String get _effectiveBackgroundPreset {
    return _appSettings.chatBackgroundPreset;
  }

  String? get _effectiveBackgroundUrl {
    final userUrl = _appSettings.chatBackgroundCustomUrl?.trim();
    return userUrl == null || userUrl.isEmpty ? null : userUrl;
  }
}
