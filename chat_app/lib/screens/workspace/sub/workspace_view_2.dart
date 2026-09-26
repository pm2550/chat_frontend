part of '../workspace_page.dart';

extension _WorkspaceView2Parts on _WorkspacePageState {
  Widget _buildToolbar(Workspace workspace) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '返回工作区列表',
                onPressed: _backToWorkspaceList,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 6),
              PMSymbolIcon(
                _workspaceSymbol(workspace.workspaceType),
                size: 20,
                color: AppColors.primary,
              ),
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
                      if (_selectedFileIds.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () =>
                              _setViewState(_selectedFileIds.clear),
                          icon: const Icon(Icons.check_box_outlined, size: 18),
                          label: Text('已选 ${_selectedFileIds.length}'),
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
              _setViewState(() {
                _folderStack.clear();
                _clearPreviewState();
              });
              _loadContents();
            },
            icon: const Icon(Icons.home_work_outlined, size: 18),
            label: const Text('根目录'),
          ),
          for (var index = 0; index < _folderStack.length; index++) ...[
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            TextButton(
              onPressed: () {
                _setViewState(() {
                  _folderStack.removeRange(index + 1, _folderStack.length);
                  _clearPreviewState();
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
    return GridView.builder(
      padding: const EdgeInsets.all(PMSpacing.l),
      itemCount: itemCount,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisSpacing: PMSpacing.m,
        crossAxisSpacing: PMSpacing.m,
        childAspectRatio: 1.08,
      ),
      itemBuilder: (context, index) {
        if (index < _contents.folders.length) {
          final folder = _contents.folders[index];
          return PMCard(
            interactive: true,
            elevated: false,
            onTap: () {
              _setViewState(() {
                _folderStack.add(folder);
                _selectedFileIds.clear();
                _clearPreviewState();
              });
              _loadContents();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(PMRadius.m),
                      ),
                      child: const Icon(
                        Icons.folder,
                        color: AppColors.warning,
                      ),
                    ),
                    const Spacer(),
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
                      icon:
                          Icon(folder.isLocked ? Icons.lock_open : Icons.lock),
                      onPressed: () => _toggleFolderLock(folder),
                    ),
                  ],
                ),
                const SizedBox(height: PMSpacing.m),
                Text(
                  folder.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: PMSpacing.xs),
                Text(
                  folder.isLocked ? '文件夹 · 已锁定' : '文件夹',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: '移入回收站',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteFolder(folder),
                  ),
                ),
              ],
            ),
          );
        }
        final file = _contents.files[index - _contents.folders.length];
        final selected = _selectedFileIds.contains(file.id);
        return Stack(
          children: [
            Positioned.fill(
              child: PMAttachmentCard(
                type: _workspaceAttachmentType(file),
                name: file.displayName,
                sizeText: [
                  file.isBotFile
                      ? 'Bot: ${file.sourceBotName ?? '未知'}'
                      : file.createdByName ?? '用户上传',
                  'v${file.currentVersion}',
                  if (file.fileSize != null) _formatBytes(file.fileSize!),
                  if (file.scanStatus != null) _scanLabel(file.scanStatus!),
                ].join(' · '),
                forcePreview: file.isImage,
                onTap: () => file.isPreviewable
                    ? _previewFile(file)
                    : _downloadFile(file),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Checkbox(
                value: selected,
                onChanged: (_) {
                  _setViewState(() {
                    if (selected) {
                      _selectedFileIds.remove(file.id);
                    } else {
                      _selectedFileIds.add(file.id);
                    }
                  });
                },
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _openTextEditor(file);
                      break;
                    case 'versions':
                      _showVersions(file);
                      break;
                    case 'permission':
                      _showPermissionDialog(
                        resourceType: 'FILE',
                        resourceId: file.id,
                        resourceName: file.displayName,
                      );
                      break;
                    case 'replace':
                      _uploadFile(replaceFile: file);
                      break;
                    case 'lock':
                      _toggleFileLock(file);
                      break;
                    case 'download':
                      _downloadFile(file);
                      break;
                    case 'delete':
                      _deleteFile(file);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (_isEditableText(file))
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(value: 'versions', child: Text('版本')),
                  const PopupMenuItem(value: 'permission', child: Text('授权')),
                  const PopupMenuItem(value: 'replace', child: Text('上传新版本')),
                  PopupMenuItem(
                    value: 'lock',
                    child: Text(file.isLocked ? '解锁' : '锁定'),
                  ),
                  const PopupMenuItem(value: 'download', child: Text('下载')),
                  const PopupMenuItem(value: 'delete', child: Text('移入回收站')),
                ],
              ),
            ),
            if (file.isLocked)
              const Positioned(
                right: 48,
                top: 16,
                child: Icon(Icons.lock, color: AppColors.warning, size: 18),
              ),
          ],
        );
      },
    );
  }

  Widget _buildState(
      {required IconData icon,
      required String title,
      required String subtitle,
      required String actionLabel,
      required VoidCallback onAction}) {
    return Center(
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(PMSpacing.xl),
            child: PMEmptyState(
              icon: icon,
              title: title,
              subtitle: subtitle,
              action: PMButton(
                  label: actionLabel, icon: Icons.add, onPressed: onAction),
            )));
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
}
