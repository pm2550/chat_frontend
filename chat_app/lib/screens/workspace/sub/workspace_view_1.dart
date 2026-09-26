part of '../workspace_page.dart';

extension _WorkspaceView1Parts on _WorkspacePageState {
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
                  title: '工作区',
                  subtitle: '把文件与灵感，放在触手可及的地方',
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
        subtitle: '为自己或团队创建一个资料库，收藏文件、整理项目，也能与聊天中的伙伴共享。',
        actionLabel: '新建资料库',
        onAction: _createWorkspace,
      );
    }
    if (_selectedWorkspace == null) {
      return _buildWorkspaceOverview(isDesktop: isDesktop);
    }
    if (!isDesktop) {
      return Column(
        children: [
          Expanded(child: _buildContentPanel()),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 220, child: _buildWorkspaceList()),
        const SizedBox(width: 18),
        Expanded(child: _buildContentPanel()),
        if (MediaQuery.sizeOf(context).width >= 1440) ...[
          const SizedBox(width: 18),
          SizedBox(width: 320, child: _buildPreviewPanel()),
        ],
      ],
    );
  }

  Widget _buildWorkspaceOverview({required bool isDesktop}) {
    final workspaces = _visibleWorkspaces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PMCard(
          elevated: false,
          padding: const EdgeInsets.all(PMSpacing.l),
          child: Wrap(
            spacing: PMSpacing.m,
            runSpacing: PMSpacing.m,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isDesktop ? 420 : double.infinity,
                child: TextField(
                  controller: _workspaceSearchController,
                  decoration: const InputDecoration(
                    hintText: '搜索工作区、类型或所有者',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      _setViewState(() => _workspaceSearchQuery = value),
                ),
              ),
              PMChip(
                label: '最近活动',
                icon: Icons.schedule,
                selected: _workspaceSort == 'updated',
                onTap: () => _setViewState(() => _workspaceSort = 'updated'),
              ),
              PMChip(
                label: '名称',
                icon: Icons.sort_by_alpha,
                selected: _workspaceSort == 'name',
                onTap: () => _setViewState(() => _workspaceSort = 'name'),
              ),
              PMChip(
                label: '文件量',
                icon: Icons.storage_outlined,
                selected: _workspaceSort == 'files',
                onTap: () => _setViewState(() => _workspaceSort = 'files'),
              ),
            ],
          ),
        ),
        const SizedBox(height: PMSpacing.l),
        Expanded(
          child: workspaces.isEmpty
              ? PMEmptyState(
                  icon: Icons.search_off,
                  title: '没有找到工作区',
                  subtitle: '换一个关键词，或创建新的个人、团队、服务资料库。',
                  action: PMButton(
                    label: '新建资料库',
                    icon: Icons.create_new_folder,
                    onPressed: _createWorkspace,
                  ),
                )
              : GridView.builder(
                  itemCount: workspaces.length,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isDesktop ? 420 : 640,
                    mainAxisSpacing: PMSpacing.l,
                    crossAxisSpacing: PMSpacing.l,
                    childAspectRatio: isDesktop ? 1.35 : 1.75,
                  ),
                  itemBuilder: (context, index) =>
                      _buildWorkspaceCard(workspaces[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceCard(Workspace workspace) {
    final quota = workspace.quotaBytes ?? 0;
    final used = workspace.usedBytes ?? 0;
    final progress = quota <= 0 ? 0.0 : (used / quota).clamp(0.0, 1.0);
    return PMCard(
      interactive: true,
      onTap: () => _selectWorkspace(workspace),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(PMRadius.l),
                ),
                child: PMSymbolIcon(
                  _workspaceSymbol(workspace.workspaceType),
                  size: 24,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: PMSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      [
                        _workspaceTypeLabel(workspace.workspaceType),
                        workspace.myAccessLevel ?? 'NONE',
                        if (workspace.isLocked) '已锁定',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (workspace.isLocked)
                const Icon(Icons.lock, color: AppColors.warning),
            ],
          ),
          const SizedBox(height: PMSpacing.l),
          Row(
            children: [
              for (final symbol in [
                PMSymbol.files,
                PMSymbol.files,
                PMSymbol.ai,
                PMSymbol.folder,
              ])
                Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: AppColors.cloud,
                    borderRadius: BorderRadius.circular(PMRadius.s),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Center(
                    child: PMSymbolIcon(
                      symbol,
                      size: 17,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                workspace.updatedAt == null
                    ? '暂无活动'
                    : _formatDate(workspace.updatedAt!),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: PMSpacing.l),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.borderLight,
              color: progress > 0.9 ? AppColors.error : AppColors.primary,
            ),
          ),
          const SizedBox(height: PMSpacing.s),
          Text(
            quota <= 0
                ? '已用 ${_formatBytes(used)}'
                : '已用 ${_formatBytes(used)} / ${_formatBytes(quota)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
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
            // 从文件管理器把文件拖进来，直接上传到当前文件夹（桌面端和网页版）。
            child: OsFileDropTarget(
              key: const Key('workspace-os-drop-target'),
              enabled: !workspace.isLocked,
              onDragActiveChanged: (active) {
                if (mounted) _setViewState(() => _isOsDragActive = active);
              },
              onFilesDropped: (batch) => _uploadDroppedFiles(batch),
              child: AnimatedContainer(
                duration: PMMotion.fast,
                decoration: BoxDecoration(
                  color: _isOsDragActive
                      ? AppColors.pixelBlue.withValues(alpha: 0.55)
                      : Colors.transparent,
                  border: _isOsDragActive
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                ),
                child: _isLoadingContents
                    ? const Center(child: CircularProgressIndicator())
                    : _buildContentsList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel() {
    final file = _selectedPreviewFile;
    final preview = _selectedPreview;

    if (file == null) {
      return const PMCard(
        radius: PMRadius.l,
        padding: EdgeInsets.all(PMSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.preview_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            SizedBox(height: PMSpacing.l),
            Text(
              '选择文件预览',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            SizedBox(height: PMSpacing.s),
            Text(
              '图片、文本和 PDF 会显示在这里，列表不会被弹窗遮住。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoadingPreview) {
      return _WorkspacePreviewChrome(
        file: file,
        onClose: () => _setViewState(_clearPreviewState),
        onDownload: () => _downloadFile(file),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_previewError != null) {
      return _WorkspacePreviewChrome(
        file: file,
        onClose: () => _setViewState(_clearPreviewState),
        onDownload: () => _downloadFile(file),
        child: PMErrorState(
          title: '预览失败',
          message: _previewError!,
          onRetry: () => _previewFile(file),
        ),
      );
    }

    return _WorkspacePreviewChrome(
      file: file,
      onClose: () => _setViewState(_clearPreviewState),
      onDownload: () => _downloadFile(file),
      child: preview == null
          ? const SizedBox.shrink()
          : _buildPreviewBody(file, preview),
    );
  }
}
