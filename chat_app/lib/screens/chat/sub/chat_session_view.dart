part of '../chat_screen.dart';

extension _ChatSessionView1Parts on _ChatScreenState {
  Widget _buildMobileComposer() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildComposerToolbar(),
          const SizedBox(height: PMSpacing.s),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _buildComposerTextField(),
            const SizedBox(width: PMSpacing.s),
            _buildComposerSubmitButton(),
          ]),
        ],
      );

  Widget _buildComposerToolbar({bool desktop = false}) {
    return Row(children: [
      _buildInputIconButton(
          symbol: PMSymbol.emoji, onPressed: _showEmojiPanel, tooltip: '表情'),
      _buildInputIconButton(
          symbol: PMSymbol.sticker,
          onPressed: _showStickerPanel,
          tooltip: '贴纸'),
      _buildInputIconButton(
          symbol: PMSymbol.terminal,
          onPressed: _insertSystemAgentMention,
          tooltip: '插入 AI 助手'),
      _buildInputIconButton(
          symbol: PMSymbol.files,
          onPressed: _showAttachmentOptions,
          tooltip: '附件'),
      _buildInputIconButton(
          symbol: PMSymbol.more,
          onPressed: _showMoreComposerTools,
          tooltip: '更多工具'),
      if (_chat.anonymousEnabled) _buildAnonymousToggle(compact: true),
      if (desktop) ...[
        const Spacer(),
        const Flexible(
          child: Text('Enter 发送 · Shift + Enter 换行',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        ),
      ],
    ]);
  }

  Widget _buildAnonymousToggle({bool compact = false}) {
    return AnonymousToggleButton(
      chatRoomId: int.tryParse(_chat.id) ?? 0,
      anonymousEnabled: _chat.anonymousEnabled,
      perMessageMode: _anonymousPerMessageMode,
      nextMessageAnonymous: _anonymousNextMessage,
      onPerMessageModeChanged: _setAnonymousMode,
      currentIdentity: _anonymousIdentity,
      compact: compact,
      onAnonymousChanged: (identity) {
        _applyAnonymousIdentity(identity);
      },
    );
  }

  Widget _buildComposerTextField() {
    return Expanded(
      child: Container(
        key: const ValueKey('chat-composer-text-field-shell'),
        decoration: BoxDecoration(
          color: AppColors.cloud,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: _buildMessageTextField(
          hintText: '输入消息，/ 调用 AI',
        ),
      ),
    );
  }

  Widget _buildComposerSubmitButton() {
    return _isTyping || _hasPendingAttachments
        ? _buildInputIconButton(
            symbol: PMSymbol.send,
            onPressed: _sendMessage,
            tooltip: '发送',
            filled: true,
          )
        : _buildInputIconButton(
            symbol: _isRecordingVoice ? PMSymbol.send : PMSymbol.mic,
            onPressed: _toggleVoiceRecording,
            tooltip: _isRecordingVoice ? '停止并发送语音' : '录音说话',
            filled: _isRecordingVoice,
          );
  }
}
