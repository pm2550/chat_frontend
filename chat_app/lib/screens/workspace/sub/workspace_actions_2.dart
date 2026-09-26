part of '../workspace_page.dart';

extension _WorkspaceActions2Parts on _WorkspacePageState {
  Future<void> _showPermissionDialog({
    required String resourceType,
    int? resourceId,
    required String resourceName,
  }) async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    final idController = TextEditingController();
    final searchController = TextEditingController();
    var principalType = 'USER';
    var accessLevel = 'VIEW';
    var isSearching = false;
    var isSaving = false;
    var isRefreshing = false;
    List<User> searchResults = [];
    List<WorkspacePermissionEntry> permissions = [];
    String? permissionsError;

    Future<void> refreshPermissions(StateSetter? setDialogState) async {
      setDialogState?.call(() {
        isRefreshing = true;
        permissionsError = null;
      });
      try {
        final next = await _service.listPermissions(workspace.id);
        void apply() {
          permissions = next;
          isRefreshing = false;
        }

        if (setDialogState == null) {
          apply();
        } else if (mounted) {
          setDialogState(apply);
        }
      } catch (error) {
        void apply() {
          permissionsError = error.toString();
          isRefreshing = false;
        }

        if (setDialogState == null) {
          apply();
        } else if (mounted) {
          setDialogState(apply);
        }
      }
    }

    await refreshPermissions(null);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> runSearch() async {
            final keyword = searchController.text.trim();
            if (principalType != 'USER' || keyword.isEmpty) return;
            setDialogState(() => isSearching = true);
            try {
              final users = await _service.searchUsers(keyword, limit: 8);
              if (!context.mounted) return;
              setDialogState(() {
                searchResults = users;
                isSearching = false;
              });
            } catch (error) {
              if (!context.mounted) return;
              setDialogState(() => isSearching = false);
              _showSnackBar('搜索失败: $error', isError: true);
            }
          }

          Future<void> grant() async {
            final principalId = int.tryParse(idController.text.trim());
            if (principalId == null) {
              _showSnackBar('请输入有效 ID', isError: true);
              return;
            }
            setDialogState(() => isSaving = true);
            try {
              await _service.grantPermission(
                workspaceId: workspace.id,
                resourceType: resourceType,
                resourceId: resourceId,
                principalType: principalType,
                principalId: principalId,
                accessLevel: accessLevel,
              );
              if (!context.mounted) return;
              await refreshPermissions(setDialogState);
              setDialogState(() {
                isSaving = false;
                idController.clear();
                searchController.clear();
                searchResults = [];
              });
              _showSnackBar('权限已更新');
            } catch (error) {
              if (context.mounted) {
                setDialogState(() => isSaving = false);
              }
              _showSnackBar('授权失败: $error', isError: true);
            }
          }

          Future<void> revoke(WorkspacePermissionEntry permission) async {
            try {
              await _service.revokePermission(
                workspaceId: workspace.id,
                permissionId: permission.id,
              );
              await refreshPermissions(setDialogState);
              _showSnackBar('权限已撤销');
            } catch (error) {
              _showSnackBar('撤销失败: $error', isError: true);
            }
          }

          final sortedPermissions = [...permissions]..sort((left, right) {
              final leftCurrent = _isCurrentPermission(
                left,
                resourceType,
                resourceId,
              );
              final rightCurrent = _isCurrentPermission(
                right,
                resourceType,
                resourceId,
              );
              if (leftCurrent == rightCurrent) {
                return left.id.compareTo(right.id);
              }
              return leftCurrent ? -1 : 1;
            });

          return AlertDialog(
            title: Text('授权：$resourceName'),
            content: SizedBox(
              width: 760,
              height: 640,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: principalType,
                          decoration: const InputDecoration(labelText: '对象'),
                          items: const [
                            DropdownMenuItem(value: 'USER', child: Text('用户')),
                            DropdownMenuItem(value: 'BOT', child: Text('Bot')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                principalType = value;
                                searchResults = [];
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: accessLevel,
                          decoration: const InputDecoration(labelText: '权限'),
                          items: const [
                            DropdownMenuItem(value: 'VIEW', child: Text('查看')),
                            DropdownMenuItem(value: 'EDIT', child: Text('编辑')),
                            DropdownMenuItem(
                                value: 'MANAGE', child: Text('管理')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => accessLevel = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: idController,
                    decoration: InputDecoration(
                      labelText: principalType == 'BOT' ? 'Bot ID' : '用户 ID',
                      prefixIcon: const Icon(Icons.tag),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (principalType == 'USER') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            decoration: const InputDecoration(
                              labelText: '搜索用户填入 ID',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onSubmitted: (_) => runSearch(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: isSearching ? null : runSearch,
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('搜索'),
                        ),
                      ],
                    ),
                    if (searchResults.isNotEmpty)
                      SizedBox(
                        height: 160,
                        child: ListView.separated(
                          itemCount: searchResults.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final user = searchResults[index];
                            return ListTile(
                              dense: true,
                              title: Text(user.displayName.isNotEmpty
                                  ? user.displayName
                                  : user.username),
                              subtitle:
                                  Text('@${user.username} · ID ${user.id}'),
                              onTap: () {
                                setDialogState(
                                    () => idController.text = user.id);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '显式权限',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '刷新权限',
                        onPressed: isRefreshing
                            ? null
                            : () => refreshPermissions(setDialogState),
                        icon: isRefreshing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: permissionsError != null
                        ? _DialogStateBlock(
                            icon: Icons.cloud_off_outlined,
                            title: '权限列表加载失败',
                            subtitle: permissionsError!,
                          )
                        : sortedPermissions.isEmpty
                            ? const _DialogStateBlock(
                                icon: Icons.key_off_outlined,
                                title: '暂无显式授权',
                                subtitle: '成员角色仍然会按拥有者、管理员、编辑者和查看者生效。',
                              )
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: AppColors.borderLight),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListView.separated(
                                  itemCount: sortedPermissions.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final permission = sortedPermissions[index];
                                    final isCurrent = _isCurrentPermission(
                                      permission,
                                      resourceType,
                                      resourceId,
                                    );
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        permission.principalType == 'BOT'
                                            ? Icons.smart_toy_outlined
                                            : Icons.person_outline,
                                        color: isCurrent
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                      ),
                                      title: Text(
                                        permission.principalName ??
                                            '${permission.principalType} ${permission.principalId}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        [
                                          _resourceLabel(permission),
                                          _accessLabel(permission.accessLevel),
                                          if (permission.createdByName != null)
                                            '授权人 ${permission.createdByName}',
                                        ].join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: IconButton(
                                        tooltip: '撤销权限',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => revoke(permission),
                                      ),
                                    );
                                  },
                                ),
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: isSaving ? null : grant,
                child: Text(isSaving ? '保存中' : '保存权限'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showTrash() async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    WorkspaceTrash trash;
    try {
      trash = await _service.listTrash(workspace.id);
    } catch (error) {
      _showSnackBar('回收站加载失败: $error', isError: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> reloadTrash() async {
            final next = await _service.listTrash(workspace.id);
            setDialogState(() => trash = next);
          }

          Future<void> restoreFolder(WorkspaceFolder folder) async {
            try {
              await _service.restoreFolder(
                workspaceId: folder.workspaceId,
                folderId: folder.id,
              );
              await reloadTrash();
              await _loadContents();
              await _refreshSelectedWorkspace();
              _showSnackBar('文件夹已恢复');
            } catch (error) {
              _showSnackBar('恢复失败: $error', isError: true);
            }
          }

          Future<void> restoreFile(WorkspaceFileItem file) async {
            try {
              await _service.restoreFile(
                workspaceId: file.workspaceId,
                fileId: file.id,
              );
              await reloadTrash();
              await _loadContents();
              await _refreshSelectedWorkspace();
              _showSnackBar('文件已恢复');
            } catch (error) {
              _showSnackBar('恢复失败: $error', isError: true);
            }
          }

          final total = trash.folders.length + trash.files.length;
          return AlertDialog(
            title: Text('${workspace.name} 回收站'),
            content: SizedBox(
              width: 680,
              height: 520,
              child: total == 0
                  ? const Center(child: Text('回收站为空'))
                  : ListView(
                      children: [
                        for (final folder in trash.folders)
                          ListTile(
                            leading: const Icon(Icons.folder_delete_outlined),
                            title: Text(folder.name),
                            subtitle: Text([
                              '文件夹',
                              if (folder.deletedByName != null)
                                '删除者 ${folder.deletedByName}',
                              if (folder.deletedAt != null)
                                _formatDate(folder.deletedAt!),
                            ].join(' · ')),
                            trailing: FilledButton(
                              onPressed: () => restoreFolder(folder),
                              child: const Text('恢复'),
                            ),
                          ),
                        for (final file in trash.files)
                          ListTile(
                            leading: const Icon(Icons.restore_page_outlined),
                            title: Text(file.displayName),
                            subtitle: Text([
                              if (file.fileSize != null)
                                _formatBytes(file.fileSize!),
                              if (file.deletedByName != null)
                                '删除者 ${file.deletedByName}',
                              if (file.deletedAt != null)
                                _formatDate(file.deletedAt!),
                            ].join(' · ')),
                            trailing: FilledButton(
                              onPressed: () => restoreFile(file),
                              child: const Text('恢复'),
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showMaintenance() async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    WorkspaceMaintenanceResult result;
    try {
      result = await _service.cleanupOrphans(workspace.id);
    } catch (error) {
      _showSnackBar('维护检查失败: $error', isError: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> cleanup() async {
            try {
              final next = await _service.cleanupOrphans(
                workspace.id,
                dryRun: false,
              );
              setDialogState(() => result = next);
              _showSnackBar('孤儿文件清理完成');
            } catch (error) {
              _showSnackBar('清理失败: $error', isError: true);
            }
          }

          return AlertDialog(
            title: Text('${workspace.name} 存储维护'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('发现 ${result.orphanCount} 个孤儿对象，'
                      '共 ${_formatBytes(result.bytes)}。'),
                  if (result.deletedCount > 0)
                    Text('本次已清理 ${result.deletedCount} 个对象。'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: result.fileNames.isEmpty
                        ? const Center(child: Text('没有需要清理的对象'))
                        : ListView(
                            children: result.fileNames
                                .map((name) => Text(name))
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                onPressed:
                    result.orphanCount == 0 || !result.dryRun ? null : cleanup,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('清理孤儿对象'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleWorkspaceLock() async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    try {
      final updated = await _service.setWorkspaceLock(
        workspace.id,
        locked: !workspace.isLocked,
        reason: workspace.isLocked ? null : '网页端锁定',
      );
      if (!mounted) return;
      _setViewState(() {
        _selectedWorkspace = updated;
        _workspaces = _workspaces
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    } catch (error) {
      _showSnackBar('锁定失败: $error', isError: true);
    }
  }
}
