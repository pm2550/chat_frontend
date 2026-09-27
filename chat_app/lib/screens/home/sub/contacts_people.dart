part of '../contacts_page.dart';

enum _ContactMenuAction {
  voiceCall,
  videoCall,
  profile,
  moveToGroup,
  togglePin,
  toggleMute,
  clearHistory,
  toggleBlock,
  removeFriend,
  addFriend,
}

extension _ContactsPeopleParts on _ContactsPageState {
  /// 好友按"好友"归组；和非好友的私聊按"会话"归组。老版本里私聊单独分过组的，
  /// 好友没有自己的分组时沿用那个。
  String? _assignedGroupIdForEntry(_ContactEntry entry) {
    final chat = entry.chat;
    final friendGroup = entry.isFriend
        ? _assignedGroupId(ContactGroupTargetType.friend, entry.user.id)
        : null;
    return friendGroup ??
        (chat == null
            ? null
            : _assignedGroupId(ContactGroupTargetType.room, chat.id));
  }

  void _showEntryMoveToGroupSheet(_ContactEntry entry) {
    final chat = entry.chat;
    final targetType = entry.isFriend || chat == null
        ? ContactGroupTargetType.friend
        : ContactGroupTargetType.room;
    final targetId =
        targetType == ContactGroupTargetType.friend ? entry.user.id : chat!.id;
    // 好友以"好友"分组为准：会话上的旧分组要一起清掉，否则移到未分组后还会显示在旧组里。
    final staleRoomAssignment = entry.isFriend &&
        chat != null &&
        _assignedGroupId(ContactGroupTargetType.room, chat.id) != null;
    _showMoveToGroupSheet(
      title: _displayName(entry.user),
      busyKey: ContactGroupTargetKey.build(targetType, targetId),
      currentGroupId: _assignedGroupIdForEntry(entry),
      onSelected: (groupId) => _assignTargetToGroup(
        targetType: targetType,
        targetId: targetId,
        groupId: groupId,
        alsoClear: [
          if (staleRoomAssignment)
            (type: ContactGroupTargetType.room, id: chat.id),
        ],
      ),
    );
  }

  Widget _buildContactEntryItem(_ContactEntry entry) {
    final user = entry.user;
    final chat = entry.chat;
    final selected = chat != null && widget.selectedChatId == chat.id;
    final isOpening = _openingChatUserId == user.id;
    final lastMessageAt = entry.lastMessageAt;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: PMSpacing.l, vertical: PMSpacing.xs),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            unawaited(_showDesktopContactMenu(entry, details.globalPosition)),
        child: PMCard(
          elevated: false,
          padding: EdgeInsets.zero,
          background: selected
              ? AppColors.pixelBlue
              : (entry.isPinned ? AppColors.cloud : AppColors.surface),
          child: PMListRow(
            key: ValueKey('contact-${user.id}'),
            onTap: () => unawaited(_openContactChat(entry)),
            onLongPress: () => _showContactMenu(entry),
            leading: _buildAvatar(user, radius: 22),
            title: Row(children: [
              Flexible(
                  child: Text(_displayName(user),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (user.title?.trim().isNotEmpty ?? false) ...[
                const SizedBox(width: PMSpacing.xs),
                PMTitleBadge(
                    title: user.title,
                    color: user.titleColor,
                    effect: user.titleEffect)
              ],
              if (!entry.isFriend) ...[
                const SizedBox(width: PMSpacing.xs),
                _buildNonFriendTag(),
              ],
              if (entry.isPinned)
                const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.push_pin_rounded,
                        size: 12, color: AppColors.textTertiary)),
            ]),
            subtitle: _buildEntrySubtitle(entry),
            badge: entry.isBlocked ? '已屏蔽' : null,
            badgeColor: AppColors.textSecondary,
            trailing: isOpening
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (lastMessageAt != null)
                        Text(timeago.format(lastMessageAt, locale: 'zh'),
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textTertiary)),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (entry.isMuted)
                          const Icon(Icons.volume_off_outlined,
                              size: 14, color: AppColors.textTertiary),
                        if (entry.unreadCount > 0 && !entry.isBlocked)
                          Badge(
                              label: Text(_unreadLabel(entry)),
                              backgroundColor: AppColors.primary),
                        SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: '联系人操作',
                                icon: const Icon(Icons.more_horiz, size: 18),
                                onPressed: () => _showContactMenu(entry))),
                      ]),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildNonFriendTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '非好友',
        style: TextStyle(
          color: AppColors.warning,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _unreadLabel(_ContactEntry entry) {
    final chat = entry.chat;
    if (chat?.lastMessage?.mentionsUser(_currentUserId) == true) return '@';
    return entry.unreadCount > 99 ? '99+' : '${entry.unreadCount}';
  }

  /// 有聊天记录显示最后一条消息，否则显示在线状态。
  Widget _buildEntrySubtitle(_ContactEntry entry) {
    final preview = entry.chat?.lastMessage?.resolvedFileLabel;
    if (preview != null) {
      return Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final user = entry.user;
    final online = user.onlineStatus == OnlineStatus.online;
    return Text(
      online
          ? '在线'
          : user.lastSeen != null
              ? '${_formatLastSeen(user.lastSeen!)}在线'
              : '离线',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: online ? AppColors.online : null),
    );
  }

  /// 点联系人就进私聊：已有会话直接打开，没有就先建一个。
  Future<void> _openContactChat(
    _ContactEntry entry, {
    CallMediaKind? startCall,
  }) async {
    if (_openingChatUserId != null) return;
    var chat = entry.chat;
    if (chat == null) {
      _setViewState(() => _openingChatUserId = entry.user.id);
      try {
        final created = await _contactService.createPrivateChat(entry.user.id);
        // 建房接口不带参与者；先补上对方，列表才能把会话归到这个人名下。
        chat = created.participants.isEmpty
            ? created.copyWith(participants: [entry.user])
            : created;
        _directory.privateChats.upsert(chat);
      } catch (e) {
        _showSnackBar(startCall == null
            ? '打开私聊失败: $e'
            : '${startCall.label}通话启动失败: $e');
        return;
      } finally {
        if (mounted) _setViewState(() => _openingChatUserId = null);
      }
      if (!mounted) return;
    }
    final arguments = ChatScreenArguments(
      chat: chat,
      startCall: startCall,
      openedFromContacts: true,
    );
    final open = widget.onOpenChat;
    if (open != null) {
      await open(arguments);
      return;
    }
    await Navigator.pushNamed(context, '/chat/${chat.id}', arguments: arguments);
    if (mounted) unawaited(_refreshPrivateChatsQuietly());
  }

  Future<void> _refreshPrivateChatsQuietly() async {
    try {
      await _directory.privateChats.load();
    } catch (_) {
      // 刷新失败时保留当前列表，实时事件会继续更新它。
    }
  }

  void _showContactMenu(_ContactEntry entry) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in _contactMenuActions(entry))
                ListTile(
                  leading: Icon(
                    _contactMenuIcon(entry, action),
                    color: _isDestructive(action) ? AppColors.error : null,
                  ),
                  title: Text(
                    _contactMenuLabel(entry, action),
                    style: _isDestructive(action)
                        ? const TextStyle(color: AppColors.error)
                        : null,
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_handleContactMenuAction(entry, action));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDesktopContactMenu(
    _ContactEntry entry,
    Offset position,
  ) async {
    final action = await showMenu<_ContactMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        for (final action in _contactMenuActions(entry))
          PopupMenuItem(
            value: action,
            child: Row(children: [
              Icon(
                _contactMenuIcon(entry, action),
                size: 20,
                color: _isDestructive(action)
                    ? AppColors.error
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                _contactMenuLabel(entry, action),
                style: TextStyle(
                  color: _isDestructive(action)
                      ? AppColors.error
                      : AppColors.textPrimary,
                ),
              ),
            ]),
          ),
      ],
    );
    if (action != null) {
      await _handleContactMenuAction(entry, action);
    }
  }

  /// 置顶、免打扰、清空、屏蔽都作用在私聊上；还没聊过的人没有这些项。
  /// 联系人不会因为"移出列表"消失，所以没有这一项。
  List<_ContactMenuAction> _contactMenuActions(_ContactEntry entry) {
    final hasChat = entry.chat != null;
    return [
      _ContactMenuAction.voiceCall,
      _ContactMenuAction.videoCall,
      _ContactMenuAction.profile,
      _ContactMenuAction.moveToGroup,
      if (hasChat) ...[
        _ContactMenuAction.togglePin,
        _ContactMenuAction.toggleMute,
        _ContactMenuAction.clearHistory,
        _ContactMenuAction.toggleBlock,
      ],
      entry.isFriend
          ? _ContactMenuAction.removeFriend
          : _ContactMenuAction.addFriend,
    ];
  }

  bool _isDestructive(_ContactMenuAction action) =>
      action == _ContactMenuAction.removeFriend;

  String _contactMenuLabel(_ContactEntry entry, _ContactMenuAction action) {
    return switch (action) {
      _ContactMenuAction.voiceCall => '语音通话',
      _ContactMenuAction.videoCall => '视频通话',
      _ContactMenuAction.profile => '查看资料',
      _ContactMenuAction.moveToGroup => '移动到分组',
      _ContactMenuAction.togglePin => entry.isPinned ? '取消置顶' : '置顶',
      _ContactMenuAction.toggleMute => entry.isMuted ? '取消免打扰' : '消息免打扰',
      _ContactMenuAction.clearHistory => '清空聊天记录',
      _ContactMenuAction.toggleBlock => entry.isBlocked ? '解除屏蔽' : '屏蔽',
      _ContactMenuAction.removeFriend => '删除好友',
      _ContactMenuAction.addFriend => '加好友',
    };
  }

  IconData _contactMenuIcon(_ContactEntry entry, _ContactMenuAction action) {
    return switch (action) {
      _ContactMenuAction.voiceCall => Icons.call,
      _ContactMenuAction.videoCall => Icons.videocam,
      _ContactMenuAction.profile => Icons.person_outline,
      _ContactMenuAction.moveToGroup => Icons.drive_file_move_outline,
      _ContactMenuAction.togglePin =>
        entry.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
      _ContactMenuAction.toggleMute => entry.isMuted
          ? Icons.notifications_active_outlined
          : Icons.notifications_off_outlined,
      _ContactMenuAction.clearHistory => Icons.cleaning_services_outlined,
      _ContactMenuAction.toggleBlock =>
        entry.isBlocked ? Icons.lock_open : Icons.block,
      _ContactMenuAction.removeFriend => Icons.person_remove,
      _ContactMenuAction.addFriend => Icons.person_add_alt_1,
    };
  }

  Future<void> _handleContactMenuAction(
    _ContactEntry entry,
    _ContactMenuAction action,
  ) async {
    final chat = entry.chat;
    switch (action) {
      case _ContactMenuAction.voiceCall:
        await _openContactChat(entry, startCall: CallMediaKind.audio);
      case _ContactMenuAction.videoCall:
        await _openContactChat(entry, startCall: CallMediaKind.video);
      case _ContactMenuAction.profile:
        _showContactProfile(entry);
      case _ContactMenuAction.moveToGroup:
        _showEntryMoveToGroupSheet(entry);
      case _ContactMenuAction.togglePin:
        if (chat != null) await _toggleChatPinned(chat);
      case _ContactMenuAction.toggleMute:
        if (chat != null) await _toggleChatMuted(chat);
      case _ContactMenuAction.clearHistory:
        if (chat != null) await _clearChatHistory(entry, chat);
      case _ContactMenuAction.toggleBlock:
        if (chat != null) await _setRoomBlocked(chat, !chat.isBlocked);
      case _ContactMenuAction.removeFriend:
        await _removeContact(entry.user);
      case _ContactMenuAction.addFriend:
        await _sendFriendRequestTo(entry.user);
    }
  }

  Future<void> _toggleChatPinned(Chat chat) async {
    try {
      await _chatService.updateNotificationSettings(
        chat.id,
        pinned: !chat.isPinned,
      );
      _directory.privateChats.updateRoom(
        chat.id,
        (room) => room.copyWith(isPinned: !chat.isPinned),
      );
      _showSnackBar(chat.isPinned ? '已取消置顶' : '已置顶');
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _toggleChatMuted(Chat chat) async {
    try {
      await _chatService.updateNotificationSettings(
        chat.id,
        muted: !chat.isMuted,
      );
      _directory.privateChats.updateRoom(
        chat.id,
        (room) => room.copyWith(isMuted: !chat.isMuted),
      );
      _showSnackBar(chat.isMuted ? '已取消免打扰' : '已开启消息免打扰');
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _clearChatHistory(_ContactEntry entry, Chat chat) async {
    final name = _displayName(entry.user);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: Text('只会清空你这边和「$name」的聊天记录，对方不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _chatService.clearChatHistory(chat.id);
      _showSnackBar('已清空和 $name 的聊天记录');
      // 最后一条消息要从服务器重新取。
      await _refreshPrivateChatsQuietly();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _setRoomBlocked(Chat chat, bool blocked) async {
    if (_unblockingRoomId != null) return;
    final name = chat.titleFor(_currentUserId);
    if (blocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('屏蔽'),
          content: Text('屏蔽后不再收到「$name」的新消息提醒，也不计未读。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('屏蔽'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _setViewState(() => _unblockingRoomId = chat.id);
    try {
      if (blocked) {
        await _chatService.blockChatRoom(chat.id);
      } else {
        await _chatService.unblockChatRoom(chat.id);
      }
      if (!mounted) return;
      _showSnackBar(blocked ? '已屏蔽 $name' : '已解除屏蔽 $name');
      if (chat.type == ChatType.private) {
        _directory.privateChats.updateRoom(
          chat.id,
          (room) => room.copyWith(
            isBlocked: blocked,
            unreadCount: blocked ? 0 : null,
            hiddenAt: blocked ? DateTime.now() : null,
            clearHiddenAt: !blocked,
          ),
        );
      } else {
        await _loadContacts();
      }
    } catch (e) {
      _showSnackBar(e.toString());
    } finally {
      if (mounted) _setViewState(() => _unblockingRoomId = null);
    }
  }

  Future<void> _sendFriendRequestTo(User user) async {
    try {
      await _contactService.sendFriendRequest(user.id);
      _showSnackBar('好友请求已发送');
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  /// 资料卡：原来点好友弹出的那张，现在从菜单的"查看资料"进入。
  void _showContactProfile(_ContactEntry entry) {
    final contact = entry.user;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildAvatar(contact, radius: 40),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _displayName(contact),
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (!entry.isFriend) ...[
                            const SizedBox(width: 8),
                            _buildNonFriendTag(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        contact.onlineStatus == OnlineStatus.online
                            ? '在线'
                            : '离线',
                        style: TextStyle(
                          color: contact.onlineStatus == OnlineStatus.online
                              ? AppColors.online
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            icon: Icons.chat,
                            label: '发消息',
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              unawaited(_openContactChat(entry));
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.videocam,
                            label: '视频通话',
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              unawaited(_openContactChat(
                                entry,
                                startCall: CallMediaKind.video,
                              ));
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.call,
                            label: '语音通话',
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              unawaited(_openContactChat(
                                entry,
                                startCall: CallMediaKind.audio,
                              ));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // 邮箱、手机号只有本人能看到，这里展示用户名。
                      _buildContactDetailLine(
                        Icons.alternate_email,
                        '用户名',
                        contact.username,
                      ),
                      if (contact.bio != null && contact.bio!.isNotEmpty)
                        _buildContactDetailLine(
                          Icons.notes,
                          '简介',
                          contact.bio!,
                        ),
                      if (contact.lastSeen != null)
                        _buildContactDetailLine(
                          Icons.access_time,
                          '最后在线',
                          _formatLastSeen(contact.lastSeen!),
                        ),
                      const SizedBox(height: 8),
                      if (entry.isFriend)
                        ListTile(
                          leading: const Icon(
                            Icons.person_remove,
                            color: AppColors.error,
                          ),
                          title: const Text(
                            '删除好友',
                            style: TextStyle(color: AppColors.error),
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            unawaited(_removeContact(contact));
                          },
                        )
                      else
                        ListTile(
                          leading: const Icon(Icons.person_add_alt_1),
                          title: const Text('加好友'),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            unawaited(_sendFriendRequestTo(contact));
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
