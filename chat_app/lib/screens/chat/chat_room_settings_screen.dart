import 'package:flutter/material.dart';

import '../../constants/api_constants.dart';
import '../../models/chat_room_member.dart';
import '../../models/user.dart';
import '../../services/anonymous_service.dart';
import '../../services/auth_service.dart';
import '../../services/bot_service.dart';
import '../../services/chat_data_service.dart';
import '../../services/contact_data_service.dart';
import 'chat_file_center_screen.dart';

class ChatRoomSettingsScreen extends StatefulWidget {
  final int chatRoomId;
  final String chatRoomName;
  final bool isAdmin;
  final bool isGroup;
  final String? currentUserId;
  final ChatDataService? chatService;
  final ContactDataService? contactService;
  final BotService? botService;
  final bool initialAnonymousEnabled;
  final bool enableBotLoading;

  const ChatRoomSettingsScreen({
    super.key,
    required this.chatRoomId,
    required this.chatRoomName,
    this.isAdmin = false,
    this.isGroup = false,
    this.currentUserId,
    this.chatService,
    this.contactService,
    this.botService,
    this.initialAnonymousEnabled = false,
    this.enableBotLoading = true,
  });

  @override
  State<ChatRoomSettingsScreen> createState() => _ChatRoomSettingsScreenState();
}

class _ChatRoomSettingsScreenState extends State<ChatRoomSettingsScreen> {
  final AnonymousService _anonymousService = AnonymousService();

  late final ChatDataService _chatService;
  late final ContactDataService _contactService;
  late final BotService _botService;

  bool _anonymousEnabled = false;
  bool _isLoadingMembers = true;
  bool _isLoadingInvitees = false;
  bool _currentUserIsAdmin = false;
  bool _isMuted = false;
  bool _isPinned = false;
  String? _memberError;
  List<ChatRoomMember> _members = [];
  List<BotConfig> _bots = [];

  String? get _currentUserId =>
      widget.currentUserId ?? AuthService().currentUser?.id;

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatDataService();
    _contactService = widget.contactService ?? ContactDataService();
    _botService = widget.botService ?? BotService();
    _anonymousEnabled = widget.initialAnonymousEnabled;
    _currentUserIsAdmin = widget.isAdmin;
    _loadMembers();
    _loadRoomPreferences();
    if (widget.isGroup && widget.enableBotLoading) {
      _loadBots();
    }
  }

  Future<void> _loadRoomPreferences() async {
    try {
      final settings = await _chatService
          .getNotificationSettings(widget.chatRoomId.toString());
      if (!mounted) return;
      setState(() {
        _isMuted = settings['muted'] == true ||
            settings['muted']?.toString().toLowerCase() == 'true';
        _isPinned = settings['pinned'] == true ||
            settings['pinned']?.toString().toLowerCase() == 'true';
      });
    } catch (_) {
      // Preferences are still editable from their default state.
    }
  }

  Future<void> _updateRoomPreferences({bool? muted, bool? pinned}) async {
    final previousMuted = _isMuted;
    final previousPinned = _isPinned;
    setState(() {
      if (muted != null) _isMuted = muted;
      if (pinned != null) _isPinned = pinned;
    });

    try {
      final settings = await _chatService.updateNotificationSettings(
        widget.chatRoomId.toString(),
        muted: muted,
        pinned: pinned,
      );
      if (!mounted) return;
      setState(() {
        _isMuted = settings['muted'] == true ||
            settings['muted']?.toString().toLowerCase() == 'true';
        _isPinned = settings['pinned'] == true ||
            settings['pinned']?.toString().toLowerCase() == 'true';
      });
      _showSnackBar('设置已更新');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isMuted = previousMuted;
        _isPinned = previousPinned;
      });
      _showSnackBar('设置更新失败: $error', isError: true);
    }
  }

  Future<void> _clearChatHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text('只会清空你自己的可见历史，不会删除其他成员的消息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _chatService.clearChatHistory(widget.chatRoomId.toString());
      if (!mounted) return;
      _showSnackBar('聊天记录已清空');
    } catch (error) {
      _showSnackBar('清空失败: $error', isError: true);
    }
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoadingMembers = true;
      _memberError = null;
    });

    try {
      final members =
          await _chatService.getChatRoomMembers(widget.chatRoomId.toString());
      final currentUserId = _currentUserId;
      setState(() {
        _members = members;
        _currentUserIsAdmin = widget.isAdmin ||
            members.any(
                (member) => member.userId == currentUserId && member.isAdmin);
        _isLoadingMembers = false;
      });
    } catch (error) {
      setState(() {
        _memberError = error.toString();
        _isLoadingMembers = false;
      });
    }
  }

  Future<void> _loadBots() async {
    try {
      final bots = await _botService.getBotsInRoom(widget.chatRoomId);
      if (mounted) {
        setState(() => _bots = bots);
      }
    } catch (_) {
      // Bot settings are optional in this phase.
    }
  }

  Future<void> _showAddBotSheet() async {
    try {
      final myBots = await _botService.getMyBots();
      final roomBotIds = _bots.map((bot) => bot.id).whereType<int>().toSet();
      final candidates = myBots
          .where((bot) => bot.id != null && !roomBotIds.contains(bot.id))
          .toList();
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.smart_toy),
                title: Text('添加机器人'),
              ),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('暂无可添加机器人'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final bot = candidates[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.smart_toy),
                        ),
                        title: Text(bot.botName),
                        subtitle: Text(bot.llmProvider),
                        trailing: const Icon(Icons.add),
                        onTap: () {
                          Navigator.pop(context);
                          _addBotToRoom(bot);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (error) {
      _showSnackBar('加载机器人失败: $error', isError: true);
    }
  }

  Future<void> _addBotToRoom(BotConfig bot) async {
    final botId = bot.id;
    if (botId == null) return;
    try {
      await _botService.addBotToRoom(
        widget.chatRoomId,
        botId,
        triggerMode: 'MENTION',
      );
      await _loadBots();
      _showSnackBar('已添加 ${bot.botName}');
    } catch (error) {
      _showSnackBar('添加机器人失败: $error', isError: true);
    }
  }

  Future<void> _removeBotFromRoom(BotConfig bot) async {
    final botId = bot.id;
    if (botId == null) return;
    try {
      await _botService.removeBotFromRoom(widget.chatRoomId, botId);
      await _loadBots();
      _showSnackBar('已移除 ${bot.botName}');
    } catch (error) {
      _showSnackBar('移除机器人失败: $error', isError: true);
    }
  }

  Future<void> _showInviteSheet() async {
    if (_isLoadingInvitees) return;
    setState(() => _isLoadingInvitees = true);

    List<User> candidates = [];
    Object? error;
    try {
      final friends = await _contactService.getFriends();
      final memberIds = _members.map((member) => member.userId).toSet();
      candidates =
          friends.where((friend) => !memberIds.contains(friend.id)).toList();
    } catch (e) {
      error = e;
    }

    if (!mounted) return;
    setState(() => _isLoadingInvitees = false);

    if (error != null) {
      _showSnackBar('加载好友失败: $error', isError: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.person_add_alt_1),
                title: Text('邀请好友'),
              ),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('没有可邀请的好友'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final user = candidates[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user.avatarUrl != null
                              ? NetworkImage(
                                  ApiConstants.resolveFileUrl(user.avatarUrl!),
                                )
                              : null,
                          child: user.avatarUrl == null
                              ? Text(_avatarText(user.displayName))
                              : null,
                        ),
                        title: Text(user.displayName),
                        subtitle: Text('@${user.username}'),
                        trailing: const Icon(Icons.add),
                        onTap: () {
                          Navigator.pop(context);
                          _inviteUser(user);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _inviteUser(User user) async {
    try {
      final members = await _chatService.addChatRoomMember(
        widget.chatRoomId.toString(),
        user.id,
      );
      setState(() => _members = members);
      _showSnackBar('已邀请 ${user.displayName}');
    } catch (error) {
      _showSnackBar('邀请失败: $error', isError: true);
    }
  }

  Future<void> _handleMemberAction(
    String action,
    ChatRoomMember member,
  ) async {
    try {
      switch (action) {
        case 'admin':
          await _chatService.toggleChatRoomAdmin(
            widget.chatRoomId.toString(),
            member.userId,
          );
          break;
        case 'mute':
          await _chatService.toggleChatRoomMute(
            widget.chatRoomId.toString(),
            member.userId,
          );
          break;
        case 'kick':
          await _chatService.kickChatRoomMember(
            widget.chatRoomId.toString(),
            member.userId,
          );
          break;
      }
      await _loadMembers();
    } catch (error) {
      _showSnackBar('操作失败: $error', isError: true);
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('退出后将不再接收这个群聊的消息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _chatService.leaveChatRoom(widget.chatRoomId.toString());
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      _showSnackBar('退出失败: $error', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _currentUserId;

    return Scaffold(
      appBar: AppBar(title: Text(widget.chatRoomName)),
      body: RefreshIndicator(
        onRefresh: _loadMembers,
        child: ListView(
          children: [
            _buildSectionHeader('群组信息'),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.group)),
              title: Text(widget.chatRoomName),
              subtitle: Text(widget.isGroup ? '${_members.length} 位成员' : '私聊'),
            ),
            _buildSectionHeader('成员管理'),
            if (_isLoadingMembers)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_memberError != null)
              ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: const Text('成员加载失败'),
                subtitle: Text(_memberError!),
                trailing: TextButton(
                  onPressed: _loadMembers,
                  child: const Text('重试'),
                ),
              )
            else ...[
              if (_currentUserIsAdmin && widget.isGroup)
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1),
                  title: Text(_isLoadingInvitees ? '加载好友中...' : '邀请好友'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _isLoadingInvitees ? null : _showInviteSheet,
                ),
              ..._members.map(
                (member) => _buildMemberTile(member, currentUserId),
              ),
            ],
            if (widget.isGroup) ...[
              _buildSectionHeader('文件'),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('聊天文件'),
                subtitle: const Text('图片和文件'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatFileCenterScreen(
                        chatRoomId: widget.chatRoomId.toString(),
                        chatRoomName: widget.chatRoomName,
                        chatService: _chatService,
                      ),
                    ),
                  );
                },
              ),
              _buildSectionHeader('匿名聊天'),
              SwitchListTile(
                title: const Text('允许匿名聊天'),
                subtitle: const Text('开启后群成员可匿名发言'),
                value: _anonymousEnabled,
                onChanged: _currentUserIsAdmin
                    ? (value) async {
                        final success = await _anonymousService.toggleAnonymous(
                            widget.chatRoomId, value);
                        if (success && mounted) {
                          setState(() => _anonymousEnabled = value);
                        }
                      }
                    : null,
                secondary: const Icon(Icons.masks),
              ),
              _buildSectionHeader('AI 机器人'),
              ..._bots.map(
                (bot) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue[100],
                    child: const Icon(Icons.smart_toy, color: Colors.blue),
                  ),
                  title: Text(bot.botName),
                  subtitle: Text(bot.llmProvider),
                  trailing: _currentUserIsAdmin
                      ? IconButton(
                          icon: const Icon(
                            Icons.remove_circle,
                            color: Colors.red,
                          ),
                          onPressed: () async {
                            await _removeBotFromRoom(bot);
                          },
                        )
                      : null,
                ),
              ),
              if (_currentUserIsAdmin)
                ListTile(
                  leading: const Icon(Icons.add_circle, color: Colors.green),
                  title: const Text('添加机器人'),
                  onTap: _showAddBotSheet,
                ),
            ],
            _buildSectionHeader('通知设置'),
            SwitchListTile(
              title: const Text('消息免打扰'),
              value: _isMuted,
              onChanged: (value) => _updateRoomPreferences(muted: value),
              secondary: const Icon(Icons.notifications_off),
            ),
            SwitchListTile(
              title: const Text('置顶聊天'),
              value: _isPinned,
              onChanged: (value) => _updateRoomPreferences(pinned: value),
              secondary: const Icon(Icons.push_pin),
            ),
            _buildSectionHeader('操作'),
            ListTile(
              leading:
                  const Icon(Icons.cleaning_services, color: Colors.orange),
              title: const Text('清空聊天记录'),
              onTap: _clearChatHistory,
            ),
            if (widget.isGroup)
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text('退出群聊'),
                onTap: _leaveGroup,
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(ChatRoomMember member, String? currentUserId) {
    final isSelf = member.userId == currentUserId;
    final canManage =
        _currentUserIsAdmin && widget.isGroup && !isSelf && member.canBeManaged;

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: member.user.avatarUrl != null
            ? NetworkImage(
                ApiConstants.resolveFileUrl(member.user.avatarUrl!),
              )
            : null,
        child: member.user.avatarUrl == null
            ? Text(_avatarText(member.displayName))
            : null,
      ),
      title: Row(
        children: [
          Flexible(child: Text(member.displayName)),
          if (isSelf)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('我', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
      subtitle: Text(_memberSubtitle(member)),
      trailing: canManage
          ? PopupMenuButton<String>(
              onSelected: (value) => _handleMemberAction(value, member),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'admin',
                  child: Text(member.isAdmin ? '取消管理员' : '设为管理员'),
                ),
                PopupMenuItem(
                  value: 'mute',
                  child: Text(member.isMuted ? '取消禁言' : '禁言成员'),
                ),
                const PopupMenuItem(
                  value: 'kick',
                  child: Text('移出群聊'),
                ),
              ],
            )
          : null,
    );
  }

  String _memberSubtitle(ChatRoomMember member) {
    final parts = <String>[];
    if (member.isAdmin) {
      parts.add('管理员');
    } else {
      parts.add(member.roleDescription ?? '成员');
    }
    if (member.isMuted) {
      parts.add('已禁言');
    }
    return parts.join(' · ');
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  String _avatarText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }
}
