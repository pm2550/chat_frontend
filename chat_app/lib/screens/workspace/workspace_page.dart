import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/user.dart';
import '../../models/workspace.dart';
import '../../services/file_save.dart' as file_save;
import '../../services/workspace_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    this.workspaceService,
  });

  final WorkspaceService? workspaceService;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late final WorkspaceService _service;
  final List<WorkspaceFolder> _folderStack = [];
  List<Workspace> _workspaces = [];
  Workspace? _selectedWorkspace;
  WorkspaceContents _contents = const WorkspaceContents(folders: [], files: []);
  bool _isLoading = true;
  bool _isLoadingContents = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.workspaceService ?? WorkspaceService();
    _loadWorkspaces();
  }

  Future<void> _loadWorkspaces() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final workspaces = await _service.listWorkspaces();
      if (!mounted) return;
      setState(() {
        _workspaces = workspaces;
        _selectedWorkspace = workspaces.isNotEmpty ? workspaces.first : null;
        _folderStack.clear();
        _isLoading = false;
      });
      if (_selectedWorkspace != null) {
        await _loadContents();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadContents() async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    setState(() => _isLoadingContents = true);
    try {
      final contents = await _service.getContents(
        workspace.id,
        folderId: _folderStack.isEmpty ? null : _folderStack.last.id,
      );
      if (!mounted) return;
      setState(() {
        _contents = contents;
        _isLoadingContents = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingContents = false);
      _showSnackBar('资料库加载失败: $error', isError: true);
    }
  }

  void _selectWorkspace(Workspace workspace) {
    setState(() {
      _selectedWorkspace = workspace;
      _folderStack.clear();
      _contents = const WorkspaceContents(folders: [], files: []);
    });
    _loadContents();
  }

  Future<void> _refreshSelectedWorkspace() async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    try {
      final updated = await _service.getWorkspace(workspace.id);
      if (!mounted) return;
      setState(() {
        _selectedWorkspace = updated;
        _workspaces = _workspaces
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    } catch (_) {
      // The contents list is still useful even if the summary refresh fails.
    }
  }

  Future<void> _createWorkspace() async {
    final result = await _showTextDialog(
      title: '新建资料库',
      label: '资料库名称',
      actionLabel: '创建',
      secondaryLabel: '类型',
      secondaryOptions: const {
        'TEAM': '团队',
        'PERSONAL': '个人',
        'SERVICE': '服务',
      },
    );
    if (result == null) return;
    try {
      final workspace = await _service.createWorkspace(
        name: result.text,
        workspaceType: result.option ?? 'TEAM',
      );
      if (!mounted) return;
      setState(() {
        _workspaces = [workspace, ..._workspaces];
        _selectedWorkspace = workspace;
        _folderStack.clear();
      });
      await _loadContents();
    } catch (error) {
      _showSnackBar('创建失败: $error', isError: true);
    }
  }

  Future<void> _createFolder() async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    final result = await _showTextDialog(
      title: '新建文件夹',
      label: '文件夹名称',
      actionLabel: '创建',
    );
    if (result == null) return;
    try {
      await _service.createFolder(
        workspaceId: workspace.id,
        name: result.text,
        parentFolderId: _folderStack.isEmpty ? null : _folderStack.last.id,
      );
      await _loadContents();
    } catch (error) {
      _showSnackBar('创建失败: $error', isError: true);
    }
  }

  Future<void> _uploadFile({WorkspaceFileItem? replaceFile}) async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;

    final uploadFile = PickedWorkspaceFile(
      name: file.name,
      size: file.size,
      path: file.path,
      bytes: file.bytes,
    );
    try {
      if (replaceFile == null) {
        await _service.uploadFile(
          workspaceId: workspace.id,
          folderId: _folderStack.isEmpty ? null : _folderStack.last.id,
          file: uploadFile,
        );
      } else {
        await _service.addVersion(
          workspaceId: workspace.id,
          fileId: replaceFile.id,
          file: uploadFile,
          versionNote: '网页端上传新版本',
        );
      }
      await _loadContents();
      await _refreshSelectedWorkspace();
      _showSnackBar(replaceFile == null ? '文件已上传' : '新版本已上传');
    } catch (error) {
      _showSnackBar('上传失败: $error', isError: true);
    }
  }

  Future<void> _downloadFile(WorkspaceFileItem file) async {
    try {
      final downloaded = await _service.downloadFile(file);
      final saved = await file_save.saveBytesAsFile(
        bytes: downloaded.bytes,
        name: downloaded.name,
        mimeType: downloaded.mimeType ?? file.mimeType,
      );
      _showSnackBar(saved
          ? '已下载 ${downloaded.name}'
          : '已取回 ${downloaded.name} (${_formatBytes(downloaded.bytes.length)})');
    } catch (error) {
      _showSnackBar('下载失败: $error', isError: true);
    }
  }

  Future<void> _openPreviewInNewTab(
    WorkspaceFileItem file,
    DownloadedWorkspaceFile preview,
  ) async {
    final opened = await file_save.openBytesInNewTab(
      bytes: preview.bytes,
      name: preview.name,
      mimeType: preview.mimeType ?? file.mimeType,
    );
    _showSnackBar(opened ? '已打开 ${preview.name}' : '当前平台不支持新窗口预览，请下载查看');
  }

  Future<void> _previewFile(WorkspaceFileItem file) async {
    try {
      final preview = await _service.previewFile(file);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(file.displayName),
          content: SizedBox(
            width: 760,
            height: 520,
            child: _buildPreviewBody(file, preview),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _downloadFile(file);
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('下载'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      _showSnackBar('预览失败: $error', isError: true);
    }
  }

  Future<void> _deleteFile(WorkspaceFileItem file) async {
    final confirmed = await _confirm(
      title: '移入回收站',
      message: '确认把 ${file.displayName} 移入回收站？',
    );
    if (!confirmed) return;
    try {
      await _service.deleteFile(workspaceId: file.workspaceId, fileId: file.id);
      await _loadContents();
      await _refreshSelectedWorkspace();
      _showSnackBar('文件已移入回收站');
    } catch (error) {
      _showSnackBar('删除失败: $error', isError: true);
    }
  }

  Future<void> _toggleFolderLock(WorkspaceFolder folder) async {
    try {
      await _service.setFolderLock(
        workspaceId: folder.workspaceId,
        folderId: folder.id,
        locked: !folder.isLocked,
        reason: folder.isLocked ? null : '网页端锁定',
      );
      await _loadContents();
    } catch (error) {
      _showSnackBar('锁定失败: $error', isError: true);
    }
  }

  Future<void> _deleteFolder(WorkspaceFolder folder) async {
    final confirmed = await _confirm(
      title: '移入回收站',
      message: '确认把文件夹 ${folder.name} 和其中的文件移入回收站？',
    );
    if (!confirmed) return;
    try {
      await _service.deleteFolder(
        workspaceId: folder.workspaceId,
        folderId: folder.id,
      );
      await _loadContents();
      await _refreshSelectedWorkspace();
      _showSnackBar('文件夹已移入回收站');
    } catch (error) {
      _showSnackBar('删除失败: $error', isError: true);
    }
  }

  Future<void> _restoreVersion(
    WorkspaceFileItem file,
    WorkspaceVersion version,
  ) async {
    final confirmed = await _confirm(
      title: '恢复版本',
      message: '确认把 ${file.displayName} 恢复到 v${version.versionNumber}？',
    );
    if (!confirmed) return;
    try {
      await _service.restoreVersion(
        workspaceId: file.workspaceId,
        fileId: file.id,
        versionNumber: version.versionNumber,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await _loadContents();
      await _refreshSelectedWorkspace();
      _showSnackBar('版本已恢复为新版本');
    } catch (error) {
      _showSnackBar('恢复失败: $error', isError: true);
    }
  }

  Future<void> _showMembers() async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    List<WorkspaceMember> members = [];
    try {
      members = await _service.listMembers(workspace.id);
    } catch (error) {
      _showSnackBar('成员加载失败: $error', isError: true);
      return;
    }

    if (!mounted) return;
    final searchController = TextEditingController();
    var selectedRole = 'VIEWER';
    var isSearching = false;
    List<User> searchResults = [];

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> refreshMembers() async {
            final nextMembers = await _service.listMembers(workspace.id);
            setDialogState(() => members = nextMembers);
          }

          Future<void> runSearch() async {
            final keyword = searchController.text.trim();
            if (keyword.isEmpty) return;
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

          Future<void> upsertMember(int userId, String role) async {
            try {
              await _service.addMember(
                workspaceId: workspace.id,
                userId: userId,
                role: role,
              );
              await refreshMembers();
              _showSnackBar('成员权限已更新');
            } catch (error) {
              _showSnackBar('成员更新失败: $error', isError: true);
            }
          }

          return AlertDialog(
            title: Text('${workspace.name} 成员'),
            content: SizedBox(
              width: 720,
              height: 560,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: const InputDecoration(
                            labelText: '搜索用户名或昵称',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onSubmitted: (_) => runSearch(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      DropdownButton<String>(
                        value: selectedRole,
                        items: const [
                          DropdownMenuItem(value: 'VIEWER', child: Text('可查看')),
                          DropdownMenuItem(value: 'EDITOR', child: Text('可编辑')),
                          DropdownMenuItem(value: 'ADMIN', child: Text('管理员')),
                          DropdownMenuItem(
                              value: 'SERVICE', child: Text('服务账号')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => selectedRole = value);
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: isSearching ? null : runSearch,
                        icon: isSearching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.person_search, size: 18),
                        label: const Text('搜索'),
                      ),
                    ],
                  ),
                  if (searchResults.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.borderLight),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SizedBox(
                        height: 128,
                        child: ListView.separated(
                          itemCount: searchResults.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final user = searchResults[index];
                            final userId = int.tryParse(user.id);
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.person_add_alt_1),
                              title: Text(user.displayName.isNotEmpty
                                  ? user.displayName
                                  : user.username),
                              subtitle:
                                  Text('@${user.username} · ID ${user.id}'),
                              trailing: FilledButton(
                                onPressed: userId == null
                                    ? null
                                    : () => upsertMember(userId, selectedRole),
                                child: const Text('加入'),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '当前成员',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: members.isEmpty
                        ? const Center(child: Text('暂无成员'))
                        : ListView.separated(
                            itemCount: members.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final member = members[index];
                              return ListTile(
                                leading:
                                    const Icon(Icons.account_circle_outlined),
                                title: Text(member.displayName.isNotEmpty
                                    ? member.displayName
                                    : member.username),
                                subtitle: Text(
                                    '@${member.username} · ID ${member.userId}'),
                                trailing: DropdownButton<String>(
                                  value: member.role,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'OWNER', child: Text('拥有者')),
                                    DropdownMenuItem(
                                        value: 'ADMIN', child: Text('管理员')),
                                    DropdownMenuItem(
                                        value: 'EDITOR', child: Text('可编辑')),
                                    DropdownMenuItem(
                                        value: 'VIEWER', child: Text('可查看')),
                                    DropdownMenuItem(
                                        value: 'SERVICE', child: Text('服务账号')),
                                  ],
                                  onChanged: member.role == 'OWNER'
                                      ? null
                                      : (role) {
                                          if (role != null) {
                                            upsertMember(member.userId, role);
                                          }
                                        },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

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
      setState(() {
        _selectedWorkspace = updated;
        _workspaces = _workspaces
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    } catch (error) {
      _showSnackBar('锁定失败: $error', isError: true);
    }
  }

  Future<void> _toggleFileLock(WorkspaceFileItem file) async {
    try {
      await _service.setFileLock(
        workspaceId: file.workspaceId,
        fileId: file.id,
        locked: !file.isLocked,
        reason: file.isLocked ? null : '网页端锁定',
      );
      await _loadContents();
    } catch (error) {
      _showSnackBar('锁定失败: $error', isError: true);
    }
  }

  Future<void> _showVersions(WorkspaceFileItem file) async {
    try {
      final versions = await _service.listVersions(
        workspaceId: file.workspaceId,
        fileId: file.id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${file.displayName} 版本'),
          content: SizedBox(
            width: 520,
            child: versions.isEmpty
                ? const Text('暂无版本')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: versions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final version = versions[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.1),
                          child: Text('v${version.versionNumber}'),
                        ),
                        title: Text(version.originalName),
                        subtitle: Text(
                          [
                            version.uploadedByBotName ??
                                version.uploadedByName ??
                                '未知提交者',
                            if (version.fileSize != null)
                              _formatBytes(version.fileSize!),
                            if (version.createdAt != null)
                              _formatDate(version.createdAt!),
                            if (version.scanStatus != null)
                              _scanLabel(version.scanStatus!),
                          ].join(' · '),
                        ),
                        trailing: TextButton.icon(
                          onPressed: () => _restoreVersion(file, version),
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('恢复'),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      _showSnackBar('版本加载失败: $error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PMBreakpoints.isDesktop(context)) {
      return _buildDesktop();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('资料库')),
      body: _buildBody(isDesktop: false),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploadFile,
        child: const Icon(Icons.upload_file),
      ),
    );
  }

  Widget _buildDesktop() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: PMChatPattern(
        dense: true,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                PMDesktopHeader(
                  title: '资料库',
                  subtitle: '个人、团队和服务文件集中管理，支持权限、锁定和版本记录',
                  icon: Icons.snippet_folder,
                  actions: [
                    OutlinedButton.icon(
                      onPressed: _loadWorkspaces,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('刷新'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _createWorkspace,
                      icon: const Icon(Icons.create_new_folder, size: 18),
                      label: const Text('新建资料库'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(child: _buildBody(isDesktop: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody({required bool isDesktop}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildState(
        icon: Icons.cloud_off,
        title: '资料库加载失败',
        subtitle: _error!,
        actionLabel: '重试',
        onAction: _loadWorkspaces,
      );
    }
    if (_workspaces.isEmpty) {
      return _buildState(
        icon: Icons.snippet_folder_outlined,
        title: '还没有资料库',
        subtitle: '创建一个团队或服务资料库，用来存放用户和 Bot 提交的文件。',
        actionLabel: '新建资料库',
        onAction: _createWorkspace,
      );
    }
    if (!isDesktop) {
      return Column(
        children: [
          _buildMobileWorkspaceSelector(),
          Expanded(child: _buildContentPanel()),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 320, child: _buildWorkspaceList()),
        const SizedBox(width: 18),
        Expanded(child: _buildContentPanel()),
      ],
    );
  }

  Widget _buildWorkspaceList() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: _workspaces.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final workspace = _workspaces[index];
          final selected = workspace.id == _selectedWorkspace?.id;
          return Material(
            color: selected ? AppColors.pixelBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              selected: selected,
              leading: Icon(_workspaceIcon(workspace.workspaceType)),
              title: Text(
                workspace.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  _workspaceTypeLabel(workspace.workspaceType),
                  workspace.myAccessLevel ?? 'NONE',
                  if (workspace.isLocked) '已锁定',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing:
                  workspace.isLocked ? const Icon(Icons.lock, size: 18) : null,
              onTap: () => _selectWorkspace(workspace),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileWorkspaceSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: DropdownButtonFormField<int>(
        initialValue: _selectedWorkspace?.id,
        decoration: const InputDecoration(labelText: '资料库'),
        items: _workspaces
            .map(
              (workspace) => DropdownMenuItem<int>(
                value: workspace.id,
                child: Text(workspace.name),
              ),
            )
            .toList(),
        onChanged: (id) {
          final workspace = _workspaces.firstWhere((item) => item.id == id);
          _selectWorkspace(workspace);
        },
      ),
    );
  }

  Widget _buildContentPanel() {
    final workspace = _selectedWorkspace;
    if (workspace == null) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildToolbar(workspace),
          const Divider(height: 1),
          _buildBreadcrumbs(),
          const Divider(height: 1),
          Expanded(
            child: _isLoadingContents
                ? const Center(child: CircularProgressIndicator())
                : _buildContentsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(Workspace workspace) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_workspaceIcon(workspace.workspaceType),
                  color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      [
                        _workspaceTypeLabel(workspace.workspaceType),
                        workspace.myAccessLevel ?? 'NONE',
                        workspace.botAccessEnabled ? '允许 Bot 写入' : 'Bot 写入关闭',
                        if (workspace.isLocked) '已锁定',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: workspace.isLocked ? '解除资料库锁定' : '锁定资料库',
                onPressed: _toggleWorkspaceLock,
                icon: Icon(workspace.isLocked ? Icons.lock_open : Icons.lock),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(flex: 2, child: _buildQuota(workspace)),
              const SizedBox(width: 12),
              Flexible(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showPermissionDialog(
                          resourceType: 'WORKSPACE',
                          resourceName: workspace.name,
                        ),
                        icon: const Icon(Icons.key_outlined, size: 18),
                        label: const Text('授权'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showMembers,
                        icon: const Icon(Icons.groups_2_outlined, size: 18),
                        label: const Text('成员'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showTrash,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('回收站'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showMaintenance,
                        icon: const Icon(
                          Icons.cleaning_services_outlined,
                          size: 18,
                        ),
                        label: const Text('维护'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _createFolder,
                        icon: const Icon(Icons.create_new_folder, size: 18),
                        label: const Text('文件夹'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _uploadFile(),
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('上传'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuota(Workspace workspace) {
    final quota = workspace.quotaBytes ?? 0;
    final used = workspace.usedBytes ?? 0;
    final progress = quota <= 0 ? 0.0 : (used / quota).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          quota <= 0
              ? '已用 ${_formatBytes(used)}'
              : '已用 ${_formatBytes(used)} / ${_formatBytes(quota)}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: AppColors.borderLight,
            color: progress > 0.9 ? AppColors.error : AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbs() {
    return SizedBox(
      height: 48,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          TextButton.icon(
            onPressed: () {
              setState(() => _folderStack.clear());
              _loadContents();
            },
            icon: const Icon(Icons.home_work_outlined, size: 18),
            label: const Text('根目录'),
          ),
          for (var index = 0; index < _folderStack.length; index++) ...[
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            TextButton(
              onPressed: () {
                setState(() {
                  _folderStack.removeRange(index + 1, _folderStack.length);
                });
                _loadContents();
              },
              child: Text(_folderStack[index].name),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContentsList() {
    final itemCount = _contents.folders.length + _contents.files.length;
    if (itemCount == 0) {
      return _buildState(
        icon: Icons.inbox_outlined,
        title: '这个位置是空的',
        subtitle: '可以上传用户文件、Bot 产物，或创建文件夹进行分组。',
        actionLabel: '上传文件',
        onAction: () => _uploadFile(),
      );
    }
    return ListView.separated(
      itemCount: itemCount,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index < _contents.folders.length) {
          final folder = _contents.folders[index];
          return ListTile(
            leading: const Icon(Icons.folder, color: AppColors.warning),
            title:
                Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(folder.isLocked ? '文件夹 · 已锁定' : '文件夹'),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: '授权',
                  icon: const Icon(Icons.key_outlined),
                  onPressed: () => _showPermissionDialog(
                    resourceType: 'FOLDER',
                    resourceId: folder.id,
                    resourceName: folder.name,
                  ),
                ),
                IconButton(
                  tooltip: folder.isLocked ? '解锁' : '锁定',
                  icon: Icon(folder.isLocked ? Icons.lock_open : Icons.lock),
                  onPressed: () => _toggleFolderLock(folder),
                ),
                IconButton(
                  tooltip: '移入回收站',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteFolder(folder),
                ),
              ],
            ),
            onTap: () {
              setState(() => _folderStack.add(folder));
              _loadContents();
            },
          );
        }
        final file = _contents.files[index - _contents.folders.length];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Icon(
              _fileIcon(file),
              color: AppColors.primary,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  file.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (file.isLocked) const Icon(Icons.lock, size: 16),
            ],
          ),
          subtitle: Text(
            [
              file.isBotFile
                  ? 'Bot: ${file.sourceBotName ?? '未知'}'
                  : file.createdByName ?? '用户上传',
              'v${file.currentVersion}',
              if (file.fileSize != null) _formatBytes(file.fileSize!),
              if (file.scanStatus != null) _scanLabel(file.scanStatus!),
              if (file.storageProvider != null) file.storageProvider!,
              if (file.updatedAt != null) _formatDate(file.updatedAt!),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: '预览',
                icon: const Icon(Icons.visibility_outlined),
                onPressed: file.isPreviewable ? () => _previewFile(file) : null,
              ),
              IconButton(
                tooltip: '版本',
                icon: const Icon(Icons.history),
                onPressed: () => _showVersions(file),
              ),
              IconButton(
                tooltip: '授权',
                icon: const Icon(Icons.key_outlined),
                onPressed: () => _showPermissionDialog(
                  resourceType: 'FILE',
                  resourceId: file.id,
                  resourceName: file.displayName,
                ),
              ),
              IconButton(
                tooltip: '上传新版本',
                icon: const Icon(Icons.upload),
                onPressed: () => _uploadFile(replaceFile: file),
              ),
              IconButton(
                tooltip: file.isLocked ? '解锁' : '锁定',
                icon: Icon(file.isLocked ? Icons.lock_open : Icons.lock),
                onPressed: () => _toggleFileLock(file),
              ),
              IconButton(
                tooltip: '下载',
                icon: const Icon(Icons.download),
                onPressed: () => _downloadFile(file),
              ),
              IconButton(
                tooltip: '移入回收站',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteFile(file),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildState({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }

  Future<_TextDialogResult?> _showTextDialog({
    required String title,
    required String label,
    required String actionLabel,
    String? secondaryLabel,
    Map<String, String>? secondaryOptions,
  }) async {
    final controller = TextEditingController();
    String? selected = secondaryOptions?.keys.first;
    return showDialog<_TextDialogResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(labelText: label),
                  onSubmitted: (_) {
                    final text = controller.text.trim();
                    if (text.isNotEmpty) {
                      Navigator.of(context).pop(
                        _TextDialogResult(text, selected),
                      );
                    }
                  },
                ),
                if (secondaryOptions != null && secondaryLabel != null) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    decoration: InputDecoration(labelText: secondaryLabel),
                    items: secondaryOptions.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setDialogState(() => selected = value);
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.of(context).pop(_TextDialogResult(text, selected));
              },
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBody(
    WorkspaceFileItem file,
    DownloadedWorkspaceFile preview,
  ) {
    final mimeType = (preview.mimeType ?? file.mimeType ?? '').toLowerCase();
    if (mimeType.startsWith('image/') || file.isImage) {
      return InteractiveViewer(
        child: Center(
          child: Image.memory(
            Uint8List.fromList(preview.bytes),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _buildPreviewFallback(
              icon: Icons.broken_image_outlined,
              title: '图片预览失败',
              subtitle: '可以改用下载查看原文件。',
            ),
          ),
        ),
      );
    }
    if (mimeType.startsWith('text/') || file.isTextPreview) {
      final text = utf8.decode(preview.bytes, allowMalformed: true);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              height: 1.45,
            ),
          ),
        ),
      );
    }
    if (mimeType == 'application/pdf') {
      return _buildPdfPreview(file, preview);
    }
    return _buildPreviewFallback(
      icon: Icons.insert_drive_file_outlined,
      title: '此类型暂不支持预览',
      subtitle: '已登录用户仍可下载查看完整文件。',
    );
  }

  Widget _buildPdfPreview(
    WorkspaceFileItem file,
    DownloadedWorkspaceFile preview,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.picture_as_pdf_outlined,
            size: 56,
            color: AppColors.error,
          ),
          const SizedBox(height: 12),
          const Text(
            'PDF 预览已准备',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            '使用浏览器或系统 PDF 查看器打开完整文件。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openPreviewInNewTab(file, preview),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('打开 PDF'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewFallback({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  IconData _fileIcon(WorkspaceFileItem file) {
    final type = (file.mimeType ?? '').toLowerCase();
    final name = file.displayName.toLowerCase();
    if (file.isBotFile) return Icons.smart_toy_outlined;
    if (type.startsWith('image/')) return Icons.image_outlined;
    if (type == 'application/pdf' || name.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (name.endsWith('.zip') ||
        name.endsWith('.rar') ||
        name.endsWith('.7z')) {
      return Icons.inventory_2_outlined;
    }
    return Icons.description_outlined;
  }

  bool _isCurrentPermission(
    WorkspacePermissionEntry permission,
    String resourceType,
    int? resourceId,
  ) {
    return permission.resourceType == resourceType &&
        permission.resourceId == resourceId;
  }

  String _resourceLabel(WorkspacePermissionEntry permission) {
    final name = permission.resourceName;
    final label = switch (permission.resourceType) {
      'FILE' => '文件',
      'FOLDER' => '文件夹',
      _ => '资料库',
    };
    if (name == null || name.isEmpty) {
      return permission.resourceId == null
          ? label
          : '$label ${permission.resourceId}';
    }
    return '$label · $name';
  }

  String _accessLabel(String level) {
    return switch (level) {
      'MANAGE' => '可管理',
      'EDIT' => '可编辑',
      'VIEW' => '可查看',
      'NONE' => '无权限',
      _ => level,
    };
  }

  String _scanLabel(String status) {
    return switch (status) {
      'CLEAN' => '扫描通过',
      'PENDING' => '等待扫描',
      'BLOCKED' => '已拦截',
      'FAILED' => '扫描失败',
      _ => status,
    };
  }

  IconData _workspaceIcon(String type) {
    return switch (type) {
      'PERSONAL' => Icons.person_pin_circle_outlined,
      'SERVICE' => Icons.cloud_sync_outlined,
      _ => Icons.groups_2_outlined,
    };
  }

  String _workspaceTypeLabel(String type) {
    return switch (type) {
      'PERSONAL' => '个人资料库',
      'SERVICE' => '服务资料库',
      _ => '团队资料库',
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime date) {
    return DateFormat('MM-dd HH:mm').format(date.toLocal());
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }
}

class _TextDialogResult {
  const _TextDialogResult(this.text, this.option);

  final String text;
  final String? option;
}

class _DialogStateBlock extends StatelessWidget {
  const _DialogStateBlock({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
