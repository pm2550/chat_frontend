part of '../chat_screen.dart';

extension _ChatScreenActionSheetParts on _ChatScreenState {
  Future<void> _updateRoomPreference({bool? muted, bool? pinned}) async {
    final nextMuted = muted ?? _chat.isMuted;
    final nextPinned = pinned ?? _chat.isPinned;
    _setViewState(() {
      _chat = _chat.copyWith(isMuted: nextMuted, isPinned: nextPinned);
    });
    try {
      await _chatService.updateNotificationSettings(
        _chat.id,
        muted: muted,
        pinned: pinned,
      );
    } catch (e) {
      if (!mounted) return;
      _setViewState(() {
        _chat = _chat.copyWith(
          isMuted: muted == null ? _chat.isMuted : !nextMuted,
          isPinned: pinned == null ? _chat.isPinned : !nextPinned,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('偏好更新失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// “删除聊天”：先清空自己这边的聊天记录，再把会话移出自己的消息列表，
  /// 然后离开聊天页。两步都只影响当前用户；对方发来新消息时会话会重新出现。
  Future<void> _deleteChatForMe() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _chatService.clearChatHistory(_chat.id);
      if (!mounted) return;
      _setViewState(() {
        _messages = [];
      });
      _saveMessageCache();
      await _chatService.hideChatRoom(_chat.id);
      if (!mounted) return;
      ChatScreen._messageCache.remove(_chat.id);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('已删除聊天「${_displayChatTitle()}」')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('删除失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _recallMessage(Message message) async {
    try {
      final updated = await _chatService.recallMessage(message.id);
      _upsertMessage(updated.chatRoomId.isEmpty
          ? updated.copyWith(chatRoomId: _chat.id)
          : updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('撤回失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteMessage(Message message) async {
    try {
      final updated = await _chatService.deleteMessage(message.id);
      _upsertMessage(updated.chatRoomId.isEmpty
          ? updated.copyWith(chatRoomId: _chat.id)
          : updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _editMessage(Message message) async {
    final controller = TextEditingController(text: message.content);
    final nextContent = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          decoration: const InputDecoration(hintText: '输入新的消息内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nextContent == null || nextContent.isEmpty) return;
    try {
      final updated = await _chatService.editMessage(message.id, nextContent);
      _upsertMessage(updated.chatRoomId.isEmpty
          ? updated.copyWith(chatRoomId: _chat.id)
          : updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('编辑失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _forwardMessage(Message message) async {
    final target = await _selectForwardTarget();
    if (target == null) return;
    try {
      final sent = await _chatService.forwardMessage(message.id, target.id);
      if (!mounted) return;
      if (target.id == _chat.id) {
        _upsertMessage(sent);
        _scrollToBottom();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已转发到 ${target.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('转发失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _pinMessage(Message message) async {
    try {
      await _pinnedMessages.pin(message.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('消息已置顶')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('置顶失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _unpinMessage(Message message) async {
    try {
      await _pinnedMessages.unpin(message.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消置顶')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('取消置顶失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// 群聊里只有群主/管理员能管理置顶（与后端 RoomPinController 一致）。
  /// [members] 来自成员列表接口；没有成员数据时只能按建群人判断。
  void _syncPinPermissions([List<ChatRoomMember>? members]) {
    final currentUserId = _authService.currentUser?.id;
    var isAdmin = currentUserId != null && _chat.createdBy == currentUserId;
    if (!isAdmin && currentUserId != null && members != null) {
      isAdmin = members.any((member) {
        if (member.userId != currentUserId) return false;
        final role = member.role.toUpperCase();
        return member.isAdmin || role == 'ADMIN' || role == 'OWNER';
      });
    }
    _pinnedMessages.updatePermissions(
      // 后端只对私聊放开成员置顶；群聊、频道都要管理员。
      isGroup: _chat.type != ChatType.private,
      viewerIsAdmin: isAdmin,
    );
  }

  Widget _buildPinnedMessagesBar() {
    return PinnedMessagesBar(
      controller: _pinnedMessages,
      onOpenList: _openPinnedMessagesList,
    );
  }

  void _openPinnedMessagesList() {
    unawaited(showPinnedMessagesSheet(
      context,
      controller: _pinnedMessages,
      onJumpTo: _openSearchResult,
      onUnpin: _unpinMessage,
      formatTime: _formatMessageTime,
    ));
  }

  Future<void> _toggleStarMessage(Message message) async {
    final starring = !message.starredByMe;
    try {
      await (starring
          ? _chatService.starMessage(message.id)
          : _chatService.unstarMessage(message.id));
      if (!mounted) return;
      // 只更新收藏状态，保留本地已有的消息内容（响应里的消息不带聚合数据）。
      final current = _messages.firstWhere(
        (item) => item.id == message.id,
        orElse: () => message,
      );
      _upsertMessage(current.copyWith(starredByMe: starring));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(starring ? '已收藏' : '已取消收藏')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${starring ? '收藏' : '取消收藏'}失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showMessageActions(Message message, bool isMe) {
    if (message.id.startsWith('local-') || message.isRemoved) {
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final emoji in const [
                          '👍',
                          '❤️',
                          '😂',
                          '🎉',
                          '😮',
                          '😢'
                        ])
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () {
                              Navigator.pop(context);
                              unawaited(_toggleReaction(
                                message,
                                emoji,
                                message.hasReactionFrom(
                                  emoji,
                                  _authService.currentUser?.id,
                                ),
                              ));
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isMe)
                    _buildChatOption(
                      icon: Icons.undo,
                      title: '撤回消息',
                      onTap: () {
                        Navigator.pop(context);
                        _recallMessage(message);
                      },
                    ),
                  if (isMe && message.type == MessageType.text)
                    _buildChatOption(
                      icon: Icons.edit,
                      title: '编辑',
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_editMessage(message));
                      },
                    ),
                  _buildChatOption(
                    icon: Icons.copy,
                    title: '复制',
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制')),
                      );
                    },
                  ),
                  _buildChatOption(
                    icon: Icons.reply,
                    title: '引用',
                    onTap: () {
                      Navigator.pop(context);
                      _quoteMessage(message);
                    },
                  ),
                  _buildChatOption(
                    icon: Icons.delete_outline,
                    title: '删除消息',
                    color: AppColors.error,
                    onTap: () {
                      Navigator.pop(context);
                      _deleteMessage(message);
                    },
                  ),
                  _buildChatOption(
                    icon: Icons.forward,
                    title: '转发',
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_forwardMessage(message));
                    },
                  ),
                  if (_pinnedMessages.canManage)
                    _pinnedMessages.isPinned(message.id)
                        ? _buildChatOption(
                            icon: Icons.push_pin_outlined,
                            title: '取消置顶',
                            onTap: () {
                              Navigator.pop(context);
                              unawaited(_unpinMessage(message));
                            },
                          )
                        : _buildChatOption(
                            icon: Icons.push_pin,
                            title: '置顶消息',
                            onTap: () {
                              Navigator.pop(context);
                              unawaited(_pinMessage(message));
                            },
                          ),
                  _buildChatOption(
                    icon: message.starredByMe ? Icons.star : Icons.star_border,
                    title: message.starredByMe ? '取消收藏' : '收藏',
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_toggleStarMessage(message));
                    },
                  ),
                  _buildChatOption(
                    icon: Icons.done_all,
                    title: '查看已读',
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_showReadReceipts(message));
                    },
                  ),
                  if (message.fileUrl?.isNotEmpty == true) ...[
                    _buildChatOption(
                      icon: Icons.download,
                      title: message.isImageMessage ? '保存图片' : '下载附件',
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_downloadAttachment(message));
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.forward,
                      title: '下载后转发附件',
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_forwardAttachment(message));
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleReaction(
    Message message,
    String emoji,
    bool selected,
  ) async {
    try {
      final reactions = selected
          ? await _chatService.removeReaction(message.id, emoji)
          : await _chatService.addReaction(message.id, emoji);
      _upsertMessage(message.copyWith(reactions: reactions));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('反应更新失败: $e')),
      );
    }
  }

  Future<void> _showReadReceipts(Message message) async {
    final memberCount = _chat.effectiveMemberCount;
    if (_chat.type == ChatType.group && memberCount > 20) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: PMCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '已读概览',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '这个群有 $memberCount 人。为避免大群刷屏，只显示已读数量：${message.readCount}。',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    try {
      final receipts = await _chatService.getReadBy(message.id);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: PMCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '已读详情',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                if (receipts.isEmpty)
                  const Text('暂无已读记录')
                else
                  for (final receipt in receipts)
                    PMListRow(
                      dense: true,
                      title: Text(receipt.displayName),
                      subtitle: Text(receipt.readAt?.toString() ?? ''),
                    ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已读详情加载失败: $e')),
      );
    }
  }

  void _showSearchSheet() {
    _searchController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        var isSearching = false;
        var searched = false;
        String? error;
        List<Message> results = const [];

        Future<void> runSearch(StateSetter setSheetState) async {
          final keyword = _searchController.text.trim();
          if (keyword.isEmpty) {
            return;
          }
          setSheetState(() {
            isSearching = true;
            searched = true;
            error = null;
          });
          try {
            final page = await _chatService.searchMessages(_chat.id, keyword);
            setSheetState(() {
              results = page.messages;
              isSearching = false;
            });
          } catch (e) {
            setSheetState(() {
              error = e.toString();
              isSearching = false;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.82,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜索聊天记录',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () => runSearch(setSheetState),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: (_) => runSearch(setSheetState),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isSearching)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (error != null)
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              '搜索失败: $error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (searched && results.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            '没有找到相关消息',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemBuilder: (context, index) {
                            final message = results[index];
                            return PMListRow(
                              dense: true,
                              leading: const PMSymbolIcon(
                                PMSymbol.search,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              title: _highlightKeyword(
                                message.resolvedFileLabel,
                                _searchController.text.trim(),
                              ),
                              subtitle: Text(
                                '${message.senderName} · ${_formatMessageTime(message.timestamp)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _openSearchResult(message);
                              },
                            );
                          },
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemCount: results.length,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _highlightKeyword(String text, String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final lowerText = text.toLowerCase();
    final lowerKeyword = trimmed.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      final index = lowerText.indexOf(lowerKeyword, cursor);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (index > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + trimmed.length),
        style: const TextStyle(
          color: AppColors.error,
          fontWeight: FontWeight.w900,
        ),
      ));
      cursor = index + trimmed.length;
    }
    return Text.rich(
      TextSpan(
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  void _openSearchResult(Message message) {
    _upsertMessage(message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _messageKeyFor(message.id);
      final targetContext = key.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: PMMotion.medium,
          curve: PMMotion.curveStandard,
          alignment: 0.35,
        );
      } else {
        final index = _messages.indexWhere((item) => item.id == message.id);
        if (index != -1 && _scrollController.hasClients) {
          final estimate = (index * 96.0).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          );
          _scrollController.animateTo(
            estimate,
            duration: PMMotion.medium,
            curve: PMMotion.curveStandard,
          );
        }
      }
      _messageHighlightTimer?.cancel();
      _setViewState(() => _highlightedMessageId = message.id);
      _messageHighlightTimer = Timer(const Duration(seconds: 1), () {
        if (mounted && _highlightedMessageId == message.id) {
          _setViewState(() => _highlightedMessageId = null);
        }
      });
    });
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildChatOption(
                      icon: Icons.info_outline,
                      title: _chat.type == ChatType.group ? '群聊设置' : '聊天信息',
                      onTap: () async {
                        Navigator.pop(context);
                        final roomId = int.tryParse(_chat.id);
                        if (roomId == null) return;
                        final left = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatRoomSettingsScreen(
                              chatRoomId: roomId,
                              chatRoomName: _chat.name,
                              isGroup: _chat.type == ChatType.group,
                              currentUserId: _authService.currentUser?.id,
                              chatService: _chatService,
                              initialAnonymousEnabled: _chat.anonymousEnabled,
                            ),
                          ),
                        );
                        if (left == true && context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.search,
                      title: '搜索聊天记录',
                      onTap: () {
                        Navigator.pop(context);
                        _showSearchSheet();
                      },
                    ),
                    if (_pinnedMessages.pins.isNotEmpty)
                      _buildChatOption(
                        icon: Icons.push_pin_outlined,
                        title: '置顶消息（${_pinnedMessages.pins.length}）',
                        onTap: () {
                          Navigator.pop(context);
                          _openPinnedMessagesList();
                        },
                      ),
                    _buildChatOption(
                      icon: Icons.volume_off,
                      title: _chat.isMuted ? '取消静音' : '静音通知',
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(
                          _updateRoomPreference(muted: !_chat.isMuted),
                        );
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.push_pin,
                      title: _chat.isPinned ? '取消置顶' : '置顶聊天',
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(
                          _updateRoomPreference(pinned: !_chat.isPinned),
                        );
                      },
                    ),
                    _buildChatOption(
                      icon: Icons.delete_outline,
                      title: '删除聊天',
                      color: AppColors.error,
                      onTap: () {
                        Navigator.pop(context);
                        _showDeleteDialog();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatOption({
    required IconData icon,
    required String title,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        color: color ?? AppColors.textPrimary,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除聊天'),
        content: const Text(
          '将清空你这边的聊天记录，并把这个聊天从你的消息列表移除。'
          '其他成员的记录不受影响；对方发来新消息时，聊天会重新出现在列表中。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_deleteChatForMe());
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
