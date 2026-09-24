part of '../chat_screen.dart';

/// 私聊端到端加密在聊天页上的部分：头部的锁、提示条、解锁、发送前加密。
extension _ChatScreenE2eeParts on _ChatScreenState {
  Future<void> _refreshE2eeRoomState({bool refresh = false}) async {
    if (_chat.type != ChatType.private || _chat.id.isEmpty) return;
    final state = await _e2ee.roomState(_chat, refresh: refresh);
    if (!mounted) return;
    _setViewState(() => _e2eeRoom = state);
  }

  /// 密钥解开了、对方公钥取到了：把列表里的加密消息重新解一遍。
  void _handleE2eeChanged() {
    if (!mounted) return;
    if (_messages.any(_hasEncryptedContent)) {
      _setViewState(() {
        _messages = _messages.map(_revealE2ee).toList();
        final replying = _replyingToMessage;
        if (replying != null) _replyingToMessage = _revealE2ee(replying);
      });
      _saveMessageCache();
    }
    if (_e2eeRoom.mode == E2eeRoomMode.needsUnlock ||
        _e2eeRoom.mode == E2eeRoomMode.unknown ||
        _e2ee.cachedRoomState(_chat.id).checkedAt == null) {
      unawaited(_refreshE2eeRoomState());
    }
  }

  static bool _hasEncryptedContent(Message message) =>
      message.isEncrypted || (message.replyToMessage?.isEncrypted ?? false);

  Message _revealE2ee(Message message) {
    final revealed = _e2ee.reveal(message);
    final reply = revealed.replyToMessage;
    if (reply == null || !reply.isEncrypted) return revealed;
    return revealed.copyWith(replyToMessage: _e2ee.reveal(reply));
  }

  Future<void> _unlockE2ee() async {
    final unlocked = await runE2eeUnlockFlow(context, _e2ee);
    if (unlocked) await _refreshE2eeRoomState(refresh: true);
  }

  Widget _buildE2eeNotice() {
    return E2eeRoomNoticeBar(state: _e2eeRoom, onUnlock: _unlockE2ee);
  }

  /// 发文本前：该加密就返回密文信封，可以明文发就返回 null；
  /// 该加密却加密不了时抛错（消息标记为发送失败），绝不悄悄发明文。
  Future<String?> _sealOutgoingText(String content,
      {required bool anonymous}) async {
    if (_chat.type != ChatType.private) return null;
    final sealed = await _e2ee.sealText(_chat, content);
    if (sealed != null && anonymous) {
      throw const E2eeSendBlockedException('端到端加密的私聊不能匿名发送');
    }
    if (_e2eeRoom.mode != _e2ee.cachedRoomState(_chat.id).mode) {
      _setViewState(() => _e2eeRoom = _e2ee.cachedRoomState(_chat.id));
    }
    return sealed;
  }

  bool get _hasEncryptedHistory =>
      _e2eeRoom.encrypts || _messages.any((message) => message.isEncrypted);

  /// 服务器只有密文，搜索接口不含加密消息；把本机已加载并解开的加密消息按关键词补进结果。
  List<Message> _withLocalEncryptedMatches(
    List<Message> serverResults,
    String keyword,
  ) {
    final needle = keyword.toLowerCase();
    final seen = serverResults.map((message) => message.id).toSet();
    final local = _messages.where((message) =>
        message.isEncrypted &&
        !message.isRemoved &&
        !seen.contains(message.id) &&
        _e2ee.isReadable(message) &&
        message.resolvedFileLabel.toLowerCase().contains(needle));
    if (local.isEmpty) return serverResults;
    return [...serverResults, ...local]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// 加密消息在这台设备上解不开时，复制/引用/转发/编辑都没有意义。
  bool _canUseMessageContent(Message message) => _e2ee.isReadable(message);
}
