part of '../contacts_page.dart';

extension _ContactsActions2Parts on _ContactsPageState {
  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
    }
  }

  void _showAddContactSheet() {
    _addSearchController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        List<User> results = [];
        Set<String> requestedUserIds = {};
        bool isSearching = false;
        String? errorMessage;

        Future<void> runSearch(StateSetter setSheetState) async {
          final keyword = _addSearchController.text.trim();
          if (keyword.isEmpty) {
            setSheetState(() {
              results = [];
              errorMessage = null;
            });
            return;
          }

          setSheetState(() {
            isSearching = true;
            errorMessage = null;
          });

          try {
            final users = await _contactService.searchUsers(keyword);
            final contactIds = _contacts.map((user) => user.id).toSet();
            if (!sheetContext.mounted) return;
            setSheetState(() {
              results =
                  users.where((user) => !contactIds.contains(user.id)).toList();
              isSearching = false;
            });
          } catch (e) {
            if (!sheetContext.mounted) return;
            setSheetState(() {
              errorMessage = e.toString();
              isSearching = false;
            });
          }
        }

        Future<void> sendRequest(
          User user,
          StateSetter setSheetState,
        ) async {
          try {
            await _contactService.sendFriendRequest(user.id);
            if (!sheetContext.mounted) return;
            setSheetState(() {
              requestedUserIds = {...requestedUserIds, user.id};
            });
            _showSnackBar('好友请求已发送');
          } catch (e) {
            _showSnackBar(e.toString());
          }
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '添加联系人',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _addSearchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => runSearch(setSheetState),
                        decoration: InputDecoration(
                          hintText: '搜索用户名、昵称或邮箱',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () => runSearch(setSheetState),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isSearching)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        )
                      else if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        )
                      else if (results.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '输入关键词搜索用户',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final user = results[index];
                              final requested =
                                  requestedUserIds.contains(user.id);
                              return ListTile(
                                leading: _buildAvatar(user, radius: 22),
                                title: Text(
                                  _displayName(user),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '@${user.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: requested
                                    ? const Text(
                                        '已发送',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      )
                                    : FilledButton(
                                        onPressed: () => sendRequest(
                                          user,
                                          setSheetState,
                                        ),
                                        child: const Text('添加'),
                                      ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showContactMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新联系人'),
              onTap: () {
                Navigator.pop(context);
                _loadContacts();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('添加联系人'),
              onTap: () {
                Navigator.pop(context);
                _showAddContactSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('新建群聊'),
              onTap: () {
                Navigator.pop(context);
                _showCreateGroupSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('管理分组'),
              onTap: () {
                Navigator.pop(context);
                _showGroupManagementSheet();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateGroupSheet() {
    final nameController = TextEditingController();
    final selectedIds = <String>{};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '新建群聊',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '群聊名称'),
                  ),
                  const SizedBox(height: 12),
                  if (_contacts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('暂无联系人可加入群聊'),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _contacts.length,
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
                          final selected = selectedIds.contains(contact.id);
                          return CheckboxListTile(
                            value: selected,
                            title: Text(_displayName(contact)),
                            subtitle: Text('@${contact.username}'),
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selectedIds.add(contact.id);
                                } else {
                                  selectedIds.remove(contact.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          _showSnackBar('请输入群聊名称');
                          return;
                        }
                        try {
                          final chat = await _contactService.createGroupChat(
                            name: name,
                            memberIds: selectedIds.toList(),
                          );
                          if (!sheetContext.mounted || !mounted) return;
                          Navigator.pop(sheetContext);
                          await Navigator.pushNamed(
                            context,
                            '/chat/${chat.id}',
                            arguments: chat,
                          );
                        } catch (e) {
                          _showSnackBar('建群失败: $e');
                        }
                      },
                      child: const Text('创建'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(nameController.dispose);
  }

  Future<void> _openAddFriend() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddFriendScreen(
          contactService: _contactService,
          scanner: isQrScanSupported ? QrScannerPage.open : null,
        ),
      ),
    );
    if (mounted) {
      unawaited(_loadContacts(showLoading: false));
    }
  }
}
