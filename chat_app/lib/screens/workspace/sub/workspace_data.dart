part of '../workspace_page.dart';

extension _WorkspaceData1Parts on _WorkspacePageState {
  Future<void> _loadWorkspaces() async {
    _setViewState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final workspaces = await _service.listWorkspaces();
      if (!mounted) return;
      final previousId = _selectedWorkspace?.id;
      Workspace? previous;
      if (previousId != null) {
        for (final workspace in workspaces) {
          if (workspace.id == previousId) {
            previous = workspace;
            break;
          }
        }
      }
      _setViewState(() {
        _workspaces = workspaces;
        _selectedWorkspace = previous;
        _folderStack.clear();
        _selectedFileIds.clear();
        _clearPreviewState();
        _isLoading = false;
      });
      if (_selectedWorkspace != null) {
        await _loadContents();
      }
    } catch (error) {
      if (!mounted) return;
      _setViewState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadContents() async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    _setViewState(() => _isLoadingContents = true);
    try {
      final contents = await _service.getContents(
        workspace.id,
        folderId: _folderStack.isEmpty ? null : _folderStack.last.id,
      );
      if (!mounted) return;
      _setViewState(() {
        _contents = contents;
        _isLoadingContents = false;
      });
    } catch (error) {
      if (!mounted) return;
      _setViewState(() => _isLoadingContents = false);
      _showSnackBar('资料库加载失败: $error', isError: true);
    }
  }

  Future<void> _refreshSelectedWorkspace() async {
    final workspace = _selectedWorkspace;
    if (workspace == null) return;
    try {
      final updated = await _service.getWorkspace(workspace.id);
      if (!mounted) return;
      _setViewState(() {
        _selectedWorkspace = updated;
        _workspaces = _workspaces
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    } catch (_) {
      // The contents list is still useful even if the summary refresh fails.
    }
  }

  bool _isEditableText(WorkspaceFileItem file) {
    if (file.isLocked || file.isDeleted) return false;
    final name = file.displayName.toLowerCase();
    return _WorkspacePageState._editableExtensions.any(name.endsWith);
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

  bool _isCurrentPermission(
    WorkspacePermissionEntry permission,
    String resourceType,
    int? resourceId,
  ) {
    return permission.resourceType == resourceType &&
        permission.resourceId == resourceId;
  }
}
