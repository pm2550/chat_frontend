part of '../contacts_page.dart';

extension _ContactsView1Parts on _ContactsPageState {
  Widget _buildDesktopScaffold() {
    return Scaffold(
        body: PMDesktopPage(
            maxWidth: 1120,
            child: Column(children: [
              PMPageHeader(title: '联系人', subtitle: '熟悉的人，随时都能找到', actions: [
                PMButton(
                    label: '管理分组',
                    icon: Icons.folder_open,
                    variant: PMButtonVariant.secondary,
                    onPressed: _showGroupManagementSheet),
              ]),
              const SizedBox(height: PMSpacing.xl),
              Expanded(
                  child: PMCard(
                      padding: EdgeInsets.zero,
                      radius: PMRadius.l,
                      child: Column(children: [
                        _buildSearchBox(),
                        Expanded(
                            child: _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : _errorMessage != null
                                    ? _buildErrorState()
                                    : RefreshIndicator(
                                        onRefresh: _loadContacts,
                                        child: _buildContactList())),
                      ]))),
            ])));
  }

  /// 桌面聊天页中间栏：只有搜索和联系人，点一个人切换到和他的私聊。
  Widget _buildCompactScaffold() {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
            child: Row(children: [
              const Expanded(
                child: Text('联系人',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: '添加联系人',
                icon: const Icon(Icons.person_add),
                onPressed: _showAddContactSheet,
              ),
            ]),
          ),
          _buildSearchBox(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorState()
                    : RefreshIndicator(
                        onRefresh: _loadContacts,
                        child: _buildContactList(),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildCountPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.pixelBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
        padding: const EdgeInsets.all(PMSpacing.l),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (value) => _setViewState(() => _searchQuery = value),
          decoration: InputDecoration(
            hintText: '搜索联系人',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _setViewState(() => _searchQuery = '');
                    }),
          ),
        ));
  }

  Widget _buildContactList() {
    final compact = widget.compact;
    final contacts = _filteredContactEntries;
    final groupChats = compact ? const <Chat>[] : _filteredGroupChats;
    final showQuickActions = _searchQuery.isEmpty && !compact;
    final showRequests = showQuickActions && _receivedRequests.isNotEmpty;
    final hasDirectoryItems = contacts.isNotEmpty || groupChats.isNotEmpty;

    if (!hasDirectoryItems && !showRequests && !showQuickActions) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: _buildEmptyState(),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (showQuickActions) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildQuickAction(
                    icon: Icons.group_add,
                    label: '新建群聊',
                    onTap: _showCreateGroupSheet,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQuickAction(
                    icon: isQrScanSupported
                        ? Icons.qr_code_scanner
                        : Icons.person_add_alt_1,
                    // 只有手机上真能打开摄像头时才叫“扫一扫”。
                    label: isQrScanSupported ? '扫一扫' : '加好友',
                    onTap: _openAddFriend,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (showRequests) ...[
          _buildSectionTitle('新的好友请求'),
          ..._receivedRequests.map(_buildRequestItem),
          const SizedBox(height: 8),
        ],
        if (groupChats.isNotEmpty) ...[
          _buildSectionTitle(
            '我的群聊',
            section: _ContactsPageState._sectionGroups,
            count: groupChats.length,
          ),
          if (!_isSectionCollapsed(_ContactsPageState._sectionGroups))
            ..._buildGroupedRoomWidgets(
                _ContactsPageState._sectionGroups, groupChats),
          const SizedBox(height: 12),
        ],
        if (contacts.isNotEmpty) ...[
          _buildSectionTitle(
            '联系人',
            section: _ContactsPageState._sectionContacts,
            count: contacts.length,
          ),
          if (!_isSectionCollapsed(_ContactsPageState._sectionContacts))
            ..._buildGroupedContactWidgets(
                _ContactsPageState._sectionContacts, contacts),
          const SizedBox(height: 16),
        ] else if (!hasDirectoryItems)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.42,
            child: _buildEmptyState(),
          ),
      ],
    );
  }

  Widget _buildQuickAction(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return PMCard(
      elevated: false,
      onTap: onTap,
      background: AppColors.pixelBlue,
      padding: const EdgeInsets.symmetric(
          vertical: PMSpacing.l, horizontal: PMSpacing.m),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: PMSpacing.s),
        Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }

  Widget _buildSectionTitle(
    String title, {
    String? section,
    int? count,
  }) {
    final collapsed = section != null && _isSectionCollapsed(section);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: InkWell(
        onTap: section == null ? null : () => _toggleSectionCollapsed(section),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count != null) ...[
                _buildCountPill(count),
                const SizedBox(width: 6),
              ],
              if (section != null)
                AnimatedRotation(
                  turns: collapsed ? 0 : 0.25,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
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
              '联系人加载失败',
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
              onPressed: _loadContacts,
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
          Icon(
            Icons.contacts_outlined,
            size: 80,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? '暂无联系人' : '没有找到相关联系人',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '点击右上角按钮添加联系人',
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

  List<Widget> _buildGroupedRoomWidgets(String section, List<Chat> chats) {
    final blocks = _groupItems<Chat>(
      section: section,
      items: chats,
      groupIdFor: (chat) =>
          _assignedGroupId(ContactGroupTargetType.room, chat.id),
    );
    return [
      for (final block in blocks) ...[
        _buildGroupBlockHeader(block),
        if (!_isGroupBlockCollapsed(block.collapseKey))
          ...block.items.map(_buildRoomItem),
      ],
    ];
  }

  List<Widget> _buildGroupedContactWidgets(
      String section, List<_ContactEntry> contacts) {
    final blocks = _groupItems<_ContactEntry>(
      section: section,
      items: contacts,
      groupIdFor: _assignedGroupIdForEntry,
    );
    return [
      for (final block in blocks) ...[
        _buildGroupBlockHeader(block),
        if (!_isGroupBlockCollapsed(block.collapseKey))
          ...([...block.items]..sort(_compareContactEntries))
              .map(_buildContactEntryItem),
      ],
    ];
  }

  Widget _buildGroupBlockHeader<T>(_ContactGroupBlock<T> block) {
    final collapsed = _isGroupBlockCollapsed(block.collapseKey);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
      child: InkWell(
        onTap: () => _toggleGroupBlockCollapsed(block.collapseKey),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(
                block.isUngrouped ? Icons.inbox_outlined : Icons.folder_open,
                size: 17,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  block.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildCountPill(block.items.length),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: collapsed ? 0 : 0.25,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestItem(FriendshipRequest request) {
    final user = request.user;
    return _buildUserCard(
      user: user,
      subtitle: '请求添加你为好友',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '拒绝',
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: () => _declineRequest(request),
          ),
          IconButton(
            tooltip: '接受',
            icon: const Icon(Icons.check, color: AppColors.success),
            onPressed: () => _acceptRequest(request),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomItem(Chat chat) {
    final isUnblocking = _unblockingRoomId == chat.id;
    void move() => _showRoomMoveToGroupSheet(chat);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: PMSpacing.l, vertical: PMSpacing.xs),
      child: GestureDetector(
          onSecondaryTapDown: (_) => move(),
          child: PMCard(
              elevated: false,
              padding: EdgeInsets.zero,
              child: PMListRow(
                onTap: () => _openChatRoom(chat),
                onLongPress: move,
                leading: _buildRoomAvatar(chat),
                title: Text(chat.name),
                subtitle: Text(
                    chat.lastMessage?.resolvedFileLabel ??
                        (chat.type == ChatType.group ? '群聊' : '私聊'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                badge: chat.isBlocked ? '已屏蔽' : null,
                badgeColor: AppColors.textSecondary,
                trailing: chat.isBlocked
                    ? TextButton(
                        onPressed: isUnblocking
                            ? null
                            : () => _setRoomBlocked(chat, false),
                        child: isUnblocking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('解除屏蔽'))
                    : null,
              ))),
    );
  }

  Widget _buildRoomAvatar(Chat chat) {
    return PMUserAvatar.raw(
        size: 44,
        imageUrl: chat.avatarUrl == null
            ? null
            : ApiConstants.resolveFileUrl(chat.avatarUrl!),
        fallbackText: chat.name,
        isGroup: chat.type == ChatType.group);
  }

  Widget _buildMoveGroupOption({
    required String label,
    required bool selected,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.primary : AppColors.textSecondary,
      ),
      title: Text(label),
      trailing: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: loading ? null : onTap,
    );
  }
}
