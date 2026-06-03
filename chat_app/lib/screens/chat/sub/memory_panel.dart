import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../../../design/design.dart';
import '../../../models/memory_entry.dart';
import '../../../services/memory_service.dart';

/// F2 — room memory library panel. Standalone (not a `part of chat_screen`) so it can
/// be unit-tested with a fake [MemoryService]; `chat_screen` mounts it as the 4th tab of
/// the desktop info side panel via `_buildMemoryPanel()`.
///
/// List order: pinned ROOM entries first, then ROOM by updatedAt desc, then the viewer's
/// own PRIVATE entries. PRIVATE entries authored by others are filtered client-side as a
/// defence-in-depth layer on top of the server's `requireAccessible` enforcement.
class MemoryPanel extends StatefulWidget {
  const MemoryPanel({
    super.key,
    required this.service,
    required this.roomId,
    required this.currentUserId,
    this.resolveUserName,
    this.resolveBotName,
  });

  final MemoryService service;
  final int roomId;

  /// Current viewer's user id (String, matching User.id). Used to gate edit/delete to the
  /// author and to filter out other users' PRIVATE entries defensively.
  final String? currentUserId;

  final String Function(int userId)? resolveUserName;
  final String Function(int botConfigId)? resolveBotName;

  @override
  State<MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends State<MemoryPanel> {
  final TextEditingController _searchController = TextEditingController();
  List<MemoryEntry> _memories = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Viewer authored this entry (gates edit/delete client-side; server also enforces).
  bool _isAuthor(MemoryEntry e) =>
      e.authorUserId != null &&
      e.authorUserId.toString() == widget.currentUserId;

  bool _canEdit(MemoryEntry e) => _isAuthor(e);

  int _rank(MemoryEntry e) {
    if (e.isRoom && e.pinned) return 0;
    if (e.isRoom) return 1;
    return 2; // own PRIVATE
  }

  List<MemoryEntry> _sortAndFilter(List<MemoryEntry> raw) {
    // Defence-in-depth: never render another user's PRIVATE entry even if the server
    // somehow returned one.
    final visible =
        raw.where((e) => e.isRoom || _isAuthor(e)).toList(growable: false);
    final sorted = [...visible]..sort((a, b) {
        final byRank = _rank(a).compareTo(_rank(b));
        if (byRank != 0) return byRank;
        final at = a.updatedAt ?? a.createdAt;
        final bt = b.updatedAt ?? b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at); // newest first
      });
    return sorted;
  }

  Future<void> _load() async {
    // Re-entered from pin/archive/delete/edit after their own network awaits; the
    // panel (info-panel tab 3) can be disposed mid-flight, so guard before setState.
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.service.listMemories(
        roomId: widget.roomId,
        q: _query.isEmpty ? null : _query,
      );
      if (!mounted) return;
      setState(() {
        _memories = _sortAndFilter(raw);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _togglePin(MemoryEntry e) async {
    try {
      await widget.service
          .setPinned(roomId: widget.roomId, memoryId: e.id, pinned: !e.pinned);
      await _load();
    } catch (err) {
      _snack('操作失败: $err', error: true);
    }
  }

  Future<void> _toggleArchive(MemoryEntry e) async {
    try {
      await widget.service.setArchived(
          roomId: widget.roomId, memoryId: e.id, archived: !e.archived);
      await _load();
    } catch (err) {
      _snack('操作失败: $err', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d';
  }

  String _authorLabel(MemoryEntry e) {
    if (e.authorBotConfigId != null) {
      final name = widget.resolveBotName?.call(e.authorBotConfigId!);
      return name?.isNotEmpty == true ? name! : 'AI';
    }
    if (e.authorUserId != null) {
      final name = widget.resolveUserName?.call(e.authorUserId!);
      return name?.isNotEmpty == true ? name! : '成员';
    }
    return '系统';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '搜索记忆',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    _query = value.trim();
                    _load();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            PMButton(
              label: '添加',
              icon: Icons.add_rounded,
              compact: true,
              onPressed: () => _openEditor(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return PMEmptyState(
        icon: Icons.error_outline_rounded,
        title: '加载记忆失败',
        subtitle: _error,
        action: PMButton(label: '重试', icon: Icons.refresh, onPressed: _load),
      );
    }
    if (_memories.isEmpty) {
      return PMEmptyState(
        icon: Icons.lightbulb_outline_rounded,
        title: '还没有记忆',
        subtitle: '记录本群的关键事实，AI 与成员都能引用。',
        action: PMButton(
          label: '添加第一条',
          icon: Icons.add_rounded,
          onPressed: () => _openEditor(),
        ),
      );
    }
    return ListView.separated(
      itemCount: _memories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _memoryCard(_memories[index]),
    );
  }

  Widget _memoryCard(MemoryEntry e) {
    final canEdit = _canEdit(e);
    return PMCard(
      key: ValueKey('memory-card-${e.id}'),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e.pinned)
                const Padding(
                  padding: EdgeInsets.only(right: 6, top: 2),
                  child: Icon(Icons.push_pin_rounded,
                      size: 16, color: AppColors.warning),
                ),
              Expanded(
                child: Text(
                  e.title.isNotEmpty ? e.title : '(无标题)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('memory-menu-${e.id}'),
                icon: const Icon(Icons.more_vert_rounded, size: 18),
                onSelected: (value) => _onMenu(value, e),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'pin',
                    child: Text(e.pinned ? '取消置顶' : '置顶'),
                  ),
                  if (canEdit)
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(e.archived ? '取消归档' : '归档'),
                  ),
                  if (canEdit)
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
          if (e.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                e.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.4),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (e.isPrivate)
                const PMChip(
                  label: '私有',
                  icon: Icons.lock_outline_rounded,
                  selected: true,
                  color: Color(0xFF7C3AED),
                ),
              PMChip(
                label: _authorLabel(e),
                icon: e.authorBotConfigId != null
                    ? Icons.smart_toy_rounded
                    : Icons.person_rounded,
                color: e.authorBotConfigId != null
                    ? AppColors.secondaryDark
                    : AppColors.primary,
              ),
              Text(
                _relativeTime(e.updatedAt ?? e.createdAt),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onMenu(String value, MemoryEntry e) {
    switch (value) {
      case 'pin':
        _togglePin(e);
        break;
      case 'edit':
        _openEditor(existing: e);
        break;
      case 'archive':
        _toggleArchive(e);
        break;
      case 'delete':
        _confirmDelete(e);
        break;
    }
  }

  Future<void> _confirmDelete(MemoryEntry e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PMDialogHeader(title: '删除记忆', showHandle: false),
        content: Text('确定删除「${e.title.isNotEmpty ? e.title : '该记忆'}」吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.deleteMemory(roomId: widget.roomId, memoryId: e.id);
      await _load();
    } catch (err) {
      _snack('删除失败: $err', error: true);
    }
  }

  Future<void> _openEditor({MemoryEntry? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MemoryEditorDialog(
        service: widget.service,
        roomId: widget.roomId,
        existing: existing,
      ),
    );
    if (saved == true) {
      await _load();
    }
  }
}

/// Add / edit dialog. A dedicated StatefulWidget so its TextEditingControllers are
/// owned by State and disposed only when the route is removed (avoids "controller used
/// after disposed" when the parent disposes them while the close animation runs).
class _MemoryEditorDialog extends StatefulWidget {
  const _MemoryEditorDialog({
    required this.service,
    required this.roomId,
    this.existing,
  });

  final MemoryService service;
  final int roomId;
  final MemoryEntry? existing;

  @override
  State<_MemoryEditorDialog> createState() => _MemoryEditorDialogState();
}

class _MemoryEditorDialogState extends State<_MemoryEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _keywords;
  late MemoryVisibility _visibility;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _content = TextEditingController(text: widget.existing?.content ?? '');
    _keywords = TextEditingController(text: widget.existing?.keywords ?? '');
    _visibility = widget.existing?.visibility ?? MemoryVisibility.room;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _keywords.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写标题')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await widget.service.createMemory(
          roomId: widget.roomId,
          title: title,
          content: _content.text.trim(),
          keywords: _keywords.text.trim(),
          visibility: _visibility,
        );
      } else {
        await widget.service.updateMemory(
          roomId: widget.roomId,
          memoryId: widget.existing!.id,
          title: title,
          content: _content.text.trim(),
          keywords: _keywords.text.trim(),
          visibility: _visibility,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $err'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: PMDialogHeader(
        title: widget.existing == null ? '添加记忆' : '编辑记忆',
        showHandle: false,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  PMChip(
                    label: '群共享',
                    icon: Icons.groups_rounded,
                    selected: _visibility == MemoryVisibility.room,
                    onTap: () =>
                        setState(() => _visibility = MemoryVisibility.room),
                  ),
                  PMChip(
                    label: '私有',
                    icon: Icons.lock_outline_rounded,
                    color: const Color(0xFF7C3AED),
                    selected: _visibility == MemoryVisibility.private,
                    onTap: () =>
                        setState(() => _visibility = MemoryVisibility.private),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _content,
                maxLength: 8000,
                maxLines: 5,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: '内容',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keywords,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '关键词（可选，便于检索）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        PMButton(
          label: '保存',
          loading: _saving,
          compact: true,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
