import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../models/call_state.dart';
import '../../models/chat.dart';
import '../../models/contact_group.dart';
import '../../models/user.dart';
import '../../services/chat_data_service.dart';
import '../../services/contact_data_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';
import '../chat/chat_screen.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, this.contactService, this.chatService});

  final ContactDataService? contactService;
  final ChatDataService? chatService;

  static Future<void> warmDirectoryCache() =>
      _ContactsPageState.warmDirectoryCache();

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsSnapshot {
  const _ContactsSnapshot({
    required this.contacts,
    required this.receivedRequests,
    required this.groupChats,
    required this.privateChats,
    required this.contactGroups,
    required this.groupAssignmentsByTarget,
    required this.groupCollapsed,
  });

  final List<User> contacts;
  final List<FriendshipRequest> receivedRequests;
  final List<Chat> groupChats;
  final List<Chat> privateChats;
  final List<ContactGroup> contactGroups;
  final Map<String, ContactGroupAssignment> groupAssignmentsByTarget;
  final Map<String, bool> groupCollapsed;
}

class _ContactsPageState extends State<ContactsPage>
    with AutomaticKeepAliveClientMixin<ContactsPage> {
  static const String _sectionGroups = 'groups';
  static const String _sectionPrivate = 'private';
  static const String _sectionContacts = 'contacts';
  static const String _sectionPrefPrefix = 'pmchat.contacts.section.collapsed.';
  static const String _groupPrefPrefix = 'pmchat.contacts.group.collapsed.';
  static const Duration _snapshotTtl = Duration(minutes: 2);
  static _ContactsSnapshot? _cachedSnapshot;
  static DateTime? _cachedSnapshotAt;

  static Future<void> warmDirectoryCache() async {
    try {
      final snapshot = await _fetchSnapshot(
        contactService: ContactDataService(),
        chatService: ChatDataService(),
      );
      _cachedSnapshot = snapshot;
      _cachedSnapshotAt = DateTime.now();
    } catch (_) {
      // Best-effort preloading must never block the home shell.
    }
  }

  static Future<_ContactsSnapshot> _fetchSnapshot({
    required ContactDataService contactService,
    required ChatDataService chatService,
  }) async {
    final results = await Future.wait<dynamic>([
      contactService.getFriends(),
      contactService.getReceivedFriendRequests(),
      chatService.getChatRooms(
        includeHidden: true,
        includeBlocked: true,
        type: ChatType.group,
      ),
      chatService.getChatRooms(
        includeHidden: true,
        includeBlocked: true,
        type: ChatType.private,
      ),
      contactService.getContactGroups(),
    ]);
    final contacts = results[0] as List<User>;
    final receivedRequests = results[1] as List<FriendshipRequest>;
    final groupChats = results[2] as List<Chat>;
    final privateChats = results[3] as List<Chat>;
    final contactGroups = results[4] as ContactGroupBundle;
    final groupCollapsed =
        await _loadGroupCollapseStatesForGroups(contactGroups.groups);
    final assignmentsByTarget = {
      for (final assignment in contactGroups.assignments)
        assignment.targetKey: assignment,
    };
    return _ContactsSnapshot(
      contacts: List<User>.from(contacts),
      receivedRequests: List<FriendshipRequest>.from(receivedRequests),
      groupChats: List<Chat>.from(groupChats),
      privateChats: List<Chat>.from(privateChats),
      contactGroups: List<ContactGroup>.from(contactGroups.groups),
      groupAssignmentsByTarget:
          Map<String, ContactGroupAssignment>.from(assignmentsByTarget),
      groupCollapsed: Map<String, bool>.from(groupCollapsed),
    );
  }

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addSearchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final ContactDataService _contactService;
  late final ChatDataService _chatService;

  String _searchQuery = '';
  List<User> _contacts = [];
  List<FriendshipRequest> _receivedRequests = [];
  List<Chat> _groupChats = [];
  List<Chat> _privateChats = [];
  List<ContactGroup> _contactGroups = [];
  Map<String, ContactGroupAssignment> _groupAssignmentsByTarget = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _openingChatUserId;
  String? _unblockingRoomId;
  String? _movingTargetKey;
  final Map<String, bool> _sectionCollapsed = {
    _sectionGroups: false,
    _sectionPrivate: false,
    _sectionContacts: false,
  };
  Map<String, bool> _groupCollapsed = {};

  @override
  void initState() {
    super.initState();
    _contactService = widget.contactService ?? ContactDataService();
    _chatService = widget.chatService ?? ChatDataService();
    _restoreSnapshotIfFresh();
    _loadCollapsedSections();
    _loadContacts(showLoading: _contacts.isEmpty);
  }

  bool get _canUseSnapshot =>
      widget.contactService == null && widget.chatService == null;

  void _restoreSnapshotIfFresh() {
    if (!_canUseSnapshot) return;
    final snapshot = _cachedSnapshot;
    final snapshotAt = _cachedSnapshotAt;
    if (snapshot == null ||
        snapshotAt == null ||
        DateTime.now().difference(snapshotAt) >= _snapshotTtl) {
      return;
    }
    _contacts = List<User>.from(snapshot.contacts);
    _receivedRequests = List<FriendshipRequest>.from(snapshot.receivedRequests);
    _groupChats = List<Chat>.from(snapshot.groupChats);
    _privateChats = List<Chat>.from(snapshot.privateChats);
    _contactGroups = List<ContactGroup>.from(snapshot.contactGroups);
    _groupAssignmentsByTarget = Map<String, ContactGroupAssignment>.from(
        snapshot.groupAssignmentsByTarget);
    _groupCollapsed = Map<String, bool>.from(snapshot.groupCollapsed);
    _isLoading = false;
  }

  Future<void> _loadCollapsedSections() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final section in _sectionCollapsed.keys) {
        _sectionCollapsed[section] =
            prefs.getBool('$_sectionPrefPrefix$section') ?? false;
      }
    });
  }

  static Future<Map<String, bool>> _loadGroupCollapseStatesForGroups(
    List<ContactGroup> groups,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final states = <String, bool>{};
    for (final group in groups) {
      states[_groupCollapseKeyFor(group.id)] =
          prefs.getBool('$_groupPrefPrefix${_groupCollapseKeyFor(group.id)}') ??
              false;
    }
    for (final section in [_sectionGroups, _sectionPrivate, _sectionContacts]) {
      states[_ungroupedCollapseKeyFor(section)] = prefs.getBool(
              '$_groupPrefPrefix${_ungroupedCollapseKeyFor(section)}') ??
          false;
    }
    return states;
  }

  bool _isSectionCollapsed(String section) =>
      _sectionCollapsed[section] ?? false;

  Future<void> _toggleSectionCollapsed(String section) async {
    final next = !_isSectionCollapsed(section);
    setState(() {
      _sectionCollapsed[section] = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_sectionPrefPrefix$section', next);
  }

  bool _isGroupBlockCollapsed(String key) => _groupCollapsed[key] ?? false;

  Future<void> _toggleGroupBlockCollapsed(String key) async {
    final next = !_isGroupBlockCollapsed(key);
    setState(() {
      _groupCollapsed = {..._groupCollapsed, key: next};
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_groupPrefPrefix$key', next);
  }

  String _groupCollapseKey(String groupId) => _groupCollapseKeyFor(groupId);

  static String _groupCollapseKeyFor(String groupId) => 'group:$groupId';

  String _ungroupedCollapseKey(String section) =>
      _ungroupedCollapseKeyFor(section);

  static String _ungroupedCollapseKeyFor(String section) =>
      'ungrouped:$section';

  Future<void> _loadContacts({bool showLoading = true}) async {
    if (mounted && showLoading && _contacts.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (mounted && showLoading) {
      setState(() {
        _errorMessage = null;
      });
    }

    try {
      final snapshot = await _fetchSnapshot(
        contactService: _contactService,
        chatService: _chatService,
      );
      if (_canUseSnapshot) {
        _cachedSnapshot = snapshot;
        _cachedSnapshotAt = DateTime.now();
      }
      if (!mounted) return;
      setState(() {
        _contacts = snapshot.contacts;
        _receivedRequests = snapshot.receivedRequests;
        _groupChats = snapshot.groupChats;
        _privateChats = snapshot.privateChats;
        _contactGroups = snapshot.contactGroups;
        _groupAssignmentsByTarget = snapshot.groupAssignmentsByTarget;
        _groupCollapsed = snapshot.groupCollapsed;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!showLoading && _contacts.isNotEmpty) {
        return;
      }
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

  List<Chat> get _filteredGroupChats => _filterChats(_groupChats);

  List<Chat> get _filteredPrivateChats => _filterChats(_privateChats);

  List<Chat> _filterChats(List<Chat> chats) {
    if (_searchQuery.isEmpty) {
      return chats;
    }
    final keyword = _searchQuery.toLowerCase();
    return chats
        .where((chat) =>
            chat.name.toLowerCase().contains(keyword) ||
            (chat.description?.toLowerCase().contains(keyword) ?? false))
        .toList();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
    final groupChats = _filteredGroupChats;
    final privateChats = _filteredPrivateChats;
    final hasDirectoryItems =
        contacts.isNotEmpty || groupChats.isNotEmpty || privateChats.isNotEmpty;
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
                    const SizedBox(width: 10),
                    _buildDesktopActionButton(
                      icon: Icons.folder_open,
                      label: '管理分组',
                      onTap: _showGroupManagementSheet,
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
                                            child: !hasDirectoryItems
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
                                                      if (groupChats
                                                          .isNotEmpty) ...[
                                                        _buildDesktopSectionHeader(
                                                          section:
                                                              _sectionGroups,
                                                          title: '我的群聊',
                                                          subtitle:
                                                              '已加入群聊，含移出或屏蔽会话',
                                                          count:
                                                              groupChats.length,
                                                        ),
                                                        if (!_isSectionCollapsed(
                                                            _sectionGroups))
                                                          ..._buildGroupedRoomWidgets(
                                                            _sectionGroups,
                                                            groupChats,
                                                          ),
                                                        const SizedBox(
                                                            height: 12),
                                                      ],
                                                      if (privateChats
                                                          .isNotEmpty) ...[
                                                        _buildDesktopSectionHeader(
                                                          section:
                                                              _sectionPrivate,
                                                          title: '私聊',
                                                          subtitle:
                                                              '全部已加入私聊，含移出或屏蔽会话',
                                                          count: privateChats
                                                              .length,
                                                        ),
                                                        if (!_isSectionCollapsed(
                                                            _sectionPrivate))
                                                          ..._buildGroupedRoomWidgets(
                                                            _sectionPrivate,
                                                            privateChats,
                                                          ),
                                                        const SizedBox(
                                                            height: 12),
                                                      ],
                                                      if (contacts.isNotEmpty)
                                                        _buildDesktopSectionHeader(
                                                          section:
                                                              _sectionContacts,
                                                          title: '联系人列表',
                                                          subtitle:
                                                              '点击联系人可发起私聊、语音或视频邀请',
                                                          count:
                                                              contacts.length,
                                                        ),
                                                      if (contacts.isNotEmpty &&
                                                          !_isSectionCollapsed(
                                                              _sectionContacts))
                                                        ..._buildGroupedContactWidgets(
                                                          _sectionContacts,
                                                          contacts,
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
                                  const SizedBox(height: 10),
                                  _buildDesktopQuickAction(
                                    Icons.folder_open,
                                    '管理分组',
                                    '新建、改名、排序和删除自定义分组',
                                    _showGroupManagementSheet,
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

  Widget _buildDesktopSectionHeader({
    required String section,
    required String title,
    required String subtitle,
    required int count,
  }) {
    final collapsed = _isSectionCollapsed(section);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: InkWell(
        onTap: () => _toggleSectionCollapsed(section),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: PMSectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCountPill(count),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: collapsed ? 0 : 0.25,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.pixelBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
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
    final groupChats = _filteredGroupChats;
    final privateChats = _filteredPrivateChats;
    final showQuickActions = _searchQuery.isEmpty;
    final hasDirectoryItems =
        contacts.isNotEmpty || groupChats.isNotEmpty || privateChats.isNotEmpty;

    if (!hasDirectoryItems && _receivedRequests.isEmpty && !showQuickActions) {
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
        if (groupChats.isNotEmpty) ...[
          _buildSectionTitle(
            '我的群聊',
            section: _sectionGroups,
            count: groupChats.length,
          ),
          if (!_isSectionCollapsed(_sectionGroups))
            ..._buildGroupedRoomWidgets(_sectionGroups, groupChats),
          const SizedBox(height: 12),
        ],
        if (privateChats.isNotEmpty) ...[
          _buildSectionTitle(
            '私聊',
            section: _sectionPrivate,
            count: privateChats.length,
          ),
          if (!_isSectionCollapsed(_sectionPrivate))
            ..._buildGroupedRoomWidgets(_sectionPrivate, privateChats),
          const SizedBox(height: 12),
        ],
        if (contacts.isNotEmpty) ...[
          _buildSectionTitle(
            '联系人',
            section: _sectionContacts,
            count: contacts.length,
          ),
          if (!_isSectionCollapsed(_sectionContacts))
            ..._buildGroupedContactWidgets(_sectionContacts, contacts),
          const SizedBox(height: 16),
        ] else if (!hasDirectoryItems)
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

  Widget _buildSectionTitle(
    String title, {
    String? section,
    int? count,
  }) {
    final collapsed = section != null && _isSectionCollapsed(section);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: InkWell(
        onTap: section == null ? null : () => _toggleSectionCollapsed(section),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count != null) ...[
                _buildCountPill(count),
                const SizedBox(width: 6),
              ],
              if (section != null)
                AnimatedRotation(
                  turns: collapsed ? 0 : 0.25,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
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

  List<Widget> _buildGroupedRoomWidgets(String section, List<Chat> chats) {
    final blocks = _groupItems<Chat>(
      section: section,
      items: chats,
      targetKeyFor: (chat) => ContactGroupTargetKey.build(
        ContactGroupTargetType.room,
        chat.id,
      ),
    );
    return [
      for (final block in blocks) ...[
        _buildGroupBlockHeader(block),
        if (!_isGroupBlockCollapsed(block.collapseKey))
          ...block.items.map(_buildRoomItem),
      ],
    ];
  }

  List<Widget> _buildGroupedContactWidgets(
      String section, List<User> contacts) {
    final blocks = _groupItems<User>(
      section: section,
      items: contacts,
      targetKeyFor: (user) => ContactGroupTargetKey.build(
        ContactGroupTargetType.friend,
        user.id,
      ),
    );
    return [
      for (final block in blocks) ...[
        _buildGroupBlockHeader(block),
        if (!_isGroupBlockCollapsed(block.collapseKey))
          ...block.items.map(_buildContactItem),
      ],
    ];
  }

  List<_ContactGroupBlock<T>> _groupItems<T>({
    required String section,
    required List<T> items,
    required String Function(T item) targetKeyFor,
  }) {
    final knownGroupIds = _contactGroups.map((group) => group.id).toSet();
    final grouped = <String, List<T>>{
      for (final group in _contactGroups) group.id: <T>[],
    };
    final ungrouped = <T>[];

    for (final item in items) {
      final assignment = _groupAssignmentsByTarget[targetKeyFor(item)];
      final groupId = assignment?.groupId;
      if (groupId != null && knownGroupIds.contains(groupId)) {
        grouped[groupId]!.add(item);
      } else {
        ungrouped.add(item);
      }
    }

    return [
      for (final group in _contactGroups)
        if ((grouped[group.id] ?? <T>[]).isNotEmpty)
          _ContactGroupBlock<T>(
            title: group.name,
            collapseKey: _groupCollapseKey(group.id),
            items: grouped[group.id]!,
          ),
      if (ungrouped.isNotEmpty)
        _ContactGroupBlock<T>(
          title: '未分组',
          collapseKey: _ungroupedCollapseKey(section),
          items: ungrouped,
          isUngrouped: true,
        ),
    ];
  }

  Widget _buildGroupBlockHeader<T>(_ContactGroupBlock<T> block) {
    final collapsed = _isGroupBlockCollapsed(block.collapseKey);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
      child: InkWell(
        onTap: () => _toggleGroupBlockCollapsed(block.collapseKey),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(
                block.isUngrouped ? Icons.inbox_outlined : Icons.folder_open,
                size: 17,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  block.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildCountPill(block.items.length),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: collapsed ? 0 : 0.25,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
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
      onLongPress: () => _showMoveToGroupSheet(
        targetType: ContactGroupTargetType.friend,
        targetId: contact.id,
        title: _displayName(contact),
      ),
      onSecondaryTapDown: (_) => _showMoveToGroupSheet(
        targetType: ContactGroupTargetType.friend,
        targetId: contact.id,
        title: _displayName(contact),
      ),
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

  Widget _buildRoomItem(Chat chat) {
    final isUnblocking = _unblockingRoomId == chat.id;
    return GestureDetector(
      onLongPress: () => _showMoveToGroupSheet(
        targetType: ContactGroupTargetType.room,
        targetId: chat.id,
        title: chat.name,
      ),
      onSecondaryTapDown: (_) => _showMoveToGroupSheet(
        targetType: ContactGroupTargetType.room,
        targetId: chat.id,
        title: chat.name,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: chat.isBlocked
                ? AppColors.error.withValues(alpha: 0.35)
                : AppColors.borderLight,
          ),
          boxShadow: const [AppColors.cardShadow],
        ),
        child: ListTile(
          onTap: () => _openChatRoom(chat),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _buildRoomAvatar(chat),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  chat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              if (chat.isBlocked) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '已屏蔽',
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            chat.lastMessage?.resolvedFileLabel ??
                (chat.type == ChatType.group ? '群聊' : '私聊'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          trailing: chat.isBlocked
              ? TextButton(
                  onPressed: isUnblocking
                      ? null
                      : () => _unblockRoomFromContacts(chat),
                  child: isUnblocking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('解除屏蔽'),
                )
              : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildRoomAvatar(Chat chat) {
    if (chat.avatarUrl != null) {
      return CircleAvatar(
        radius: 26,
        backgroundColor: AppColors.pixelBlue,
        backgroundImage:
            NetworkImage(ApiConstants.resolveFileUrl(chat.avatarUrl!)),
      );
    }
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: chat.type == ChatType.group
            ? AppColors.primaryGradient
            : AppColors.accentGradient,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        chat.type == ChatType.group ? Icons.groups_2 : Icons.person,
        color: Colors.white,
      ),
    );
  }

  Future<void> _openChatRoom(Chat chat) async {
    await Navigator.pushNamed(context, '/chat/${chat.id}', arguments: chat);
    if (mounted) {
      await _loadContacts();
    }
  }

  Future<void> _unblockRoomFromContacts(Chat chat) async {
    if (_unblockingRoomId != null) return;
    setState(() {
      _unblockingRoomId = chat.id;
    });
    try {
      await _chatService.unblockChatRoom(chat.id);
      if (!mounted) return;
      _showSnackBar('已解除屏蔽 ${chat.name}');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _unblockingRoomId = null;
        });
      }
    }
  }

  void _showMoveToGroupSheet({
    required ContactGroupTargetType targetType,
    required String targetId,
    required String title,
  }) {
    final targetKey = ContactGroupTargetKey.build(targetType, targetId);
    final currentGroupId = _groupAssignmentsByTarget[targetKey]?.groupId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '移动到分组',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showEditContactGroupSheet();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _buildMoveGroupOption(
                        label: '未分组',
                        selected: currentGroupId == null,
                        loading: _movingTargetKey == targetKey,
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await _assignTargetToGroup(
                            targetType: targetType,
                            targetId: targetId,
                            groupId: null,
                          );
                        },
                      ),
                      for (final group in _contactGroups)
                        _buildMoveGroupOption(
                          label: group.name,
                          selected: currentGroupId == group.id,
                          loading: _movingTargetKey == targetKey,
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await _assignTargetToGroup(
                              targetType: targetType,
                              targetId: targetId,
                              groupId: group.id,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoveGroupOption({
    required String label,
    required bool selected,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.primary : AppColors.textSecondary,
      ),
      title: Text(label),
      trailing: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: loading ? null : onTap,
    );
  }

  Future<void> _assignTargetToGroup({
    required ContactGroupTargetType targetType,
    required String targetId,
    required String? groupId,
  }) async {
    final targetKey = ContactGroupTargetKey.build(targetType, targetId);
    if (_movingTargetKey != null) return;
    setState(() {
      _movingTargetKey = targetKey;
    });
    try {
      await _contactService.assignContactGroupItem(
        targetType: targetType,
        targetId: targetId,
        groupId: groupId,
      );
      _showSnackBar(groupId == null ? '已移到未分组' : '已移动到分组');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _movingTargetKey = null;
        });
      }
    }
  }

  void _showGroupManagementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '分组管理',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showEditContactGroupSheet();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.borderLight),
                Flexible(
                  child: _contactGroups.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(28),
                          child: Text(
                            '暂无自定义分组',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _contactGroups.length,
                          itemBuilder: (context, index) {
                            final group = _contactGroups[index];
                            return ListTile(
                              leading: const Icon(Icons.folder_open),
                              title: Text(group.name),
                              subtitle: Text('排序 ${group.sortOrder}'),
                              trailing: Wrap(
                                spacing: 2,
                                children: [
                                  IconButton(
                                    tooltip: '上移',
                                    onPressed: index == 0
                                        ? null
                                        : () {
                                            Navigator.pop(sheetContext);
                                            _moveContactGroup(index, -1);
                                          },
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                                  IconButton(
                                    tooltip: '下移',
                                    onPressed:
                                        index == _contactGroups.length - 1
                                            ? null
                                            : () {
                                                Navigator.pop(sheetContext);
                                                _moveContactGroup(index, 1);
                                              },
                                    icon: const Icon(Icons.arrow_downward),
                                  ),
                                  IconButton(
                                    tooltip: '改名',
                                    onPressed: () {
                                      Navigator.pop(sheetContext);
                                      _showEditContactGroupSheet(group: group);
                                    },
                                    icon: const Icon(Icons.edit),
                                  ),
                                  IconButton(
                                    tooltip: '删除',
                                    onPressed: () {
                                      Navigator.pop(sheetContext);
                                      _confirmDeleteContactGroup(group);
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditContactGroupSheet({ContactGroup? group}) async {
    var draftName = group?.name ?? '';
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group == null ? '新建分组' : '重命名分组',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                TextFormField(
                  initialValue: draftName,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '分组名称'),
                  onChanged: (value) => draftName = value,
                  onFieldSubmitted: (value) =>
                      Navigator.pop(sheetContext, value.trim()),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(sheetContext, draftName.trim()),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (name == null || name.isEmpty) return;

    try {
      if (group == null) {
        await _contactService.createContactGroup(name);
        _showSnackBar('分组已创建');
      } else {
        await _contactService.updateContactGroup(
          group.id,
          name: name,
          sortOrder: group.sortOrder,
        );
        _showSnackBar('分组已更新');
      }
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _confirmDeleteContactGroup(ContactGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('删除「${group.name}」后，里面的联系人和会话会回到未分组。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _contactService.deleteContactGroup(group.id);
      _showSnackBar('分组已删除，条目已回到未分组');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _moveContactGroup(int index, int delta) async {
    final targetIndex = index + delta;
    if (targetIndex < 0 || targetIndex >= _contactGroups.length) return;
    final ids = _contactGroups.map((group) => group.id).toList();
    final moving = ids.removeAt(index);
    ids.insert(targetIndex, moving);
    try {
      await _contactService.reorderContactGroups(ids);
      _showSnackBar('分组排序已更新');
      await _loadContacts();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Widget _buildUserCard({
    required User user,
    String? subtitle,
    String? secondarySubtitle,
    Widget? trailing,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    GestureTapDownCallback? onSecondaryTapDown,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              if (secondarySubtitle != null &&
                  secondarySubtitle.isNotEmpty) ...[
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
      await Navigator.pushNamed(context, '/chat/${chat.id}', arguments: chat);
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
        '/chat/${chat.id}',
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
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('管理分组'),
              onTap: () {
                Navigator.pop(context);
                _showGroupManagementSheet();
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
                            '/chat/${chat.id}',
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

class _ContactGroupBlock<T> {
  const _ContactGroupBlock({
    required this.title,
    required this.collapseKey,
    required this.items,
    this.isUngrouped = false,
  });

  final String title;
  final String collapseKey;
  final List<T> items;
  final bool isUngrouped;
}
