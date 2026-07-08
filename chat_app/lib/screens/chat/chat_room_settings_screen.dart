import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/chat_customization.dart';
import '../../models/chat_room_member.dart';
import '../../models/user.dart';
import '../../services/anonymous_service.dart';
import '../../services/auth_service.dart';
import '../../services/bot_service.dart';
import '../../services/chat_data_service.dart';
import '../../services/contact_data_service.dart';
import '../../widgets/pm_responsive.dart';
import 'anonymous_theme_picker_screen.dart';
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
  bool _currentUserIsOwner = false;
  bool _isMuted = false;
  bool _isPinned = false;
  bool _isSavingRoom = false;
  String? _memberError;
  late String _roomName;
  String? _roomDescription;
  String? _roomAnnouncement;
  String? _roomAvatarUrl;
  String? _roomBackgroundPreset;
  String? _roomBackgroundUrl;
  DateTime? _announcementUpdatedAt;
  String? _announcementUpdatedBy;
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
    _roomName = widget.chatRoomName;
    _anonymousEnabled = widget.initialAnonymousEnabled;
    _currentUserIsAdmin = widget.isAdmin;
    _loadRoomDetails();
    _loadMembers();
    _loadRoomPreferences();
    if (widget.isGroup && widget.enableBotLoading) {
      _loadBots();
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadRoomDetails(),
      _loadMembers(),
      _loadRoomPreferences(),
      if (widget.isGroup && widget.enableBotLoading) _loadBots(),
    ]);
  }

  Future<void> _loadRoomDetails() async {
    try {
      final room = await _chatService.getChatRoom(
        widget.chatRoomId.toString(),
        includeDetails: false,
      );
      if (!mounted) return;
      setState(() {
        _roomName = room.name;
        _roomDescription = room.description;
        _roomAnnouncement = room.announcement;
        _roomAvatarUrl = room.avatarUrl;
        _roomBackgroundPreset = room.customBackgroundPreset;
        _roomBackgroundUrl = room.customBackgroundUrl;
        _announcementUpdatedAt = room.announcementUpdatedAt;
        _announcementUpdatedBy = room.announcementUpdatedBy;
        _anonymousEnabled = room.anonymousEnabled;
      });
    } catch (_) {
      // The settings page can still operate from the route-provided room name.
    }
  }

  Future<void> _loadRoomPreferences() async {
    try {
      final settings = await _chatService
          .getNotificationSettings(widget.chatRoomId.toString());
      if (!mounted) return;
      setState(() {
        _isMuted = _parsePreferenceBool(settings['muted'], 'muted');
        _isPinned = _parsePreferenceBool(settings['pinned'], 'pinned');
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
        _isMuted = _parsePreferenceBool(settings['muted'], 'muted');
        _isPinned = _parsePreferenceBool(settings['pinned'], 'pinned');
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

  Future<void> _showEditRoomSheet() async {
    final result = await showModalBottomSheet<_RoomInfoDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RoomInfoEditorSheet(
        initialName: _roomName,
        initialDescription: _roomDescription ?? '',
        initialAnnouncement: _roomAnnouncement ?? '',
      ),
    );
    if (result == null) return;
    await _updateRoomInfo(result);
  }

  Future<void> _updateRoomInfo(_RoomInfoDraft draft) async {
    final name = draft.name.trim();
    if (name.isEmpty) {
      _showSnackBar('群名不能为空', isError: true);
      return;
    }

    setState(() => _isSavingRoom = true);
    try {
      final room = await _chatService.updateChatRoom(
        widget.chatRoomId.toString(),
        name: name,
        description: draft.description.trim(),
        announcement: draft.announcement.trim(),
      );
      if (!mounted) return;
      setState(() {
        _roomName = room.name;
        _roomDescription = room.description;
        _roomAnnouncement = room.announcement;
        _roomAvatarUrl = room.avatarUrl;
        _announcementUpdatedAt = room.announcementUpdatedAt;
        _announcementUpdatedBy = room.announcementUpdatedBy;
        _isSavingRoom = false;
      });
      _showSnackBar('群资料已更新');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingRoom = false);
      _showSnackBar('群资料更新失败: $error', isError: true);
    }
  }

  Future<void> _setRoomBackgroundPreset(String preset) async {
    if (!_currentUserIsAdmin) return;
    setState(() => _isSavingRoom = true);
    try {
      final room = await _chatService.updateRoomBackgroundPreset(
        widget.chatRoomId.toString(),
        preset,
      );
      if (!mounted) return;
      setState(() {
        _roomBackgroundPreset = room.customBackgroundPreset;
        _roomBackgroundUrl = room.customBackgroundUrl;
        _isSavingRoom = false;
      });
      _showSnackBar('房间背景已更新');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingRoom = false);
      _showSnackBar('房间背景更新失败: $error', isError: true);
    }
  }

  Future<void> _pickAndUploadRoomBackground() async {
    if (!_currentUserIsAdmin) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.size > 2 * 1024 * 1024) {
      _showSnackBar('背景图片不能超过 2MB', isError: true);
      return;
    }

    setState(() => _isSavingRoom = true);
    try {
      final room = await _chatService.uploadRoomBackground(
        widget.chatRoomId.toString(),
        PickedChatFile(
          name: file.name,
          path: file.path,
          size: file.size,
          bytes: file.bytes,
        ),
      );
      if (!mounted) return;
      setState(() {
        _roomBackgroundPreset = room.customBackgroundPreset;
        _roomBackgroundUrl = room.customBackgroundUrl;
        _isSavingRoom = false;
      });
      _showSnackBar('房间背景已上传');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingRoom = false);
      _showSnackBar('房间背景上传失败: $error', isError: true);
    }
  }

  Future<void> _pickAndUploadRoomAvatar() async {
    if (!_currentUserIsAdmin || !widget.isGroup) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;

    setState(() => _isSavingRoom = true);
    try {
      final room = await _chatService.uploadRoomAvatar(
        widget.chatRoomId.toString(),
        PickedChatFile(
          name: file.name,
          path: file.path,
          size: file.size,
          bytes: file.bytes,
        ),
      );
      if (!mounted) return;
      setState(() {
        _roomAvatarUrl = room.avatarUrl;
        _roomName = room.name;
        _isSavingRoom = false;
      });
      _showSnackBar('群头像已更新');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingRoom = false);
      _showSnackBar('群头像上传失败: $error', isError: true);
    }
  }

  Future<void> _clearRoomBackground() async {
    if (!_currentUserIsAdmin) return;
    setState(() => _isSavingRoom = true);
    try {
      final room = await _chatService.clearRoomBackground(
        widget.chatRoomId.toString(),
      );
      if (!mounted) return;
      setState(() {
        _roomBackgroundPreset = room.customBackgroundPreset;
        _roomBackgroundUrl = room.customBackgroundUrl;
        _isSavingRoom = false;
      });
      _showSnackBar('已恢复成员个人背景');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingRoom = false);
      _showSnackBar('恢复失败: $error', isError: true);
    }
  }

  Future<void> _showMemberProfileSheet(ChatRoomMember member) async {
    final isSelf = member.userId == _currentUserId;
    final canEditTitle = _currentUserIsAdmin;
    final nicknameController = TextEditingController(text: member.nickname);
    final titleController = TextEditingController(text: member.memberTitle);
    final result = await showModalBottomSheet<_MemberProfileDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: PMSpacing.l,
          right: PMSpacing.l,
          bottom: MediaQuery.of(context).viewInsets.bottom + PMSpacing.l,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PMDialogHeader(
                title: isSelf ? '我的群名片' : '成员名片',
                subtitle: isSelf ? '设置你在本群显示的昵称' : member.user.displayName,
                showHandle: false,
                onClose: () => Navigator.pop(context),
              ),
              const SizedBox(height: PMSpacing.l),
              TextField(
                controller: nicknameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '群昵称',
                  prefixIcon: Icon(Icons.badge),
                  hintText: '留空则使用个人昵称',
                ),
              ),
              const SizedBox(height: PMSpacing.m),
              TextField(
                controller: titleController,
                enabled: canEditTitle,
                decoration: InputDecoration(
                  labelText: '群头衔',
                  prefixIcon: const Icon(Icons.workspace_premium),
                  hintText: canEditTitle ? '例如 项目负责人' : '只有管理员可设置',
                ),
              ),
              const SizedBox(height: PMSpacing.l),
              PMButton(
                label: '保存名片',
                icon: Icons.check,
                onPressed: () => Navigator.pop(
                  context,
                  _MemberProfileDraft(
                    nickname: nicknameController.text,
                    memberTitle: canEditTitle
                        ? titleController.text
                        : member.memberTitle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    nicknameController.dispose();
    titleController.dispose();
    if (result == null) return;
    await _updateMemberProfile(member, result);
  }

  Future<void> _updateMemberProfile(
    ChatRoomMember member,
    _MemberProfileDraft draft,
  ) async {
    try {
      await _chatService.updateChatRoomMemberProfile(
        widget.chatRoomId.toString(),
        member.userId,
        nickname: draft.nickname,
        memberTitle: _currentUserIsAdmin ? draft.memberTitle : null,
      );
      await _loadMembers();
      _showSnackBar('群名片已更新');
    } catch (error) {
      _showSnackBar('群名片更新失败: $error', isError: true);
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
    // Re-entered from member-action handlers (role/transfer/kick/mute) after their own
    // network awaits; guard before the entry setState in case the screen was popped.
    if (!mounted) return;
    setState(() {
      _isLoadingMembers = true;
      _memberError = null;
    });

    try {
      final members =
          await _chatService.getChatRoomMembers(widget.chatRoomId.toString());
      if (!mounted) return;
      final currentUserId = _currentUserId;
      setState(() {
        _members = members;
        _currentUserIsAdmin = widget.isAdmin ||
            members.any(
                (member) => member.userId == currentUserId && member.isAdmin);
        // F5: real OWNER role, derived from the authoritative member list.
        _currentUserIsOwner = members.any(
            (member) => member.userId == currentUserId && member.isOwner);
        _isLoadingMembers = false;
      });
    } catch (error) {
      if (!mounted) return;
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
                        leading: PMUserAvatar.raw(
                          imageUrl: _resolveAvatarUrl(user.avatarUrl),
                          fallbackText: user.displayName,
                          framePreset: user.avatarFramePreset,
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
      appBar: AppBar(title: Text(widget.isGroup ? '群聊设置' : '聊天信息')),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(PMSpacing.l),
          children: [
            _buildRoomHero(),
            if (widget.isGroup) ...[
              const SizedBox(height: PMSpacing.l),
              _buildGroupProfileSection(currentUserId),
            ],
            const SizedBox(height: PMSpacing.l),
            _buildMembersSection(currentUserId),
            if (widget.isGroup) ...[
              const SizedBox(height: PMSpacing.l),
              _buildRoomBackgroundSection(),
              const SizedBox(height: PMSpacing.l),
              _buildFilesSection(),
              const SizedBox(height: PMSpacing.l),
              _buildBotsSection(),
            ],
            const SizedBox(height: PMSpacing.l),
            _buildBehaviorSection(),
            const SizedBox(height: PMSpacing.l),
            _buildDangerSection(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomHero() {
    final displayName = _settingsDisplayName();
    return PMCard(
      padding: const EdgeInsets.all(PMSpacing.xl),
      background: AppColors.pixelBlue,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              PMUserAvatar.raw(
                imageUrl: _resolveAvatarUrl(_roomAvatarUrl),
                fallbackText: widget.isGroup ? '群' : displayName,
                isGroup: widget.isGroup,
                size: 68,
              ),
              if (widget.isGroup && _currentUserIsAdmin)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Tooltip(
                    message: '更改群头像',
                    child: InkWell(
                      key: const Key('change-room-avatar-button'),
                      onTap: _isSavingRoom ? null : _pickAndUploadRoomAvatar,
                      borderRadius: BorderRadius.circular(PMRadius.pill),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                          boxShadow: const [PMElevation.subtle],
                        ),
                        child: const Icon(
                          Icons.add_a_photo,
                          size: 15,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: PMSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: PMSpacing.xs),
                Text(
                  widget.isGroup ? '${_members.length} 位成员' : '私聊成员与聊天偏好',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (widget.isGroup)
            PMButton(
              label: _isSavingRoom ? '保存中' : '编辑群资料',
              icon: Icons.edit,
              onPressed: _currentUserIsAdmin && !_isSavingRoom
                  ? _showEditRoomSheet
                  : null,
              variant: PMButtonVariant.secondary,
              compact: true,
            ),
        ],
      ),
    );
  }

  String _settingsDisplayName() {
    if (widget.isGroup) {
      return _roomName;
    }
    final currentUserId = _currentUserId;
    final peer = _members.firstWhere(
      (member) => currentUserId == null || member.userId != currentUserId,
      orElse: () => _members.isNotEmpty
          ? _members.first
          : ChatRoomMember(
              id: '',
              userId: '',
              role: 'MEMBER',
              joinedAt: DateTime.now(),
              user: User(
                id: '',
                username: _roomName,
                email: '',
                displayName: _roomName,
                createdAt: DateTime.now(),
              ),
            ),
    );
    return peer.displayName.trim().isNotEmpty ? peer.displayName : _roomName;
  }

  Widget _buildGroupProfileSection(String? currentUserId) {
    final currentMember = _currentMember(currentUserId);
    final description = _roomDescription?.trim();
    final announcement = _roomAnnouncement?.trim();
    return PMSectionCard(
      title: '群资料与群名片',
      subtitle: '群名、说明、成员在本群内的显示身份',
      trailing: _currentUserIsAdmin
          ? PMButton(
              label: '编辑',
              icon: Icons.edit,
              compact: true,
              variant: PMButtonVariant.secondary,
              onPressed: _isSavingRoom ? null : _showEditRoomSheet,
            )
          : null,
      children: [
        PMListRow(
          leading: _iconTile(Icons.campaign_rounded, AppColors.warning),
          title: const Text('群公告'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                announcement == null || announcement.isEmpty
                    ? '暂无群公告'
                    : announcement,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (_announcementUpdatedText() != null) ...[
                const SizedBox(height: PMSpacing.xs),
                Text(
                  _announcementUpdatedText()!,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          trailing: _currentUserIsAdmin
              ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
              : null,
          onTap: _currentUserIsAdmin ? _showEditRoomSheet : null,
        ),
        PMListRow(
          leading:
              _iconTile(Icons.drive_file_rename_outline, AppColors.primary),
          title: const Text('群名'),
          subtitle: Text(_roomName),
          trailing: _currentUserIsAdmin
              ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
              : null,
          onTap: _currentUserIsAdmin ? _showEditRoomSheet : null,
        ),
        PMListRow(
          leading: _iconTile(Icons.notes, AppColors.info),
          title: const Text('群说明'),
          subtitle: Text(
            description == null || description.isEmpty ? '暂无群说明' : description,
          ),
          trailing: _currentUserIsAdmin
              ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
              : null,
          onTap: _currentUserIsAdmin ? _showEditRoomSheet : null,
        ),
        if (currentMember != null)
          PMListRow(
            leading: _iconTile(Icons.badge, AppColors.secondaryDark),
            title: const Text('我的群名片'),
            subtitle: Text(
              [
                currentMember.displayName,
                if ((currentMember.memberTitle ?? '').isNotEmpty)
                  currentMember.memberTitle ?? '',
              ].join(' · '),
            ),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            onTap: () => _showMemberProfileSheet(currentMember),
          ),
      ],
    );
  }

  Widget _buildRoomBackgroundSection() {
    final customUrl = _roomBackgroundUrl?.trim();
    final activePreset = _roomBackgroundPreset?.trim();
    final hasOverride = (customUrl != null && customUrl.isNotEmpty) ||
        (activePreset != null && activePreset.isNotEmpty);
    return PMSectionCard(
      title: '房间外观',
      subtitle: hasOverride ? '管理员设置的背景会覆盖成员个人聊天背景' : '未设置房间背景时，成员会看到自己的聊天偏好背景',
      trailing: Wrap(
        spacing: PMSpacing.s,
        children: [
          PMButton(
            label: '上传',
            icon: Icons.upload,
            compact: true,
            variant: PMButtonVariant.secondary,
            onPressed: _currentUserIsAdmin && !_isSavingRoom
                ? _pickAndUploadRoomBackground
                : null,
          ),
          PMButton(
            label: '恢复个人',
            icon: Icons.layers_clear,
            compact: true,
            variant: PMButtonVariant.secondary,
            onPressed: _currentUserIsAdmin && hasOverride && !_isSavingRoom
                ? _clearRoomBackground
                : null,
          ),
        ],
      ),
      children: [
        if (customUrl != null && customUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PMSpacing.l,
              PMSpacing.m,
              PMSpacing.l,
              0,
            ),
            child: SizedBox(
              height: 112,
              child: PMBackgroundPreview(
                preset: activePreset == null || activePreset.isEmpty
                    ? ChatCustomizationCatalog.defaultBackground
                    : activePreset,
                customUrl: customUrl,
                selected: true,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(PMSpacing.l),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ChatCustomizationCatalog.backgrounds.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 210,
              mainAxisExtent: 166,
              crossAxisSpacing: PMSpacing.m,
              mainAxisSpacing: PMSpacing.m,
            ),
            itemBuilder: (context, index) {
              final option = ChatCustomizationCatalog.backgrounds[index];
              final selected = option.id == activePreset &&
                  (customUrl == null || customUrl.isEmpty);
              return PMCard(
                padding: const EdgeInsets.all(PMSpacing.s),
                elevated: selected,
                interactive: _currentUserIsAdmin,
                onTap: _currentUserIsAdmin && !_isSavingRoom
                    ? () => _setRoomBackgroundPreset(option.id)
                    : null,
                background: selected ? AppColors.pixelBlue : Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: PMBackgroundPreview(
                        preset: option.id,
                        selected: selected,
                      ),
                    ),
                    const SizedBox(height: PMSpacing.s),
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      option.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMembersSection(String? currentUserId) {
    if (_isLoadingMembers) {
      return PMSectionCard(
        title: widget.isGroup ? '成员管理' : '私聊成员',
        subtitle: widget.isGroup ? '加载群成员和权限' : '加载私聊成员',
        children: [
          Padding(
            padding: const EdgeInsets.all(PMSpacing.l),
            child: PMSkeleton.row(),
          ),
        ],
      );
    }
    if (_memberError != null) {
      return PMSectionCard(
        title: widget.isGroup ? '成员管理' : '私聊成员',
        subtitle: widget.isGroup ? '加载群成员和权限' : '加载私聊成员',
        children: [
          PMErrorState(message: _memberError!, onRetry: _loadMembers),
        ],
      );
    }

    return PMSectionCard(
      title: widget.isGroup ? '成员管理' : '私聊成员',
      subtitle: widget.isGroup ? '横向浏览成员，管理员可邀请和管理权限' : '当前私聊成员',
      trailing: widget.isGroup
          ? TextButton(
              onPressed: _showMembersSheet,
              child: Text('查看全部 ${_members.length}'),
            )
          : null,
      children: [
        if (widget.isGroup)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PMSpacing.l,
              PMSpacing.m,
              PMSpacing.l,
              0,
            ),
            child: Wrap(
              spacing: PMSpacing.s,
              runSpacing: PMSpacing.s,
              children: [
                PMButton(
                  label: '邀请成员',
                  icon: Icons.person_add,
                  compact: true,
                  variant: PMButtonVariant.secondary,
                  onPressed: _currentUserIsAdmin && !_isLoadingInvitees
                      ? _showInviteSheet
                      : null,
                ),
                PMButton(
                  label: '刷新成员',
                  icon: Icons.refresh,
                  compact: true,
                  variant: PMButtonVariant.secondary,
                  onPressed: _loadMembers,
                ),
                PMButton(
                  label: '群名片',
                  icon: Icons.badge,
                  compact: true,
                  variant: PMButtonVariant.secondary,
                  onPressed: () {
                    final member = _currentMember(currentUserId);
                    if (member != null) {
                      _showMemberProfileSheet(member);
                    }
                  },
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(PMSpacing.s),
          child: SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _members.length,
              separatorBuilder: (_, __) => const SizedBox(width: PMSpacing.m),
              itemBuilder: (context, index) =>
                  _buildMemberAvatar(_members[index]),
            ),
          ),
        ),
        if (_currentUserIsAdmin && widget.isGroup)
          PMListRow(
            leading: _iconTile(Icons.person_add_alt_1, AppColors.primary),
            title: Text(_isLoadingInvitees ? '加载好友中...' : '邀请好友'),
            subtitle: const Text('从联系人中添加新成员'),
            trailing:
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            onTap: _isLoadingInvitees ? null : _showInviteSheet,
          ),
        ..._members.map((member) => _buildMemberTile(member, currentUserId)),
      ],
    );
  }

  Widget _buildMemberAvatar(ChatRoomMember member) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          PMUserAvatar.raw(
            imageUrl: _resolveAvatarUrl(member.user.avatarUrl),
            fallbackText: member.displayName,
            framePreset: member.user.avatarFramePreset,
            showOnlineDot: true,
            size: 48,
          ),
          const SizedBox(height: PMSpacing.s),
          Text(
            member.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _showMembersSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(PMSpacing.l),
          children: [
            PMDialogHeader(
              title: '全部成员',
              subtitle: '${_members.length} 位成员',
              onClose: () => Navigator.pop(context),
              showHandle: false,
            ),
            const SizedBox(height: PMSpacing.l),
            for (final member in _members)
              _buildMemberTile(member, _currentUserId),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesSection() {
    return PMSectionCard(
      title: '文件',
      subtitle: '图片、文档和附件入口',
      children: [
        PMListRow(
          leading: _iconTile(Icons.folder_open, AppColors.primary),
          title: const Text('聊天文件'),
          subtitle: const Text('图片和文件'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatFileCenterScreen(
                  chatRoomId: widget.chatRoomId.toString(),
                  chatRoomName: _roomName,
                  chatService: _chatService,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBotsSection() {
    return PMSectionCard(
      title: 'AI 机器人',
      subtitle: '启用 Bot 参与这个群组',
      trailing: _currentUserIsAdmin
          ? TextButton.icon(
              onPressed: _showAddBotSheet,
              icon: const Icon(Icons.add),
              label: const Text('添加机器人'),
            )
          : null,
      children: [
        if (_bots.isEmpty)
          const PMEmptyState(
            icon: Icons.smart_toy_outlined,
            title: '暂无机器人',
            subtitle: '添加机器人后可在群聊中通过提及触发。',
            variant: EmptyStateVariant.muted,
          )
        else
          Padding(
            padding: const EdgeInsets.all(PMSpacing.s),
            child: Wrap(
              spacing: PMSpacing.m,
              runSpacing: PMSpacing.m,
              children: _bots.map(_buildBotCard).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildBotCard(BotConfig bot) {
    return SizedBox(
      width: 220,
      child: PMCard(
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconTile(Icons.smart_toy_outlined, AppColors.secondaryDark),
                const SizedBox(width: PMSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bot.botName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        bot.llmProvider,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_currentUserIsAdmin)
                  IconButton(
                    tooltip: '移除机器人',
                    icon:
                        const Icon(Icons.remove_circle, color: AppColors.error),
                    onPressed: () => _removeBotFromRoom(bot),
                  ),
              ],
            ),
            const SizedBox(height: PMSpacing.m),
            PMChip(
              label: _botTriggerLabel(bot.triggerMode),
              icon: _botTriggerIcon(bot.triggerMode),
              selected: true,
              color: AppColors.secondaryDark,
            ),
          ],
        ),
      ),
    );
  }

  String _botTriggerLabel(String? mode) {
    return switch ((mode ?? 'MENTION').toUpperCase()) {
      'KEYWORD' => '关键词触发',
      'REGEX' => '正则触发',
      'ALL' => '全消息触发',
      _ => '提及触发',
    };
  }

  IconData _botTriggerIcon(String? mode) {
    return switch ((mode ?? 'MENTION').toUpperCase()) {
      'KEYWORD' => Icons.key,
      'REGEX' => Icons.data_object,
      'ALL' => Icons.all_inclusive,
      _ => Icons.alternate_email,
    };
  }

  Widget _buildBehaviorSection() {
    return PMSectionCard(
      title: '行为',
      subtitle: '会话通知、置顶和匿名能力',
      children: [
        PMListRow(
          leading: _iconTile(Icons.notifications_off, AppColors.primary),
          title: const Text('消息免打扰'),
          subtitle: const Text('开启后不再弹出这个群组的新消息提醒'),
          trailing: Switch(
            value: _isMuted,
            onChanged: (value) => _updateRoomPreferences(muted: value),
          ),
        ),
        PMListRow(
          leading: _iconTile(Icons.push_pin, AppColors.warning),
          title: const Text('置顶聊天'),
          subtitle: const Text('开启后这个会话会固定在聊天列表顶部'),
          trailing: Switch(
            value: _isPinned,
            onChanged: (value) => _updateRoomPreferences(pinned: value),
          ),
        ),
        if (widget.isGroup)
          Column(
            children: [
              PMListRow(
                leading:
                    _iconTile(Icons.masks_outlined, AppColors.secondaryDark),
                title: const Text('允许匿名聊天'),
                subtitle: const Text(
                  '开启后，群成员可以用匿名身份发言。匿名消息显示为预设头像和随机代号。',
                ),
                trailing: Switch(
                  value: _anonymousEnabled,
                  onChanged: _currentUserIsAdmin
                      ? (value) async {
                          final success =
                              await _anonymousService.toggleAnonymous(
                            widget.chatRoomId,
                            value,
                          );
                          if (success && mounted) {
                            setState(() => _anonymousEnabled = value);
                          }
                        }
                      : null,
                ),
              ),
              if (_anonymousEnabled)
                PMListRow(
                  leading: _iconTile(
                    Icons.palette_outlined,
                    const Color(0xFF7C3AED),
                  ),
                  title: const Text('匿名主题'),
                  subtitle: const Text('选择本群统一的匿名名称和颜色风格'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AnonymousThemePickerScreen(
                          roomId: widget.chatRoomId,
                          canEdit: _currentUserIsAdmin,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildDangerSection() {
    return PMSectionCard(
      title: '管理区',
      subtitle: '清空记录和退出群聊需要二次确认',
      children: [
        PMListRow(
          leading:
              _iconTile(Icons.cleaning_services_outlined, AppColors.warning),
          title: const Text('清空聊天记录'),
          subtitle: const Text('只清空你自己的可见历史'),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: _clearChatHistory,
        ),
        if (widget.isGroup)
          PMListRow(
            key: const Key('leave-group-row'),
            leading: _iconTile(Icons.exit_to_app, AppColors.error),
            title: const Text(
              '退出群聊',
              style: TextStyle(color: AppColors.error),
            ),
            subtitle: const Text('退出后将不再接收这个群聊的消息'),
            trailing: const Icon(Icons.chevron_right, color: AppColors.error),
            onTap: _leaveGroup,
          ),
      ],
    );
  }

  Widget _buildMemberTile(ChatRoomMember member, String? currentUserId) {
    final isSelf = member.userId == currentUserId;
    final canManage =
        _currentUserIsAdmin && widget.isGroup && !isSelf && member.canBeManaged;
    final canEditProfile = widget.isGroup && (isSelf || _currentUserIsAdmin);
    final showTextActions = PMBreakpoints.isDesktop(context);
    // F5: owner-only role + transfer controls. Gated at render (not at click) so
    // non-owners never see them.
    final showOwnerControls =
        _currentUserIsOwner && widget.isGroup && !isSelf && !member.isOwner;

    final tile = PMListRow(
      leading: PMUserAvatar.raw(
        imageUrl: _resolveAvatarUrl(member.user.avatarUrl),
        fallbackText: member.displayName,
        framePreset: member.user.avatarFramePreset,
        showOnlineDot: true,
      ),
      title: Row(
        children: [
          Flexible(child: Text(member.displayName)),
          if (isSelf)
            const Padding(
              padding: EdgeInsets.only(left: PMSpacing.s),
              child: Text('我', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
      subtitle: _memberSubtitleWidget(member),
      trailing: canManage
          ? Wrap(
              spacing: showTextActions ? 6 : 2,
              runSpacing: 4,
              children: [
                if (showTextActions)
                  _memberActionButton(
                    icon: member.isAdmin
                        ? Icons.admin_panel_settings
                        : Icons.admin_panel_settings_outlined,
                    label: member.isAdmin ? '取消管理' : '设管理员',
                    tooltip: member.isAdmin ? '取消管理员' : '设为管理员',
                    color: member.isAdmin
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    onPressed: () => _handleMemberAction('admin', member),
                  )
                else
                  IconButton(
                    tooltip: member.isAdmin ? '取消管理员' : '设为管理员',
                    icon: Icon(
                      member.isAdmin
                          ? Icons.admin_panel_settings
                          : Icons.admin_panel_settings_outlined,
                      color: member.isAdmin
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    onPressed: () => _handleMemberAction('admin', member),
                  ),
                if (showTextActions)
                  _memberActionButton(
                    icon: member.isMuted ? Icons.volume_up : Icons.volume_off,
                    label: member.isMuted ? '解禁' : '禁言',
                    tooltip: member.isMuted ? '取消禁言' : '禁言成员',
                    color: member.isMuted
                        ? AppColors.warning
                        : AppColors.textSecondary,
                    onPressed: () => _handleMemberAction('mute', member),
                  )
                else
                  IconButton(
                    tooltip: member.isMuted ? '取消禁言' : '禁言成员',
                    icon: Icon(
                      member.isMuted ? Icons.volume_up : Icons.volume_off,
                      color: member.isMuted
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                    onPressed: () => _handleMemberAction('mute', member),
                  ),
                if (showTextActions)
                  _memberActionButton(
                    icon: Icons.badge,
                    label: '群名片',
                    tooltip: '编辑群名片和头衔',
                    color: AppColors.secondaryDark,
                    onPressed: () => _showMemberProfileSheet(member),
                  )
                else
                  IconButton(
                    tooltip: '编辑群名片和头衔',
                    icon:
                        const Icon(Icons.badge, color: AppColors.secondaryDark),
                    onPressed: () => _showMemberProfileSheet(member),
                  ),
                if (showTextActions)
                  _memberActionButton(
                    icon: Icons.person_remove,
                    label: '踢出',
                    tooltip: '移出群聊',
                    color: AppColors.error,
                    onPressed: () => _handleMemberAction('kick', member),
                  )
                else
                  IconButton(
                    tooltip: '移出群聊',
                    icon:
                        const Icon(Icons.person_remove, color: AppColors.error),
                    onPressed: () => _handleMemberAction('kick', member),
                  ),
                PopupMenuButton<String>(
                  tooltip: '更多成员操作',
                  onSelected: (value) {
                    if (value == 'profile') {
                      _showMemberProfileSheet(member);
                    } else {
                      _handleMemberAction(value, member);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'profile',
                      child: Text('编辑群名片'),
                    ),
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
                ),
              ],
            )
          : canEditProfile
              ? IconButton(
                  tooltip: isSelf ? '编辑我的群名片' : '编辑成员群名片',
                  icon: const Icon(Icons.badge, color: AppColors.secondaryDark),
                  onPressed: () => _showMemberProfileSheet(member),
                )
              : null,
    );
    if (!showOwnerControls) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [tile, _ownerControls(member)],
    );
  }

  /// F5: owner-only role chips (成员 / 协管 / 管理员 — never OWNER) + transfer button.
  Widget _ownerControls(ChatRoomMember member) {
    final role = member.role.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(
          left: 56, right: PMSpacing.s, bottom: PMSpacing.s),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('角色',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          PMChip(
            label: '成员',
            selected: role == 'MEMBER',
            onTap: () => _setMemberRole(member, 'MEMBER'),
          ),
          PMChip(
            label: '协管',
            selected: role == 'MODERATOR',
            onTap: () => _setMemberRole(member, 'MODERATOR'),
          ),
          PMChip(
            label: '管理员',
            selected: role == 'ADMIN',
            onTap: () => _setMemberRole(member, 'ADMIN'),
          ),
          PMButton(
            label: '转让群主',
            icon: Icons.workspace_premium_rounded,
            compact: true,
            variant: PMButtonVariant.secondary,
            onPressed: () => _confirmTransferOwnership(member),
          ),
        ],
      ),
    );
  }

  Future<void> _setMemberRole(ChatRoomMember member, String role) async {
    try {
      await _chatService.setChatRoomMemberRole(
        chatRoomId: widget.chatRoomId.toString(),
        userId: member.userId,
        role: role,
      );
      await _loadMembers();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('设置角色失败: $error'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _confirmTransferOwnership(ChatRoomMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const PMDialogHeader(title: '确认转让群主', showHandle: false),
        content: Text('确定将群主转让给 ${member.displayName} 吗？转让后你将降为管理员，'
            '此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _chatService.transferChatRoomOwnership(
        chatRoomId: widget.chatRoomId.toString(),
        newOwnerId: member.userId,
      );
      await _loadMembers();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('转让群主失败: $error'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Widget _memberActionButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: color,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _memberSubtitle(ChatRoomMember member) {
    final parts = <String>[];
    final memberTitle = member.memberTitle ?? '';
    if (memberTitle.isNotEmpty) {
      parts.add(memberTitle);
    }
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

  /// F5: owners get a gold 群主 badge; everyone else keeps the text subtitle.
  Widget _memberSubtitleWidget(ChatRoomMember member) {
    if (!member.isOwner) {
      return Text(_memberSubtitle(member));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const PMChip(
          label: '群主',
          icon: Icons.workspace_premium_rounded,
          selected: true,
          color: Color(0xFFD4A017),
        ),
        if (member.isMuted)
          const Text('已禁言',
              style: TextStyle(fontSize: 12, color: AppColors.warning)),
      ],
    );
  }

  ChatRoomMember? _currentMember(String? currentUserId) {
    if (currentUserId == null) return null;
    for (final member in _members) {
      if (member.userId == currentUserId) {
        return member;
      }
    }
    return null;
  }

  String? _resolveAvatarUrl(String? avatarUrl) {
    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return ApiConstants.resolveFileUrl(url);
  }

  Widget _iconTile(IconData icon, Color color) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PMRadius.m),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }

  bool _parsePreferenceBool(Object? value, String fieldName) {
    if (value is bool) return value;
    if (value == null) return false;
    debugPrint(
      'Chat room preference "$fieldName" expected bool but got '
      '${value.runtimeType}; parsing compatibly.',
    );
    return value.toString().toLowerCase() == 'true';
  }

  String? _announcementUpdatedText() {
    final updatedAt = _announcementUpdatedAt;
    if (updatedAt == null) return null;
    final by = _announcementUpdatedBy;
    final date =
        '${updatedAt.year}-${updatedAt.month.toString().padLeft(2, '0')}-${updatedAt.day.toString().padLeft(2, '0')} '
        '${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}';
    return by == null || by.isEmpty ? '更新于 $date' : '用户 $by 更新于 $date';
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

class _RoomInfoDraft {
  const _RoomInfoDraft({
    required this.name,
    required this.description,
    required this.announcement,
  });

  final String name;
  final String description;
  final String announcement;
}

class _RoomInfoEditorSheet extends StatefulWidget {
  const _RoomInfoEditorSheet({
    required this.initialName,
    required this.initialDescription,
    required this.initialAnnouncement,
  });

  final String initialName;
  final String initialDescription;
  final String initialAnnouncement;

  @override
  State<_RoomInfoEditorSheet> createState() => _RoomInfoEditorSheetState();
}

class _RoomInfoEditorSheetState extends State<_RoomInfoEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _announcementController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController =
        TextEditingController(text: widget.initialDescription);
    _announcementController =
        TextEditingController(text: widget.initialAnnouncement);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _announcementController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: PMSpacing.l,
        right: PMSpacing.l,
        bottom: MediaQuery.of(context).viewInsets.bottom + PMSpacing.l,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PMDialogHeader(
                title: '编辑群资料',
                subtitle: '群名、群说明和群公告会同步给所有成员',
                showHandle: false,
                onClose: () => Navigator.pop(context),
              ),
              const SizedBox(height: PMSpacing.l),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '群名',
                  prefixIcon: Icon(Icons.drive_file_rename_outline),
                ),
              ),
              const SizedBox(height: PMSpacing.m),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '群说明',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: PMSpacing.m),
              TextField(
                controller: _announcementController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '群公告',
                  prefixIcon: Icon(Icons.campaign_rounded),
                ),
              ),
              const SizedBox(height: PMSpacing.l),
              PMButton(
                label: '保存群资料',
                icon: Icons.check,
                onPressed: () => Navigator.pop(
                  context,
                  _RoomInfoDraft(
                    name: _nameController.text,
                    description: _descriptionController.text,
                    announcement: _announcementController.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberProfileDraft {
  const _MemberProfileDraft({
    required this.nickname,
    this.memberTitle,
  });

  final String nickname;
  final String? memberTitle;
}
