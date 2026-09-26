part of '../workspace_page.dart';

extension _WorkspaceActions1Parts on _WorkspacePageState {
  void _selectWorkspace(Workspace workspace) {
    _setViewState(() {
      _selectedWorkspace = workspace;
      _folderStack.clear();
      _selectedFileIds.clear();
      _contents = const WorkspaceContents(folders: [], files: []);
      _clearPreviewState();
    });
    _loadContents();
  }

  void _backToWorkspaceList() {
    _setViewState(() {
      _selectedWorkspace = null;
      _folderStack.clear();
      _selectedFileIds.clear();
      _contents = const WorkspaceContents(folders: [], files: []);
      _clearPreviewState();
    });
  }

  void _clearPreviewState() {
    _selectedPreviewFile = null;
    _selectedPreview = null;
    _isLoadingPreview = false;
    _previewError = null;
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
      _setViewState(() {
        _workspaces = [workspace, ..._workspaces];
        _selectedWorkspace = workspace;
        _folderStack.clear();
        _clearPreviewState();
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

  /// 从系统拖进内容区的文件，逐个上传到当前文件夹。
  Future<void> _uploadDroppedFiles(DroppedFileBatch batch) async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    final skipped = batch.skippedMessage;
    if (batch.files.isEmpty) {
      if (skipped != null) _showSnackBar(skipped, isError: true);
      return;
    }
    final folderId = _folderStack.isEmpty ? null : _folderStack.last.id;
    var uploaded = 0;
    final failures = <String>[];
    for (final file in batch.files) {
      try {
        await _service.uploadFile(
          workspaceId: workspace.id,
          folderId: folderId,
          file: PickedWorkspaceFile(
            name: file.name,
            size: file.size,
            path: file.path,
            bytes: file.bytes,
          ),
        );
        uploaded++;
      } catch (error) {
        failures.add('${file.name}: $error');
      }
    }
    if (!mounted) return;
    if (uploaded > 0) {
      await _loadContents();
      await _refreshSelectedWorkspace();
    }
    if (failures.isNotEmpty) {
      _showSnackBar('上传失败 ${failures.join('；')}', isError: true);
    } else {
      _showSnackBar(
        [
          '已上传 $uploaded 个文件',
          if (skipped != null) skipped,
        ].join('，'),
      );
    }
  }

  Future<void> _downloadFile(WorkspaceFileItem file) async {
    try {
      final downloaded = await _service.downloadFile(file);
      final result = await file_save.saveBytesAsFile(
        bytes: downloaded.bytes,
        name: downloaded.name,
        mimeType: downloaded.mimeType ?? file.mimeType,
      );
      final text = result.describe(downloaded.name);
      if (text != null) _showSnackBar(text, isError: !result.isSaved);
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
    _showSnackBar(opened ? '已打开 ${preview.name}' : '当前平台无法打开预览，请下载查看');
  }

  Future<void> _openTextEditor(WorkspaceFileItem file) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkspaceTextEditorPage(
          workspaceId: file.workspaceId,
          fileId: file.id,
          fileName: file.displayName,
          service: _service,
        ),
      ),
    );
    if (!mounted) return;
    // Refresh contents so the bumped version / updatedAt is reflected.
    _loadContents();
  }

  Future<void> _previewFile(WorkspaceFileItem file) async {
    _setViewState(() {
      _selectedPreviewFile = file;
      _selectedPreview = null;
      _previewError = null;
      _isLoadingPreview = true;
    });

    try {
      final preview = await _service.previewFile(file);
      if (!mounted) return;
      _setViewState(() {
        _selectedPreview = preview;
        _isLoadingPreview = false;
      });
      if (MediaQuery.sizeOf(context).width < 1440) {
        await _showMobilePreviewSheet(file, preview);
      }
    } catch (error) {
      if (mounted) {
        _setViewState(() {
          _previewError = error.toString();
          _isLoadingPreview = false;
        });
      }
      _showSnackBar('预览失败: $error', isError: true);
    }
  }

  Future<void> _showMobilePreviewSheet(
    WorkspaceFileItem file,
    DownloadedWorkspaceFile preview,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _WorkspacePreviewChrome(
          file: file,
          onClose: () => Navigator.of(context).pop(),
          onDownload: () {
            Navigator.of(context).pop();
            _downloadFile(file);
          },
          child: _buildPreviewBody(file, preview),
        ),
      ),
    );
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
      if (_selectedPreviewFile?.id == file.id) {
        _setViewState(_clearPreviewState);
      }
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
}
