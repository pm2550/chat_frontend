part of '../chat_list_page.dart';

extension _ChatListView1Parts on _ChatListPageState {
  Widget _buildConversationList() {
    final chats = _filteredChats
        .where((chat) => !_unreadOnly || chat.unreadCount > 0)
        .toList();
    final unread = _chats.fold<int>(0, (sum, chat) => sum + chat.unreadCount);
    return ColoredBox(
        color: AppColors.surface,
        child: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(children: [
                const Expanded(
                    child: Text('消息',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: '发起聊天',
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/home/contacts'),
                    icon: const Icon(Icons.edit_square)),
                IconButton(
                    tooltip: '消息选项',
                    onPressed: _showMoreMenu,
                    icon: const Icon(Icons.more_horiz)),
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: PMSpacing.l),
              child: _buildDesktopSearchBox()),
          const SizedBox(height: PMSpacing.m),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: PMSpacing.l),
                child: Row(children: [
                  PMChip(
                      label: '全部',
                      selected: !_unreadOnly && !_showMentionsOnly,
                      onTap: () => _setViewState(() {
                            _unreadOnly = false;
                            _showMentionsOnly = false;
                          })),
                  const SizedBox(width: PMSpacing.s),
                  PMChip(
                      label: unread > 0 ? '未读 $unread' : '未读',
                      selected: _unreadOnly && !_showMentionsOnly,
                      onTap: () => _setViewState(() {
                            _unreadOnly = true;
                            _showMentionsOnly = false;
                          })),
                  const SizedBox(width: PMSpacing.s),
                  PMChip(
                      label: '@我',
                      selected: _showMentionsOnly,
                      onTap: () => unawaited(_toggleMentionsOnly())),
                ]),
              )),
          const SizedBox(height: PMSpacing.m),
          if (_isShowingCachedData) _buildCachedDataIndicator(),
          Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? _buildErrorState()
                      : RefreshIndicator(
                          onRefresh: _loadChats,
                          child: _showMentionsOnly
                              ? _buildMentionHitsList()
                              : _isSearching
                                  ? _buildSearchResults()
                                  : chats.isEmpty
                                      ? ListView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          children: [
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: PMSpacing.xxl,
                                                      horizontal: PMSpacing.l),
                                                  child: _unreadOnly
                                                      ? const PMEmptyState(
                                                          icon: Icons.done_all,
                                                          title: '未读都看完了',
                                                          subtitle:
                                                              '切换到全部，继续聊天。',
                                                          variant:
                                                              EmptyStateVariant
                                                                  .muted)
                                                      : _buildEmptyState()),
                                            ])
                                      : ListView.builder(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.fromLTRB(
                                              8, 0, 8, 16),
                                          itemCount: chats.length,
                                          itemBuilder: (context, index) =>
                                              _buildChatItem(chats[index])),
                        )),
        ])));
  }

  Widget _buildCachedDataIndicator() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 16, color: AppColors.warning),
          SizedBox(width: 7),
          Text(
            '正在显示上次同步的数据',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSearchBox() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: '搜索消息、群聊或联系人',
        prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                onPressed: _clearSearch,
              )
            : null,
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

  Widget _buildSearchSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final chats = _filteredChats;
    final friends = _filteredFriends;
    final query = _searchQuery.trim();
    final noLocalHits = chats.isEmpty && friends.isEmpty;
    return ListView(
      key: const ValueKey('chat-list-search-results'),
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        if (chats.isNotEmpty) ...[
          _buildSearchSectionTitle('聊天'),
          for (final chat in chats) _buildChatItem(chat),
        ],
        if (friends.isNotEmpty) ...[
          _buildSearchSectionTitle('联系人'),
          for (final friend in friends)
            PMListRow(
              key: ValueKey('search-friend-${friend.id}'),
              leading: PMUserAvatar(user: friend),
              title: Text(
                friend.displayName.isNotEmpty
                    ? friend.displayName
                    : friend.username,
              ),
              subtitle: Text('@${friend.username}'),
              trailing: _openingSearchTarget == 'user:${friend.id}'
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: () => unawaited(_openFriendChat(friend)),
            ),
        ],
        _buildSearchSectionTitle('消息'),
        if (_isSearchingMessages)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_messageSearchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              '消息搜索失败: $_messageSearchError',
              style: const TextStyle(color: AppColors.error),
            ),
          )
        else if (_messageHits.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              noLocalHits ? '没有找到与“$query”相关的内容' : '没有相关消息',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          for (final message in _messageHits) _buildMessageHit(message),
      ],
    );
  }

  Widget _buildMessageHit(Message message) {
    final chat = _chats.where((item) => item.id == message.chatRoomId);
    final chatName = chat.isEmpty ? '聊天' : chat.first.name;
    return PMListRow(
      key: ValueKey('search-message-${message.id}'),
      leading: const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
      title: Text(
        message.resolvedFileLabel,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$chatName · ${message.senderName} · '
        '${timeago.format(message.timestamp, locale: 'zh')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _openingSearchTarget == 'message:${message.id}'
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: () => unawaited(_openMessageHit(message)),
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
              unawaited(_loadChats(showLoading: false));
            }
          },
        );
      },
    );
  }

  Widget _buildChatItem(Chat chat) {
    final selected = widget.selectedChatId == chat.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: PMSpacing.xs),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            unawaited(_showDesktopChatMenu(chat, details.globalPosition)),
        child: PMCard(
          padding: EdgeInsets.zero,
          elevated: false,
          background: selected
              ? AppColors.pixelBlue
              : (chat.isPinned ? AppColors.cloud : AppColors.surface),
          child: PMListRow(
            leading: _buildChatAvatar(chat),
            title: Row(children: [
              Expanded(
                  child: Text(chat.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (chat.isPinned)
                const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.push_pin_rounded,
                        size: 12, color: AppColors.textTertiary)),
            ]),
            subtitle: Text(chat.lastMessage?.resolvedFileLabel ?? '开始你们的对话',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (chat.lastMessage != null)
                    Text(
                        timeago.format(chat.lastMessage!.timestamp,
                            locale: 'zh'),
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textTertiary)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (chat.isMuted)
                      const Icon(Icons.volume_off_outlined,
                          size: 14, color: AppColors.textTertiary),
                    if (chat.unreadCount > 0)
                      Badge(
                          label: Text(_hasUnreadMention(chat)
                              ? '@'
                              : chat.unreadCount > 99
                                  ? '99+'
                                  : '${chat.unreadCount}'),
                          backgroundColor: AppColors.primary),
                    SizedBox(
                        width: 28,
                        height: 28,
                        child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: '会话操作',
                            icon: const Icon(Icons.more_horiz, size: 18),
                            onPressed: () => _showMobileChatMenu(chat))),
                  ]),
                ]),
            onTap: () => unawaited(_openChatFromSearch(chat)),
            onLongPress: () => _showMobileChatMenu(chat),
          ),
        ),
      ),
    );
  }

  Widget _buildChatAvatar(Chat chat) {
    final peers = chat.participants.where((user) => user.id != _currentUserId);
    final peer =
        chat.type == ChatType.private && peers.isNotEmpty ? peers.first : null;
    final url = peer?.avatarUrl ?? chat.avatarUrl;
    return PMUserAvatar.raw(
      size: 44,
      imageUrl: url == null ? null : ApiConstants.resolveFileUrl(url),
      fallbackText: peer?.displayName ?? chat.name,
      isGroup: chat.type == ChatType.group,
      status: peer == null
          ? null
          : PMOnlineStatus.fromUserStatus(peer.onlineStatus),
      showOnlineDot: peer != null,
    );
  }
}
