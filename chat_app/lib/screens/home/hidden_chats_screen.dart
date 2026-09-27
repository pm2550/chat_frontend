import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/chat.dart';
import '../../services/chat_data_service.dart';

/// 被“移出列表”或“屏蔽”的会话。移出的会话在有人发新消息时会自动回到
/// 消息列表；屏蔽的不会。这里可以手动恢复它们。
///
/// 返回后调用方应强制刷新消息列表，恢复的会话才会出现。
class HiddenChatsScreen extends StatefulWidget {
  const HiddenChatsScreen({super.key, this.chatService});

  final ChatDataService? chatService;

  @override
  State<HiddenChatsScreen> createState() => _HiddenChatsScreenState();
}

class _HiddenChatsScreenState extends State<HiddenChatsScreen> {
  // 后端 summaries 接口单页最多 100 条。
  static const int _pageSize = 100;
  static const int _maxPages = 10;

  late final ChatDataService _chatService;
  final List<Chat> _chats = [];
  final Set<String> _restoring = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatDataService();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final hidden = <Chat>[];
      for (var page = 0; page < _maxPages; page++) {
        final rooms = await _chatService.getChatRooms(
          page: page,
          size: _pageSize,
          includeHidden: true,
          includeBlocked: true,
          forceRefresh: true,
        );
        hidden.addAll(rooms.where((chat) => chat.isHidden || chat.isBlocked));
        if (rooms.length < _pageSize) break;
      }
      if (!mounted) return;
      setState(() {
        _chats
          ..clear()
          ..addAll(hidden);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _restore(Chat chat) async {
    if (_restoring.contains(chat.id)) return;
    setState(() => _restoring.add(chat.id));
    try {
      if (chat.isBlocked) {
        await _chatService.unblockChatRoom(chat.id);
      } else {
        await _chatService.restoreChatRoom(chat.id);
      }
      if (!mounted) return;
      setState(() {
        _restoring.remove(chat.id);
        _chats.removeWhere((item) => item.id == chat.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${chat.name}」已回到消息列表')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _restoring.remove(chat.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('恢复失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('已移出的聊天')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return PMErrorState(message: error, onRetry: _load);
    }
    if (_chats.isEmpty) {
      return const PMEmptyState(
        icon: Icons.inbox_outlined,
        title: '没有被移出或屏蔽的聊天',
        subtitle: '在消息列表长按会话可以移出或屏蔽，之后能在这里恢复',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(PMSpacing.l),
      itemCount: _chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: PMSpacing.s),
      itemBuilder: (context, index) {
        final chat = _chats[index];
        final busy = _restoring.contains(chat.id);
        return PMCard(
          elevated: false,
          padding: EdgeInsets.zero,
          child: PMListRow(
            key: ValueKey('hidden-chat-${chat.id}'),
            leading: Icon(
              chat.isBlocked ? Icons.block : Icons.visibility_off_outlined,
              color: chat.isBlocked ? AppColors.error : AppColors.textSecondary,
            ),
            title:
                Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              chat.isBlocked ? '已屏蔽 · 新消息不会回到列表，也不计未读' : '已移出 · 有新消息时会自动回到列表',
            ),
            trailing: TextButton(
              onPressed: busy ? null : () => _restore(chat),
              child: Text(chat.isBlocked ? '取消屏蔽' : '恢复'),
            ),
          ),
        );
      },
    );
  }
}
