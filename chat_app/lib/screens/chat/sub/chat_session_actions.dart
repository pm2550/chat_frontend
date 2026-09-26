part of '../chat_screen.dart';

extension _ChatSessionActions1Parts on _ChatScreenState {
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

  void _startChatSession() {
    _restoreCachedMessages();
    // 进聊天页总是找服务器确认一次加密状态，别用别的页面留下的旧缓存。
    unawaited(_refreshE2eeRoomState(refresh: true));
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

  Color? _parseAnonymousColor(String? value) {
    if (value == null || !value.startsWith('#')) return null;
    final hex = value.substring(1);
    if (hex.length != 6 && hex.length != 8) return null;
    final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  AttachmentType _attachmentTypeForMessage(Message message) {
    if (message.isImageMessage) return AttachmentType.image;
    if (message.isVideoMessage) return AttachmentType.video;
    if (message.isVoiceMessage) return AttachmentType.voice;
    if (message.isLocationMessage) return AttachmentType.location;
    return AttachmentType.file;
  }
}
