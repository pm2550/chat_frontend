part of '../chat_screen.dart';

extension _ChatScreenChromeParts on _ChatScreenState {
  Widget _buildDesktopChatScaffold() {
    return _buildDropPasteTarget(Scaffold(
      body: Row(
        children: [
          _buildDesktopRoomPanel(),
          Expanded(
            child: Column(
              children: [
                _buildDesktopConversationHeader(),
                _buildCallPanel(),
                _buildAnonymousBanner(),
                Expanded(
                  child: _buildMessageArea(),
                ),
                _buildDesktopInputBar(),
              ],
            ),
          ),
          _buildDesktopInfoPanel(),
        ],
      ),
    ));
  }

  Widget _buildDesktopRoomPanel() {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.borderLight)),
        boxShadow: [AppColors.appBarShadow],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const PMSymbolIcon(PMSymbol.back),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: PMChatLogo(size: 34, showWordmark: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  width: 78,
                  height: 78,
                  child: FittedBox(child: _buildChatAvatar()),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _chat.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _chatSubtitle(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              _buildDesktopActionTile(
                symbol: PMSymbol.call,
                title: '语音通话',
                onTap: () => _startCall(CallMediaKind.audio),
              ),
              _buildDesktopActionTile(
                symbol: PMSymbol.video,
                title: '视频通话',
                onTap: () => _startCall(CallMediaKind.video),
              ),
              _buildDesktopActionTile(
                symbol: PMSymbol.search,
                title: '搜索记录',
                onTap: _showSearchSheet,
              ),
              const Spacer(),
              _buildInfoTile(
                Icons.schedule,
                '最近消息',
                _messages.isEmpty
                    ? '暂无消息'
                    : timeago.format(_messages.last.timestamp, locale: 'zh'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopConversationHeader() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: _chat.type == ChatType.group ? '群信息 / 设置' : '聊天信息',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  onTap: _openRoomSettings,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _chat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _chatSubtitle(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildDesktopHeaderIcon(PMSymbol.call, '语音通话', () {
            _startCall(CallMediaKind.audio);
          }),
          const SizedBox(width: 8),
          _buildDesktopHeaderIcon(PMSymbol.video, '视频通话', () {
            _startCall(CallMediaKind.video);
          }),
          const SizedBox(width: 8),
          _buildDesktopHeaderIcon(
            PMSymbol.settings,
            _chat.type == ChatType.group ? '群设置' : '聊天信息',
            _openRoomSettings,
          ),
          const SizedBox(width: 8),
          _buildDesktopHeaderIcon(PMSymbol.more, '更多', _showChatOptions),
        ],
      ),
    );
  }

  Widget _buildDesktopHeaderIcon(
    PMSymbol symbol,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.pixelBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: PMSymbolIcon(
            symbol,
            color: AppColors.primary,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopActionTile({
    required PMSymbol symbol,
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cloud,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: [
              PMSymbolIcon(symbol, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const PMSymbolIcon(
                PMSymbol.chevronRight,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pixelMint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.secondaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _chatSubtitle() {
    if (_chat.type == ChatType.private && _chat.participants.isNotEmpty) {
      final participant = _chat.participants.first;
      if (participant.onlineStatus == OnlineStatus.online) {
        return '在线';
      }
      if (participant.lastSeen != null) {
        return '最后在线 ${timeago.format(participant.lastSeen!, locale: 'zh')}';
      }
      return '离线';
    }
    if (_chat.type == ChatType.group) {
      return '${_chat.participants.length}人';
    }
    return '会话';
  }

  Widget _buildChatAvatar() {
    final fallback = _chat.type == ChatType.group
        ? '群'
        : _chat.name.isNotEmpty
            ? _chat.name[0].toUpperCase()
            : '?';
    return CircleAvatar(
      radius: 20,
      backgroundColor:
          _chat.type == ChatType.group ? AppColors.primary : AppColors.accent,
      backgroundImage: _chat.avatarUrl != null
          ? NetworkImage(
              ApiConstants.resolveFileUrl(_chat.avatarUrl!),
            )
          : null,
      child: _chat.avatarUrl == null
          ? Text(
              fallback,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}
