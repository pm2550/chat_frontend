import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/user.dart';
import '../../models/workspace.dart';
import '../../services/file_save.dart' as file_save;
import '../../services/os_dropped_files.dart';
import '../../services/workspace_service.dart';
import 'workspace_text_editor_page.dart';
import '../../widgets/os_file_drop_target.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';

part 'sub/workspace_data.dart';
part 'sub/workspace_actions_1.dart';
part 'sub/workspace_actions_2.dart';
part 'sub/workspace_actions_3.dart';
part 'sub/workspace_view_1.dart';
part 'sub/workspace_view_2.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    this.workspaceService,
  });

  final WorkspaceService? workspaceService;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with AutomaticKeepAliveClientMixin<WorkspacePage> {
  late final WorkspaceService _service;
  final TextEditingController _workspaceSearchController =
      TextEditingController();
  final List<WorkspaceFolder> _folderStack = [];
  final Set<int> _selectedFileIds = {};
  List<Workspace> _workspaces = [];
  Workspace? _selectedWorkspace;
  WorkspaceContents _contents = const WorkspaceContents(folders: [], files: []);
  bool _isLoading = true;
  bool _isLoadingContents = false;
  bool _isOsDragActive = false;
  WorkspaceFileItem? _selectedPreviewFile;
  DownloadedWorkspaceFile? _selectedPreview;
  bool _isLoadingPreview = false;
  String? _previewError;
  String? _error;
  String _workspaceSearchQuery = '';
  String _workspaceSort = 'updated';

  @override
  void initState() {
    super.initState();
    _service = widget.workspaceService ?? WorkspaceService();
    _loadWorkspaces();
  }

  @override
  void dispose() {
    _workspaceSearchController.dispose();
    super.dispose();
  }

  // F6: only plain-text files are human-editable in this batch.
  static const Set<String> _editableExtensions = {'.txt'};

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (PMBreakpoints.isDesktop(context)) {
      return _buildDesktop();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('工作区'), actions: [
        IconButton(
            tooltip: '新建资料库',
            onPressed: _createWorkspace,
            icon: const Icon(Icons.create_new_folder_outlined))
      ]),
      body: _buildBody(isDesktop: false),
      floatingActionButton: _selectedWorkspace == null
          ? null
          : FloatingActionButton(
              tooltip: '上传文件',
              onPressed: _uploadFile,
              child: const Icon(Icons.upload_file),
            ),
    );
  }

  void _setViewState(VoidCallback change) {
    if (mounted) setState(change);
  }
}

class _WorkspacePreviewChrome extends StatelessWidget {
  const _WorkspacePreviewChrome({
    required this.file,
    required this.child,
    required this.onClose,
    required this.onDownload,
  });

  final WorkspaceFileItem file;
  final Widget child;
  final VoidCallback onClose;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return PMCard(
      radius: PMRadius.l,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(PMSpacing.l),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _previewAccent(file).withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(PMRadius.m),
                  ),
                  child: Icon(
                    _previewIcon(file),
                    color: _previewAccent(file),
                  ),
                ),
                const SizedBox(width: PMSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: PMSpacing.xs),
                      Text(
                        [
                          'v${file.currentVersion}',
                          if (file.fileSize != null)
                            _formatPreviewBytes(file.fileSize!),
                          if (file.scanStatus != null) file.scanStatus!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭预览',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(PMSpacing.l),
              child: child,
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),
          Padding(
            padding: const EdgeInsets.all(PMSpacing.l),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    file.isLocked ? '文件已锁定，编辑操作受权限限制。' : '预览不会离开当前目录。',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: PMSpacing.m),
                PMButton(
                  label: '下载',
                  icon: Icons.download_outlined,
                  compact: true,
                  variant: PMButtonVariant.secondary,
                  onPressed: onDownload,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _previewIcon(WorkspaceFileItem file) {
    final type = (file.mimeType ?? '').toLowerCase();
    final name = file.displayName.toLowerCase();
    if (file.isImage) return Icons.image_outlined;
    if (type == 'application/pdf' || name.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (file.isTextPreview) return Icons.article_outlined;
    if (type.contains('zip') || name.endsWith('.zip')) {
      return Icons.archive_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  static Color _previewAccent(WorkspaceFileItem file) {
    final type = (file.mimeType ?? '').toLowerCase();
    final name = file.displayName.toLowerCase();
    if (file.isImage) return AppColors.secondary;
    if (type == 'application/pdf' || name.endsWith('.pdf')) {
      return AppColors.error;
    }
    if (file.isTextPreview) return AppColors.primary;
    if (type.contains('zip') || name.endsWith('.zip')) {
      return AppColors.warning;
    }
    return AppColors.primaryDark;
  }
}

String _formatPreviewBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
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
