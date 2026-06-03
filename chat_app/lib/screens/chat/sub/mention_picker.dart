part of '../chat_screen.dart';

extension _ChatScreenCommandParts on _ChatScreenState {
  void _insertSystemAgentMention() {
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
