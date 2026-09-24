part of '../chat_screen.dart';

/// 会话状态的实时同步：对方在线状态、已读回执、被移出会话、自己的输入状态。
extension _ChatScreenRealtimeSyncParts on _ChatScreenState {
  void _applyRealtimePresence(Map<String, dynamic> event) {
    final userId = event['userId']?.toString();
    final value = event['onlineStatus'] ?? event['online_status'];
    if (userId == null || value == null) return;
    final index = _chat.participants.indexWhere((user) => user.id == userId);
    if (index == -1) return;
    final status = OnlineStatus.values.firstWhere(
      (item) => item.name.toUpperCase() == value.toString().toUpperCase(),
      orElse: () => OnlineStatus.offline,
    );
    final current = _chat.participants[index];
    if (current.onlineStatus == status) return;
    final participants = List<User>.from(_chat.participants);
    participants[index] = current.copyWith(
      onlineStatus: status,
      lastSeen: status == OnlineStatus.offline ? DateTime.now() : null,
    );
    _setViewState(() => _chat = _chat.copyWith(participants: participants));
  }

  /// 别人读了消息：和服务器的计数规则保持一致——按条读（带 messageId）给那一条
  /// 加一；整房间已读（带 lastReadMessageId）给截至该条、还没标已读的消息加一。
  /// 自己在其他设备上读不影响这里的已读数（列表页负责清未读）。
  void _applyRealtimeReadReceipt(Map<String, dynamic> event) {
    final readerId = event['userId']?.toString();
    if (readerId == null || readerId == _authService.currentUser?.id) return;
    final messageId = event['messageId']?.toString();
    final lastReadId =
        int.tryParse(event['lastReadMessageId']?.toString() ?? '');
    if (messageId == null && lastReadId == null) return;
    var changed = false;
    final next = _messages.map((message) {
      if (message.senderId == readerId) return message;
      if (messageId != null) {
        if (message.id != messageId) return message;
      } else {
        final id = int.tryParse(message.id);
        if (id == null ||
            id > lastReadId! ||
            message.status == MessageStatus.read) {
          return message;
        }
      }
      changed = true;
      return message.copyWith(
        status: MessageStatus.read,
        readCount: message.readCount + 1,
      );
    }).toList();
    if (!changed) return;
    _setViewState(() => _messages = next);
    _saveMessageCache();
  }

  /// 被踢、群被解散、或在另一台设备上退出了：提示一下并离开聊天页。
  void _handleRemovedFromRoom(String? reason) {
    if (_removedFromRoom) return;
    final route = ModalRoute.of(context);
    final isCurrent = route?.isCurrent ?? true;
    // 在这台设备的设置页里点了退出：设置页会自己关掉聊天页。
    if (reason == 'left' && !isCurrent) return;
    _removedFromRoom = true;
    _messageReconciliationTimer?.cancel();
    final notice = switch (reason) {
      'kicked' => '你已被移出该群聊',
      'deleted' => '该群聊已被解散',
      _ => '你已退出该群聊',
    };
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(notice)));
    final navigator = Navigator.of(context);
    if (route != null && !isCurrent) {
      navigator.removeRoute(route);
    } else if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/home');
    }
  }

  void _sendTypingState(bool isTyping) {
    final roomId = int.tryParse(_chat.id);
    if (roomId == null) return;
    _webSocketService.sendTyping(roomId, isTyping);
  }

  void _handleComposerTextForTyping() {
    if (!_didInitialize || _removedFromRoom) return;
    // 匿名发言时不发输入状态：服务器广播的是真实昵称，会暴露匿名身份。
    if (_activeSendIdentity() != null) {
      _typingSender.stop();
      return;
    }
    _typingSender.onTextChanged(_messageController.text);
  }

  void _handleComposerFocusForTyping() {
    if (!_focusNode.hasFocus) _typingSender.stop();
  }
}
