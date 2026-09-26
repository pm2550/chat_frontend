part of '../contacts_page.dart';

extension _ContactsActions1Parts on _ContactsPageState {
  bool get _canUseSnapshot =>
      widget.contactService == null && widget.chatService == null;

  void _applySnapshot(_ContactsSnapshot snapshot) {
    _contacts = List<User>.from(snapshot.contacts);
    _receivedRequests = List<FriendshipRequest>.from(snapshot.receivedRequests);
    _groupChats = List<Chat>.from(snapshot.groupChats);
    _privateChats = List<Chat>.from(snapshot.privateChats);
    _contactGroups = List<ContactGroup>.from(snapshot.contactGroups);
    _groupAssignmentsByTarget = Map<String, ContactGroupAssignment>.from(
      snapshot.groupAssignmentsByTarget,
    );
    _groupCollapsed = Map<String, bool>.from(snapshot.groupCollapsed);
  }

  Future<void> _toggleSectionCollapsed(String section) async {
    final next = !_isSectionCollapsed(section);
    _setViewState(() {
      _sectionCollapsed[section] = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_ContactsPageState._sectionPrefPrefix}$section', next);
  }

  Future<void> _toggleGroupBlockCollapsed(String key) async {
    final next = !_isGroupBlockCollapsed(key);
    _setViewState(() {
      _groupCollapsed = {..._groupCollapsed, key: next};
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_ContactsPageState._groupPrefPrefix}$key', next);
  }

  String _groupCollapseKey(String groupId) =>
      _ContactsPageState._groupCollapseKeyFor(groupId);

  String _ungroupedCollapseKey(String section) =>
      _ContactsPageState._ungroupedCollapseKeyFor(section);

  List<_ContactGroupBlock<T>> _groupItems<T>({
    required String section,
    required List<T> items,
    required String Function(T item) targetKeyFor,
  }) {
    final knownGroupIds = _contactGroups.map((group) => group.id).toSet();
    final grouped = <String, List<T>>{
      for (final group in _contactGroups) group.id: <T>[],
    };
    final ungrouped = <T>[];

    for (final item in items) {
      final assignment = _groupAssignmentsByTarget[targetKeyFor(item)];
      final groupId = assignment?.groupId;
      if (groupId != null && knownGroupIds.contains(groupId)) {
        grouped[groupId]!.add(item);
      } else {
        ungrouped.add(item);
      }
    }

    return [
      for (final group in _contactGroups)
        if ((grouped[group.id] ?? <T>[]).isNotEmpty)
          _ContactGroupBlock<T>(
            title: group.name,
            collapseKey: _groupCollapseKey(group.id),
            items: grouped[group.id]!,
          ),
      if (ungrouped.isNotEmpty)
        _ContactGroupBlock<T>(
          title: '未分组',
          collapseKey: _ungroupedCollapseKey(section),
          items: ungrouped,
          isUngrouped: true,
        ),
    ];
  }

  Future<void> _openChatRoom(Chat chat) async {
    await Navigator.pushNamed(context, '/chat/${chat.id}', arguments: chat);
    if (mounted) {
      await _loadContacts();
    }
  }

  Future<void> _unblockRoomFromContacts(Chat chat) async {
    if (_unblockingRoomId != null) return;
    _setViewState(() {
      _unblockingRoomId = chat.id;
    });
    try {
      await _chatService.unblockChatRoom(chat.id);
      if (!mounted) return;
      _showSnackBar('已解除屏蔽 ${chat.name}');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    } finally {
      if (mounted) {
        _setViewState(() {
          _unblockingRoomId = null;
        });
      }
    }
  }

  void _showMoveToGroupSheet({
    required ContactGroupTargetType targetType,
    required String targetId,
    required String title,
  }) {
    final targetKey = ContactGroupTargetKey.build(targetType, targetId);
    final currentGroupId = _groupAssignmentsByTarget[targetKey]?.groupId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '移动到分组',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showEditContactGroupSheet();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _buildMoveGroupOption(
                        label: '未分组',
                        selected: currentGroupId == null,
                        loading: _movingTargetKey == targetKey,
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _assignTargetToGroup(
                            targetType: targetType,
                            targetId: targetId,
                            groupId: null,
                          );
                        },
                      ),
                      for (final group in _contactGroups)
                        _buildMoveGroupOption(
                          label: group.name,
                          selected: currentGroupId == group.id,
                          loading: _movingTargetKey == targetKey,
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await _assignTargetToGroup(
                              targetType: targetType,
                              targetId: targetId,
                              groupId: group.id,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _assignTargetToGroup({
    required ContactGroupTargetType targetType,
    required String targetId,
    required String? groupId,
  }) async {
    final targetKey = ContactGroupTargetKey.build(targetType, targetId);
    if (_movingTargetKey != null) return;
    _setViewState(() {
      _movingTargetKey = targetKey;
    });
    try {
      await _contactService.assignContactGroupItem(
        targetType: targetType,
        targetId: targetId,
        groupId: groupId,
      );
      _showSnackBar(groupId == null ? '已移到未分组' : '已移动到分组');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    } finally {
      if (mounted) {
        _setViewState(() {
          _movingTargetKey = null;
        });
      }
    }
  }

  void _showGroupManagementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '分组管理',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showEditContactGroupSheet();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.borderLight),
                Flexible(
                  child: _contactGroups.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(28),
                          child: Text(
                            '暂无自定义分组',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _contactGroups.length,
                          itemBuilder: (context, index) {
                            final group = _contactGroups[index];
                            return ListTile(
                              leading: const Icon(Icons.folder_open),
                              title: Text(group.name),
                              subtitle: Text('排序 ${group.sortOrder}'),
                              trailing: Wrap(
                                spacing: 2,
                                children: [
                                  IconButton(
                                    tooltip: '上移',
                                    onPressed: index == 0
                                        ? null
                                        : () {
                                            Navigator.pop(sheetContext);
                                            _moveContactGroup(index, -1);
                                          },
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                                  IconButton(
                                    tooltip: '下移',
                                    onPressed:
                                        index == _contactGroups.length - 1
                                            ? null
                                            : () {
                                                Navigator.pop(sheetContext);
                                                _moveContactGroup(index, 1);
                                              },
                                    icon: const Icon(Icons.arrow_downward),
                                  ),
                                  IconButton(
                                    tooltip: '改名',
                                    onPressed: () {
                                      Navigator.pop(sheetContext);
                                      _showEditContactGroupSheet(group: group);
                                    },
                                    icon: const Icon(Icons.edit),
                                  ),
                                  IconButton(
                                    tooltip: '删除',
                                    onPressed: () {
                                      Navigator.pop(sheetContext);
                                      _confirmDeleteContactGroup(group);
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditContactGroupSheet({ContactGroup? group}) async {
    var draftName = group?.name ?? '';
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group == null ? '新建分组' : '重命名分组',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                TextFormField(
                  initialValue: draftName,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '分组名称'),
                  onChanged: (value) => draftName = value,
                  onFieldSubmitted: (value) =>
                      Navigator.pop(sheetContext, value.trim()),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(sheetContext, draftName.trim()),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (name == null || name.isEmpty) return;

    try {
      if (group == null) {
        await _contactService.createContactGroup(name);
        _showSnackBar('分组已创建');
      } else {
        await _contactService.updateContactGroup(
          group.id,
          name: name,
          sortOrder: group.sortOrder,
        );
        _showSnackBar('分组已更新');
      }
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _confirmDeleteContactGroup(ContactGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('删除「${group.name}」后，里面的联系人和会话会回到未分组。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _contactService.deleteContactGroup(group.id);
      _showSnackBar('分组已删除，条目已回到未分组');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _moveContactGroup(int index, int delta) async {
    final targetIndex = index + delta;
    if (targetIndex < 0 || targetIndex >= _contactGroups.length) return;
    final ids = _contactGroups.map((group) => group.id).toList();
    final moving = ids.removeAt(index);
    ids.insert(targetIndex, moving);
    try {
      await _contactService.reorderContactGroups(ids);
      _showSnackBar('分组排序已更新');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _acceptRequest(FriendshipRequest request) async {
    try {
      await _contactService.acceptFriendRequest(request.user.id);
      _showSnackBar('已添加 ${_displayName(request.user)}');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _declineRequest(FriendshipRequest request) async {
    try {
      await _contactService.declineFriendRequest(request.user.id);
      _showSnackBar('已拒绝好友请求');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _startChat(User contact) async {
    if (_openingChatUserId != null) {
      return;
    }

    _setViewState(() {
      _openingChatUserId = contact.id;
    });

    try {
      final Chat chat = await _contactService.createPrivateChat(contact.id);
      if (!mounted) return;
      await Navigator.pushNamed(context, '/chat/${chat.id}', arguments: chat);
    } catch (e) {
      if (mounted) {
        _showSnackBar(e.toString());
      }
    } finally {
      if (mounted) {
        _setViewState(() {
          _openingChatUserId = null;
        });
      }
    }
  }
}
