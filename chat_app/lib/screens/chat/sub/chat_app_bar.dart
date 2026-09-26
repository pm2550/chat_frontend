part of '../chat_screen.dart';

extension _ChatScreenChromeParts on _ChatScreenState {
  Widget _buildDesktopChatScaffold() {
    return _buildDropPasteTarget(Scaffold(
      key: _desktopScaffoldKey,
      endDrawer: Drawer(width: 340, child: _buildDesktopInfoPanel()),
      onEndDrawerChanged: (open) {
        _setViewState(() => _desktopInfoPanelCollapsed = !open);
        _syncAgentClientToolState();
      },
      body: Row(children: [
        _buildDesktopRail(),
        SizedBox(
            key: const ValueKey('desktop-conversation-list'),
            width: PMDesktopLayout.conversationListWidth(context),
            // 私聊属于联系人：中间栏换成联系人列表，群聊 / 频道仍是消息列表。
            child: _chat.type == ChatType.private
                ? ContactsPage(
                    compact: true,
                    selectedChatId: _chat.id,
                    chatService: widget.chatService,
                    contactService: widget.contactService,
                    realtimeService: widget.webSocketService,
                    currentUserId: _authService.currentUser?.id,
                    onOpenChat: _openChatFromDesktopList,
                  )
                : ChatListPage(
                    compact: true,
                    selectedChatId: _chat.id,
                    chatService: widget.chatService,
                    realtimeService: widget.webSocketService,
                    currentUserId: _authService.currentUser?.id,
                    onOpenChat: _openChatFromDesktopList,
                  )),
        const VerticalDivider(width: 1),
        Expanded(
            child: Column(children: [
          _buildDesktopConversationHeader(),
          _buildCallPanel(),
          _buildE2eeNotice(),
          _buildAnonymousBanner(),
          _buildAnnouncementBanner(),
          _buildPinnedMessagesBar(),
          Expanded(child: _buildMessageArea()),
          _buildDesktopInputBar(),
        ])),
      ]),
    ));
  }

  /// 导航栏高亮当前会话所属的 tab（私聊在联系人），角标跟着未读实时变化。
  Widget _buildDesktopRail() {
    final directory = ChatRoomDirectory.of(
      chatService: widget.chatService,
      realtimeService: widget.webSocketService,
      currentUserId: _authService.currentUser?.id,
    );
    return ListenableBuilder(
        listenable: directory.changes,
        builder: (context, _) => PMNavigationRail(
            selectedIndex: _chat.type == ChatType.private ? 1 : 0,
            badgeCounts: [
              directory.conversationUnread,
              directory.privateUnread,
            ],
            onSelected: (index) {
              Navigator.of(context).pushNamedAndRemoveUntil(
                  PMNavigationRail.routes[index], (_) => false);
            }));
  }

  Future<void> _openChatFromDesktopList(ChatScreenArguments arguments) async {
    if (arguments.chat.id == _chat.id) {
      if (arguments.focusMessage != null) {
        _pendingFocusMessage = arguments.focusMessage;
        _focusPendingMessage();
      }
      final startCall = arguments.startCall;
      if (startCall != null) unawaited(_startCall(startCall));
      return;
    }
    unawaited(Navigator.of(context)
        .pushReplacementNamed('/chat/${arguments.chat.id}', arguments: arguments));
  }

  void _openDesktopDetails() {
    _setViewState(() => _desktopInfoPanelCollapsed = false);
    _desktopScaffoldKey.currentState?.openEndDrawer();
  }

  Widget _buildDesktopConversationHeader() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: _chat.type == ChatType.group ? '群信息 / 设置' : '聊天信息',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  onTap: _openRoomSettings,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayChatTitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _chatSubtitle(),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (_e2eeRoom.encrypts) ...[
                              const SizedBox(width: 10),
                              E2eeHeaderBadge(state: _e2eeRoom, fontSize: 13),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildDesktopHeaderIcon(PMSymbol.call, '语音通话', () {
            _startCall(CallMediaKind.audio);
          }),
          const SizedBox(width: 8),
          _buildDesktopHeaderIcon(PMSymbol.video, '视频通话', () {
            _startCall(CallMediaKind.video);
          }),
          const SizedBox(width: 8),
          _buildDesktopHeaderIcon(PMSymbol.search, '搜索记录', _showSearchSheet),
          const SizedBox(width: 8),
          _buildDesktopHeaderIcon(
              PMSymbol.profile, '房间资料', _openDesktopDetails),
          const SizedBox(width: 8),
          _buildDesktopHeaderIcon(PMSymbol.more, '更多', _showChatOptions),
        ],
      ),
    );
  }

  Widget _buildDesktopHeaderIcon(
      PMSymbol symbol, String tooltip, VoidCallback onTap) {
    return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: PMSymbolIcon(symbol, size: 21, color: AppColors.textSecondary));
  }

  String _chatSubtitle() {
    if (_chat.type == ChatType.private) {
      final participant = _privatePeer();
      if (participant == null) return '私聊';
      return _presenceLabel(participant);
    }
    if (_chat.type == ChatType.group) {
      return '${_chat.effectiveMemberCount}人';
    }
    return '会话';
  }

  User? _privatePeer() {
    if (_chat.type != ChatType.private || _chat.participants.isEmpty) {
      return null;
    }
    final currentUserId = _authService.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return _chat.participants.first;
    }
    return _chat.participants.firstWhere(
      (user) => user.id != currentUserId,
      orElse: () => _chat.participants.first,
    );
  }

  String _displayChatTitle() {
    if (_chat.type != ChatType.private) {
      return _chat.name;
    }
    final peer = _privatePeer();
    final peerName = peer?.displayName.trim();
    if (peerName != null && peerName.isNotEmpty) {
      return peerName;
    }
    final username = peer?.username.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
    return _chat.name;
  }

  String? _displayChatAvatarUrl() {
    if (_chat.type == ChatType.private) {
      return _privatePeer()?.avatarUrl ?? _chat.avatarUrl;
    }
    return _chat.avatarUrl;
  }

  Widget _buildChatAvatar() {
    final avatarUrl = _displayChatAvatarUrl();
    final title = _displayChatTitle();
    final fallback = _chat.type == ChatType.group
        ? '群'
        : title.isNotEmpty
            ? title.characters.first.toUpperCase()
            : '?';
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.pixelBlue,
      backgroundImage: avatarUrl != null
          ? NetworkImage(
              ApiConstants.resolveFileUrl(avatarUrl),
            )
          : null,
      child: avatarUrl == null
          ? Text(
              fallback,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}

/// 在线 / 离开 / 忙碌 直接显示；离线时显示"最后在线 X"（最后一个连接断开的时间）。
String _presenceLabel(User user) {
  if (user.onlineStatus != OnlineStatus.offline) {
    return user.onlineStatus.description;
  }
  final lastSeen = user.lastSeen;
  if (lastSeen != null) {
    return '最后在线 ${timeago.format(lastSeen, locale: 'zh')}';
  }
  return OnlineStatus.offline.description;
}
