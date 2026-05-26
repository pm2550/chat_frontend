import 'package:flutter/material.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../models/call_state.dart';
import '../../models/chat.dart';
import '../../models/user.dart';
import '../../services/contact_data_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import '../chat/chat_screen.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, this.contactService});

  final ContactDataService? contactService;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addSearchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final ContactDataService _contactService;

  String _searchQuery = '';
  List<User> _contacts = [];
  List<FriendshipRequest> _receivedRequests = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _openingChatUserId;

  @override
  void initState() {
    super.initState();
    _contactService = widget.contactService ?? ContactDataService();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final contacts = await _contactService.getFriends();
      final receivedRequests =
          await _contactService.getReceivedFriendRequests();
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _receivedRequests = receivedRequests;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<User> get _filteredContacts {
    if (_searchQuery.isEmpty) {
      return _contacts;
    }
    final keyword = _searchQuery.toLowerCase();
    return _contacts.where((contact) {
      return contact.displayName.toLowerCase().contains(keyword) ||
          contact.username.toLowerCase().contains(keyword) ||
          contact.email.toLowerCase().contains(keyword) ||
          (contact.phone?.contains(_searchQuery) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (PMBreakpoints.isDesktop(context)) {
      return _buildDesktopScaffold();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('联系人'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _searchFocusNode.requestFocus(),
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _showAddContactSheet,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showContactMoreMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBox(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorState()
                    : RefreshIndicator(
                        onRefresh: _loadContacts,
                        child: _buildContactList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopScaffold() {
    final contacts = _filteredContacts;
    return Scaffold(
      body: PMChatPattern(
        dense: true,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                PMDesktopHeader(
                  title: '通讯录',
                  subtitle: '管理联系人、好友请求、快速建群和私聊入口',
                  icon: Icons.groups_2,
                  actions: [
                    _buildDesktopActionButton(
                      icon: Icons.group_add,
                      label: '新建群聊',
                      onTap: _showCreateGroupSheet,
                    ),
                    const SizedBox(width: 10),
                    _buildDesktopActionButton(
                      icon: Icons.person_add,
                      label: '添加联系人',
                      onTap: _showAddContactSheet,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: PMDesktopCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: _buildDesktopSearchBox(),
                              ),
                              const Divider(
                                height: 1,
                                color: AppColors.borderLight,
                              ),
                              Expanded(
                                child: _isLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : _errorMessage != null
                                        ? _buildErrorState()
                                        : RefreshIndicator(
                                            onRefresh: _loadContacts,
                                            child: contacts.isEmpty
                                                ? ListView(
                                                    children: [
                                                      SizedBox(
                                                        height: 420,
                                                        child:
                                                            _buildEmptyState(),
                                                      ),
                                                    ],
                                                  )
                                                : ListView(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            12),
                                                    children: [
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.fromLTRB(
                                                          8,
                                                          4,
                                                          8,
                                                          12,
                                                        ),
                                                        child: PMSectionHeader(
                                                          title: '联系人列表',
                                                          subtitle:
                                                              '点击联系人可发起私聊、语音或视频邀请',
                                                        ),
                                                      ),
                                                      ...contacts.map(
                                                        _buildContactItem,
                                                      ),
                                                    ],
                                                  ),
                                          ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      SizedBox(
                        width: 340,
                        child: Column(
                          children: [
                            PMDesktopCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const PMSectionHeader(
                                    title: '快速操作',
                                    subtitle: '建群、添加和处理好友请求',
                                  ),
                                  const SizedBox(height: 16),
                                  _buildDesktopQuickAction(
                                    Icons.group_add,
                                    '新建群聊',
                                    '选择多个联系人开启团队会话',
                                    _showCreateGroupSheet,
                                  ),
                                  const SizedBox(height: 10),
                                  _buildDesktopQuickAction(
                                    Icons.qr_code_scanner,
                                    '扫码 / 粘贴添加',
                                    '通过用户 ID、用户名或邮箱添加',
                                    _showScanAddDialog,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Expanded(
                              child: PMDesktopCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    PMSectionHeader(
                                      title: '好友请求',
                                      subtitle:
                                          '${_receivedRequests.length} 条待处理',
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: _receivedRequests.isEmpty
                                          ? const Center(
                                              child: Text(
                                                '暂无新的好友请求',
                                                style: TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              ),
                                            )
                                          : ListView(
                                              children: _receivedRequests
                                                  .map(_buildRequestItem)
                                                  .toList(),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    );
  }

  Widget _buildDesktopSearchBox() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        hintText: '搜索联系人、用户名、邮箱或手机号',
        prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
      ),
    );
  }

  Widget _buildDesktopQuickAction(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cloud,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.pixelBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: '搜索联系人',
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildContactList() {
    final contacts = _filteredContacts;
    final showQuickActions = _searchQuery.isEmpty;

    if (contacts.isEmpty && _receivedRequests.isEmpty && !showQuickActions) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: _buildEmptyState(),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (showQuickActions) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildQuickAction(
                    icon: Icons.group_add,
                    label: '新建群聊',
                    onTap: _showCreateGroupSheet,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQuickAction(
                    icon: Icons.qr_code_scanner,
                    label: '扫一扫',
                    onTap: _showScanAddDialog,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_receivedRequests.isNotEmpty && showQuickActions) ...[
          _buildSectionTitle('新的好友请求'),
          ..._receivedRequests.map(_buildRequestItem),
          const SizedBox(height: 8),
        ],
        if (contacts.isNotEmpty) ...[
          _buildSectionTitle('联系人'),
          ...contacts.map(_buildContactItem),
          const SizedBox(height: 16),
        ] else
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.42,
            child: _buildEmptyState(),
          ),
      ],
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              '联系人加载失败',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadContacts,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.contacts_outlined,
            size: 80,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? '暂无联系人' : '没有找到相关联系人',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '点击右上角按钮添加联系人',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequestItem(FriendshipRequest request) {
    final user = request.user;
    return _buildUserCard(
      user: user,
      subtitle: '请求添加你为好友',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '拒绝',
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: () => _declineRequest(request),
          ),
          IconButton(
            tooltip: '接受',
            icon: const Icon(Icons.check, color: AppColors.success),
            onPressed: () => _acceptRequest(request),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(User contact) {
    final isOpening = _openingChatUserId == contact.id;
    return _buildUserCard(
      user: contact,
      onTap: () => _showContactOptions(contact),
      subtitle: contact.email,
      secondarySubtitle: contact.phone,
      trailing: isOpening
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              contact.onlineStatus == OnlineStatus.online
                  ? '在线'
                  : contact.lastSeen != null
                      ? _formatLastSeen(contact.lastSeen!)
                      : '离线',
              style: TextStyle(
                color: contact.onlineStatus == OnlineStatus.online
                    ? AppColors.online
                    : AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
    );
  }

  Widget _buildUserCard({
    required User user,
    String? subtitle,
    String? secondarySubtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildAvatar(user, radius: 28),
        title: Text(
          _displayName(user),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null && subtitle.isNotEmpty)
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (secondarySubtitle != null && secondarySubtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                secondarySubtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: trailing,
      ),
    );
  }

  Widget _buildAvatar(User user, {required double radius}) {
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          backgroundImage: user.avatarUrl != null
              ? NetworkImage(ApiConstants.resolveFileUrl(user.avatarUrl!))
              : null,
          child: user.avatarUrl == null
              ? Text(
                  _displayName(user).isNotEmpty
                      ? _displayName(user)[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: radius <= 28 ? 18 : 24,
                  ),
                )
              : null,
        ),
        if (user.onlineStatus == OnlineStatus.online)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _acceptRequest(FriendshipRequest request) async {
    try {
      await _contactService.acceptFriendRequest(request.user.id);
      _showSnackBar('已添加 ${_displayName(request.user)}');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _declineRequest(FriendshipRequest request) async {
    try {
      await _contactService.declineFriendRequest(request.user.id);
      _showSnackBar('已拒绝好友请求');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _startChat(User contact) async {
    if (_openingChatUserId != null) {
      return;
    }

    setState(() {
      _openingChatUserId = contact.id;
    });

    try {
      final Chat chat = await _contactService.createPrivateChat(contact.id);
      if (!mounted) return;
      await Navigator.pushNamed(context, '/chat', arguments: chat);
    } catch (e) {
      if (mounted) {
        _showSnackBar(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingChatUserId = null;
        });
      }
    }
  }

  Future<void> _startContactCall(
    User contact,
    CallMediaKind mediaKind,
  ) async {
    if (_openingChatUserId != null) {
      return;
    }

    setState(() {
      _openingChatUserId = contact.id;
    });

    final label = '${mediaKind.label}通话';
    try {
      final chat = await _contactService.createPrivateChat(contact.id);
      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        '/chat',
        arguments: ChatScreenArguments(
          chat: chat,
          startCall: mediaKind,
        ),
      );
    } catch (e) {
      _showSnackBar('$label启动失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _openingChatUserId = null;
        });
      }
    }
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
    }
  }

  void _showContactOptions(User contact) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildAvatar(contact, radius: 40),
                      const SizedBox(height: 16),
                      Text(
                        _displayName(contact),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        contact.onlineStatus == OnlineStatus.online
                            ? '在线'
                            : '离线',
                        style: TextStyle(
                          color: contact.onlineStatus == OnlineStatus.online
                              ? AppColors.online
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(
                            icon: Icons.chat,
                            label: '发消息',
                            onPressed: () {
                              Navigator.pop(context);
                              _startChat(contact);
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.videocam,
                            label: '视频通话',
                            onPressed: () {
                              Navigator.pop(context);
                              _startContactCall(
                                contact,
                                CallMediaKind.video,
                              );
                            },
                          ),
                          _buildActionButton(
                            icon: Icons.call,
                            label: '语音通话',
                            onPressed: () {
                              Navigator.pop(context);
                              _startContactCall(
                                contact,
                                CallMediaKind.audio,
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildContactDetailLine(
                        Icons.email,
                        '邮箱',
                        contact.email,
                      ),
                      if (contact.phone != null && contact.phone!.isNotEmpty)
                        _buildContactDetailLine(
                          Icons.phone,
                          '手机号',
                          contact.phone!,
                        ),
                      if (contact.bio != null && contact.bio!.isNotEmpty)
                        _buildContactDetailLine(
                          Icons.notes,
                          '简介',
                          contact.bio!,
                        ),
                      if (contact.lastSeen != null)
                        _buildContactDetailLine(
                          Icons.access_time,
                          '最后在线',
                          _formatLastSeen(contact.lastSeen!),
                        ),
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(
                          Icons.person_remove,
                          color: AppColors.error,
                        ),
                        title: const Text(
                          '删除好友',
                          style: TextStyle(color: AppColors.error),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _removeContact(contact);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddContactSheet() {
    _addSearchController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        List<User> results = [];
        Set<String> requestedUserIds = {};
        bool isSearching = false;
        String? errorMessage;

        Future<void> runSearch(StateSetter setSheetState) async {
          final keyword = _addSearchController.text.trim();
          if (keyword.isEmpty) {
            setSheetState(() {
              results = [];
              errorMessage = null;
            });
            return;
          }

          setSheetState(() {
            isSearching = true;
            errorMessage = null;
          });

          try {
            final users = await _contactService.searchUsers(keyword);
            final contactIds = _contacts.map((user) => user.id).toSet();
            if (!sheetContext.mounted) return;
            setSheetState(() {
              results =
                  users.where((user) => !contactIds.contains(user.id)).toList();
              isSearching = false;
            });
          } catch (e) {
            if (!sheetContext.mounted) return;
            setSheetState(() {
              errorMessage = e.toString();
              isSearching = false;
            });
          }
        }

        Future<void> sendRequest(
          User user,
          StateSetter setSheetState,
        ) async {
          try {
            await _contactService.sendFriendRequest(user.id);
            if (!sheetContext.mounted) return;
            setSheetState(() {
              requestedUserIds = {...requestedUserIds, user.id};
            });
            _showSnackBar('好友请求已发送');
          } catch (e) {
            _showSnackBar(e.toString());
          }
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '添加联系人',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _addSearchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => runSearch(setSheetState),
                        decoration: InputDecoration(
                          hintText: '搜索用户名、昵称或邮箱',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () => runSearch(setSheetState),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isSearching)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        )
                      else if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        )
                      else if (results.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '输入关键词搜索用户',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final user = results[index];
                              final requested =
                                  requestedUserIds.contains(user.id);
                              return ListTile(
                                leading: _buildAvatar(user, radius: 22),
                                title: Text(
                                  _displayName(user),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  user.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: requested
                                    ? const Text(
                                        '已发送',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      )
                                    : FilledButton(
                                        onPressed: () => sendRequest(
                                          user,
                                          setSheetState,
                                        ),
                                        child: const Text('添加'),
                                      ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showContactMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新联系人'),
              onTap: () {
                Navigator.pop(context);
                _loadContacts();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('添加联系人'),
              onTap: () {
                Navigator.pop(context);
                _showAddContactSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('新建群聊'),
              onTap: () {
                Navigator.pop(context);
                _showCreateGroupSheet();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateGroupSheet() {
    final nameController = TextEditingController();
    final selectedIds = <String>{};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '新建群聊',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '群聊名称'),
                  ),
                  const SizedBox(height: 12),
                  if (_contacts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('暂无联系人可加入群聊'),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _contacts.length,
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
                          final selected = selectedIds.contains(contact.id);
                          return CheckboxListTile(
                            value: selected,
                            title: Text(_displayName(contact)),
                            subtitle: Text(contact.email),
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selectedIds.add(contact.id);
                                } else {
                                  selectedIds.remove(contact.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          _showSnackBar('请输入群聊名称');
                          return;
                        }
                        try {
                          final chat = await _contactService.createGroupChat(
                            name: name,
                            memberIds: selectedIds.toList(),
                          );
                          if (!sheetContext.mounted || !mounted) return;
                          Navigator.pop(sheetContext);
                          await Navigator.pushNamed(
                            context,
                            '/chat',
                            arguments: chat,
                          );
                        } catch (e) {
                          _showSnackBar('建群失败: $e');
                        }
                      },
                      child: const Text('创建'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(nameController.dispose);
  }

  Future<void> _showScanAddDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫码添加'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '用户ID、用户名或邮箱',
            hintText: '可粘贴二维码识别结果',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;

    try {
      final directId = int.tryParse(value);
      if (directId != null) {
        await _contactService.sendFriendRequest(directId.toString());
        _showSnackBar('好友请求已发送');
        return;
      }

      final users = await _contactService.searchUsers(value, limit: 1);
      if (users.isEmpty) {
        _showSnackBar('未找到用户');
        return;
      }
      await _contactService.sendFriendRequest(users.first.id);
      _showSnackBar('已向 ${_displayName(users.first)} 发送好友请求');
    } catch (e) {
      _showSnackBar('添加失败: $e');
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: IconButton(
            icon: Icon(icon, color: AppColors.primary),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildContactDetailLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeContact(User contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除 ${_displayName(contact)} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await _contactService.removeFriend(contact.id);
      _showSnackBar('已删除 ${_displayName(contact)}');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  String _displayName(User user) {
    if (user.displayName.isNotEmpty) {
      return user.displayName;
    }
    if (user.username.isNotEmpty) {
      return user.username;
    }
    return user.email;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _addSearchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
}
