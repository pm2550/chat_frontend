part of '../workspace_page.dart';

extension _WorkspaceActions3Parts on _WorkspacePageState {
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

  List<Workspace> get _visibleWorkspaces {
    final query = _workspaceSearchQuery.trim().toLowerCase();
    final filtered = _workspaces.where((workspace) {
      if (query.isEmpty) return true;
      return [
        workspace.name,
        workspace.description,
        workspace.ownerName,
        workspace.workspaceType,
      ].whereType<String>().any((value) => value.toLowerCase().contains(query));
    }).toList();
    filtered.sort((a, b) {
      return switch (_workspaceSort) {
        'name' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        'files' => (b.usedBytes ?? 0).compareTo(a.usedBytes ?? 0),
        _ =>
          (b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.updatedAt ??
                  a.createdAt ??
                  DateTime.fromMillisecondsSinceEpoch(0)),
      };
    });
    return filtered;
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

  AttachmentType _workspaceAttachmentType(WorkspaceFileItem file) {
    final type = (file.mimeType ?? '').toLowerCase();
    final name = file.displayName.toLowerCase();
    if (file.isImage) return AttachmentType.image;
    if (type.startsWith('video/')) return AttachmentType.video;
    if (type.startsWith('audio/')) return AttachmentType.voice;
    if (name.endsWith('.geojson') || name.endsWith('.kml')) {
      return AttachmentType.location;
    }
    return AttachmentType.file;
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
      'PERSONAL' => Icons.person,
      'SERVICE' => Icons.storage,
      _ => Icons.groups,
    };
  }

  PMSymbol _workspaceSymbol(String type) {
    return switch (type) {
      'PERSONAL' => PMSymbol.profile,
      'SERVICE' => PMSymbol.files,
      _ => PMSymbol.workspace,
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
