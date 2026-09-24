import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../services/chat_data_service.dart';
import '../chat/chat_screen.dart';

/// “我的收藏”：当前用户收藏过的消息（GET /users/me/starred，最新收藏在前）。
/// 点一条打开对应聊天并定位到该消息；星标按钮取消收藏。
class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key, this.chatService});

  final ChatDataService? chatService;

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  static const int _pageSize = 20;

  late final ChatDataService _chatService;
  final List<Message> _messages = [];
  final Map<String, Chat> _roomsById = {};
  final Set<String> _unstarring = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _nextPage = 0;
  String? _error;
  String? _openingMessageId;

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatDataService();
    timeago.setLocaleMessages('zh', timeago.ZhCnMessages());
    unawaited(_loadRooms());
    unawaited(_loadFirstPage());
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await _chatService.getChatRooms(size: 100);
      if (!mounted) return;
      setState(() {
        for (final room in rooms) {
          _roomsById[room.id] = room;
        }
      });
    } catch (_) {
      // 房间名只是辅助信息；拿不到时列表里显示“聊天”。
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await _chatService.getStarredMessages(size: _pageSize);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _hasMore = page.hasNext;
        _nextPage = page.currentPage + 1;
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

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _chatService.getStarredMessages(
        page: _nextPage,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        final known = _messages.map((m) => m.id).toSet();
        _messages.addAll(page.messages.where((m) => !known.contains(m.id)));
        _hasMore = page.hasNext;
        _nextPage = page.currentPage + 1;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      _showSnackBar('加载失败: $e', isError: true);
    }
  }

  Future<void> _unstar(Message message) async {
    if (_unstarring.contains(message.id)) return;
    setState(() => _unstarring.add(message.id));
    try {
      await _chatService.unstarMessage(message.id);
      if (!mounted) return;
      setState(() {
        _unstarring.remove(message.id);
        _messages.removeWhere((m) => m.id == message.id);
      });
      _showSnackBar('已取消收藏');
    } catch (e) {
      if (!mounted) return;
      setState(() => _unstarring.remove(message.id));
      _showSnackBar('取消收藏失败: $e', isError: true);
    }
  }

  Future<void> _open(Message message) async {
    if (_openingMessageId != null || message.chatRoomId.isEmpty) return;
    setState(() => _openingMessageId = message.id);
    try {
      final chat = _roomsById[message.chatRoomId] ??
          await _chatService.getChatRoom(message.chatRoomId);
      if (!mounted) return;
      await Navigator.of(context).pushNamed(
        '/chat/${chat.id}',
        arguments: ChatScreenArguments(chat: chat, focusMessage: message),
      );
    } catch (e) {
      _showSnackBar('打开聊天失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _openingMessageId = null);
    }
  }

  void _showSnackBar(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  String _roomName(Message message) {
    final room = _roomsById[message.chatRoomId];
    if (room == null || room.name.trim().isEmpty) return '聊天';
    return room.name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return PMErrorState(message: error, onRetry: _loadFirstPage);
    }
    if (_messages.isEmpty) {
      return const PMEmptyState(
        icon: Icons.star_border_rounded,
        title: '还没有收藏的消息',
        subtitle: '在聊天里长按消息，选择“收藏”即可保存到这里',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(PMSpacing.l),
        itemCount: _messages.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: PMSpacing.s),
        itemBuilder: (context, index) {
          if (index >= _messages.length) {
            return Center(
              child: TextButton(
                onPressed: _isLoadingMore ? null : _loadMore,
                child: Text(_isLoadingMore ? '加载中…' : '加载更多'),
              ),
            );
          }
          return _buildItem(_messages[index]);
        },
      ),
    );
  }

  Widget _buildItem(Message message) {
    final preview = message.isRemoved
        ? '该消息已删除'
        : message.resolvedFileLabel.trim().isEmpty
            ? '[消息]'
            : message.resolvedFileLabel.trim();
    final busy = _unstarring.contains(message.id);
    return PMCard(
      elevated: false,
      padding: EdgeInsets.zero,
      child: PMListRow(
        key: ValueKey('starred-message-${message.id}'),
        leading: _openingMessageId == message.id
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.star_rounded, color: AppColors.accentGold),
        title: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${message.senderName} · ${_roomName(message)} · '
          '${timeago.format(message.timestamp, locale: 'zh')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: '取消收藏',
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.star_rounded, color: AppColors.accentGold),
          onPressed: busy ? null : () => _unstar(message),
        ),
        onTap: () => _open(message),
      ),
    );
  }
}
