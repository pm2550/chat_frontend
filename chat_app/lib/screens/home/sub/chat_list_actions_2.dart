part of '../chat_list_page.dart';

extension _ChatListActions2Parts on _ChatListPageState {
  Future<void> _toggleChatPinned(Chat chat) async {
    try {
      await _chatService.updateNotificationSettings(
        chat.id,
        pinned: !chat.isPinned,
      );
      if (!mounted) return;
      _directory.conversations.updateRoom(
        chat.id,
        (room) => room.copyWith(isPinned: !chat.isPinned),
      );
      _showSnackBar(chat.isPinned ? '已取消置顶' : '已置顶');
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _runChatStateAction(
    Chat chat,
    Future<void> Function() action, {
    required String successMessage,
    required bool removeFromList,
    Future<void> Function()? undo,
  }) async {
    try {
      await action();
      if (!mounted) return;
      if (removeFromList) {
        _directory.conversations.removeRoom(chat.id);
      } else {
        unawaited(_loadChats(showLoading: false));
      }
      if (undo == null) {
        _showSnackBar(successMessage);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => unawaited(_undoChatStateAction(chat, undo)),
            ),
          ),
        );
      }
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _undoChatStateAction(
    Chat chat,
    Future<void> Function() undo,
  ) async {
    try {
      await undo();
      await _loadChats(showLoading: false, forceRefresh: true);
      if (!mounted) return;
      if (!_directory.conversations.contains(chat.id)) {
        // 刷新失败时至少把本地这一项放回去。
        _directory.conversations.upsert(chat);
      }
    } catch (e) {
      _showSnackBar('撤销失败: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
