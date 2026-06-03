import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/workspace.dart';
import '../../services/workspace_service.dart';

/// F6 — inline plain-text editor for workspace files. Standalone full-page route so it
/// is independently testable with a fake [WorkspaceService]. No external editor
/// dependency: a monospace multiline TextField + version history from the existing
/// versions endpoint.
class WorkspaceTextEditorPage extends StatefulWidget {
  const WorkspaceTextEditorPage({
    super.key,
    required this.workspaceId,
    required this.fileId,
    this.fileName,
    this.service,
  });

  final int workspaceId;
  final int fileId;
  final String? fileName;
  final WorkspaceService? service;

  @override
  State<WorkspaceTextEditorPage> createState() =>
      _WorkspaceTextEditorPageState();
}

class _WorkspaceTextEditorPageState extends State<WorkspaceTextEditorPage> {
  late final WorkspaceService _service;
  final TextEditingController _controller = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _displayName = '';
  int _currentVersion = 1;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WorkspaceService();
    _displayName = widget.fileName ?? '';
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Re-entered from restore/conflict-reload after their own awaits; the route may be
    // popped mid-flight, so guard before the entry setState.
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await _service.readText(
        workspaceId: widget.workspaceId,
        fileId: widget.fileId,
      );
      if (!mounted) return;
      setState(() {
        _controller.text = text.content;
        _displayName = text.displayName;
        _currentVersion = text.currentVersion;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await _service.saveText(
        workspaceId: widget.workspaceId,
        fileId: widget.fileId,
        content: _controller.text,
      );
      if (!mounted) return;
      setState(() {
        _currentVersion = updated.currentVersion;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存成功 (版本 $_currentVersion)')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (error is WorkspaceException && error.isConflict) {
        _showConflictDialog();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('保存失败: $error'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _showConflictDialog() async {
    final reload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PMDialogHeader(title: '版本冲突', showHandle: false),
        content: const Text('文件已被更新, 请重新加载后再编辑。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重新加载'),
          ),
        ],
      ),
    );
    if (reload == true) await _load();
  }

  Future<void> _showVersionHistory() async {
    List<WorkspaceVersion> versions;
    try {
      versions = await _service.listVersions(
        workspaceId: widget.workspaceId,
        fileId: widget.fileId,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('读取版本失败: $error'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    if (!mounted) return;
    final recent = versions.take(20).toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PMDialogHeader(title: '历史版本', showHandle: false),
        content: SizedBox(
          width: 420,
          height: 360,
          child: recent.isEmpty
              ? const Center(child: Text('暂无历史版本'))
              : ListView.separated(
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final v = recent[index];
                    final isCurrent = v.versionNumber == _currentVersion;
                    return PMListRow(
                      title: Text('版本 ${v.versionNumber}'),
                      subtitle: Text(
                        v.versionNote?.isNotEmpty == true
                            ? v.versionNote!
                            : v.originalName,
                      ),
                      trailing: isCurrent
                          ? const PMChip(label: '当前', selected: true)
                          : TextButton(
                              onPressed: () =>
                                  _confirmRestore(context, v.versionNumber),
                              child: const Text('恢复'),
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
  }

  Future<void> _confirmRestore(BuildContext listContext, int versionNumber) async {
    Navigator.of(listContext).pop(); // close the version list first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PMDialogHeader(title: '恢复版本', showHandle: false),
        content: Text('确定将文件恢复到版本 $versionNumber 吗？这会生成一个新版本。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.restoreVersion(
        workspaceId: widget.workspaceId,
        fileId: widget.fileId,
        versionNumber: versionNumber,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已恢复到版本 $versionNumber')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('恢复失败: $error'), backgroundColor: AppColors.error),
      );
    }
  }

  int get _lineCount =>
      _controller.text.isEmpty ? 1 : '\n'.allMatches(_controller.text).length + 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName.isNotEmpty ? _displayName : '文本编辑'),
        actions: [
          IconButton(
            tooltip: '历史版本',
            icon: const Icon(Icons.history_rounded),
            onPressed: _loading ? null : _showVersionHistory,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PMSpacing.s),
            child: PMButton(
              label: '保存',
              icon: Icons.save_outlined,
              compact: true,
              loading: _saving,
              onPressed: _loading || _saving ? null : _save,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return PMEmptyState(
        icon: Icons.error_outline_rounded,
        title: '加载失败',
        subtitle: _error,
        action: PMButton(label: '重试', icon: Icons.refresh, onPressed: _load),
      );
    }
    return Column(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.4,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(PMSpacing.l),
              hintText: '在此编辑文本…',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: AppColors.cloud,
            border: Border(top: BorderSide(color: AppColors.borderLight)),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: PMSpacing.l, vertical: PMSpacing.s),
          child: Row(
            children: [
              Text('行 $_lineCount',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: PMSpacing.l),
              Text('字符 ${_controller.text.length}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const Spacer(),
              Text('当前版本 $_currentVersion',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
