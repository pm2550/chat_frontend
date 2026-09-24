part of '../chat_screen.dart';

extension _ChatScreenCommandParts on _ChatScreenState {
  void _insertSystemAgentMention() {
    if (_e2eeRoom.encrypts) {
      // 加密消息服务器看不到，@ 了 AI 助手它也收不到。
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端到端加密的私聊里，AI 助手读不到消息')),
      );
      return;
    }
    final bot = _systemAgentBot();
    if (bot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本房间未启用 AI 助手，请先在房间设置里添加')),
      );
      return;
    }
    _insertMentionForUser(_mentionUserForBot(bot));
    _focusNode.requestFocus();
  }

  BotConfig? _systemAgentBot() {
    for (final bot in _roomBots) {
      if (bot.enabledInRoom && bot.createdById == null) {
        return bot;
      }
    }
    return null;
  }
}
