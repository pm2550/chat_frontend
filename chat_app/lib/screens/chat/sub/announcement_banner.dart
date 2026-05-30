part of '../chat_screen.dart';

extension _ChatScreenAnnouncementParts on _ChatScreenState {
  Future<void> _prepareAnnouncementBanner() async {
    final announcement = _chat.announcement?.trim();
    final updatedAt = _chat.announcementUpdatedAt;
    if (announcement == null || announcement.isEmpty || updatedAt == null) {
      _setViewState(() {
        _showAnnouncementBanner = false;
        _announcementSeenKey = null;
      });
      return;
    }
    if (DateTime.now().difference(updatedAt).inDays > 7) {
      _setViewState(() {
        _showAnnouncementBanner = false;
        _announcementSeenKey = null;
      });
      return;
    }

    final key = 'announcement_seen:${_chat.id}:${updatedAt.toIso8601String()}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(key) ?? false;
      if (!mounted) return;
      _setViewState(() {
        _announcementSeenKey = key;
        _showAnnouncementBanner = !seen;
      });
    } catch (_) {
      if (!mounted) return;
      _setViewState(() {
        _announcementSeenKey = key;
        _showAnnouncementBanner = true;
      });
    }
  }

  Future<void> _dismissAnnouncementBanner() async {
    final key = _announcementSeenKey;
    _setViewState(() => _showAnnouncementBanner = false);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } catch (_) {
      // Banner dismissal is still applied in memory when persistence is absent.
    }
  }

  Widget _buildAnnouncementBanner() {
    final announcement = _chat.announcement?.trim();
    if (!_showAnnouncementBanner ||
        announcement == null ||
        announcement.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(PMSpacing.l, PMSpacing.m, PMSpacing.l, 0),
      child: PMCard(
        elevated: false,
        background: AppColors.warning.withValues(alpha: 0.10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.campaign_rounded, color: AppColors.warning),
            const SizedBox(width: PMSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '群公告',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: PMSpacing.xs),
                  Text(
                    announcement,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '关闭群公告',
              icon: const Icon(Icons.close_rounded),
              onPressed: _dismissAnnouncementBanner,
            ),
          ],
        ),
      ),
    );
  }
}

extension _ChatScreenRouteResolutionParts on _ChatScreenState {
  Future<void> _loadChatFromRoute(String chatRoomId) async {
    try {
      final chat = await _chatService.getChatRoom(chatRoomId);
      if (!mounted) return;
      _setViewState(() {
        _chat = chat;
        _isResolvingRouteChat = false;
        _routeChatError = null;
      });
      _startChatSession();
    } catch (e) {
      if (!mounted) return;
      _setViewState(() {
        _isResolvingRouteChat = false;
        _isLoadingMessages = false;
        _routeChatError = e.toString();
      });
    }
  }

  void _retryOpenRouteChat() {
    final chatRoomId = _routeChatIdToResolve ?? _chatRoomIdFromRoute(null);
    if (chatRoomId == null || chatRoomId.trim().isEmpty) {
      Navigator.of(context).pushReplacementNamed('/home');
      return;
    }
    _setViewState(() {
      _routeChatIdToResolve = chatRoomId;
      _routeChatError = null;
      _isResolvingRouteChat = true;
    });
    unawaited(_loadChatFromRoute(chatRoomId));
  }

  Widget _buildRouteResolutionScaffold() {
    final hasError = _routeChatError != null;
    final canRetry = (_routeChatIdToResolve?.isNotEmpty ?? false);
    return Scaffold(
      body: PMChatPattern(
        dense: true,
        child: Center(
          child: Container(
            width: 420,
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: const [AppColors.cardShadow],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasError ? Icons.link_off : Icons.chat_bubble_outline,
                  size: 54,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  hasError ? '无法打开聊天' : '正在打开聊天',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasError ? _routeChatError! : '正在根据当前链接加载会话信息...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                if (hasError)
                  FilledButton.icon(
                    onPressed: _retryOpenRouteChat,
                    icon: Icon(canRetry ? Icons.refresh : Icons.home_outlined),
                    label: Text(canRetry ? '重试' : '返回消息工作台'),
                  )
                else
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
