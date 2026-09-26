import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../constants/api_constants.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../models/call_state.dart';
import '../../models/chat.dart';
import '../../models/contact_group.dart';
import '../../models/user.dart';
import '../../services/chat_data_service.dart';
import '../../services/chat_room_directory.dart';
import '../../services/auth_service.dart';
import '../../services/contact_data_service.dart';
import '../../services/persistent_data_cache.dart';
import '../../services/websocket_service.dart';
import '../../widgets/pm_responsive.dart';
import '../chat/chat_screen.dart';
import 'add_friend_screen.dart';
import 'qr_scanner_page.dart';

part 'sub/contacts_data.dart';
part 'sub/contacts_actions_1.dart';
part 'sub/contacts_actions_2.dart';
part 'sub/contacts_actions_3.dart';
part 'sub/contacts_people.dart';
part 'sub/contacts_view_1.dart';
part 'sub/contacts_view_2.dart';

/// 联系人：好友和所有私聊过的人合在一张列表里，点一个人就进入和他的私聊。
class ContactsPage extends StatefulWidget {
  const ContactsPage({
    super.key,
    this.contactService,
    this.chatService,
    this.realtimeService,
    this.currentUserId,
    this.compact = false,
    this.selectedChatId,
    this.onOpenChat,
  });

  final ContactDataService? contactService;
  final ChatDataService? chatService;
  final ChatRealtimeService? realtimeService;
  final String? currentUserId;

  /// 桌面聊天页的中间栏：只列联系人，当前私聊高亮，点别人切换私聊。
  final bool compact;
  final String? selectedChatId;
  final Future<void> Function(ChatScreenArguments)? onOpenChat;

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
    required this.contactGroups,
    required this.groupAssignmentsByTarget,
    required this.groupCollapsed,
  });

  final List<User> contacts;
  final List<FriendshipRequest> receivedRequests;
  final List<Chat> groupChats;
  final List<ContactGroup> contactGroups;
  final Map<String, ContactGroupAssignment> groupAssignmentsByTarget;
  final Map<String, bool> groupCollapsed;

  Map<String, dynamic> toJson() => {
        'contacts': contacts.map((contact) => contact.toJson()).toList(),
        'receivedRequests':
            receivedRequests.map((request) => request.toJson()).toList(),
        'groupChats': groupChats.map((chat) => chat.toJson()).toList(),
        'contactGroups': contactGroups.map((group) => group.toJson()).toList(),
        'groupAssignments': groupAssignmentsByTarget.values
            .map((assignment) => assignment.toJson())
            .toList(),
        'groupCollapsed': groupCollapsed,
      };

  factory _ContactsSnapshot.fromJson(Map<String, dynamic> json) {
    final assignments = (json['groupAssignments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ContactGroupAssignment.fromJson)
        .toList();
    return _ContactsSnapshot(
      contacts: (json['contacts'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(User.fromJson)
          .toList(),
      receivedRequests: (json['receivedRequests'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FriendshipRequest.fromJson)
          .toList(),
      groupChats: (json['groupChats'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Chat.fromJson)
          .toList(),
      contactGroups: (json['contactGroups'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ContactGroup.fromJson)
          .toList(),
      groupAssignmentsByTarget: {
        for (final assignment in assignments) assignment.targetKey: assignment,
      },
      groupCollapsed: (json['groupCollapsed'] as Map? ?? const {})
          .map((key, value) => MapEntry(key.toString(), value == true)),
    );
  }
}

class _ContactsPageState extends State<ContactsPage>
    with AutomaticKeepAliveClientMixin<ContactsPage> {
  static const String _sectionGroups = 'groups';
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
      contactService.getContactGroups(),
    ]);
    final contacts = results[0] as List<User>;
    final receivedRequests = results[1] as List<FriendshipRequest>;
    final groupChats = results[2] as List<Chat>;
    final contactGroups = results[3] as ContactGroupBundle;
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

  /// 私聊（和消息页共用、跟着实时事件更新），联系人列表由好友和它合并而成。
  late final ChatRoomDirectory _directory;

  String _searchQuery = '';
  List<User> _contacts = [];
  List<FriendshipRequest> _receivedRequests = [];
  List<Chat> _groupChats = [];
  List<ContactGroup> _contactGroups = [];
  Map<String, ContactGroupAssignment> _groupAssignmentsByTarget = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _openingChatUserId;
  String? _unblockingRoomId;
  String? _movingTargetKey;
  final Map<String, bool> _sectionCollapsed = {
    _sectionGroups: false,
    _sectionContacts: false,
  };
  Map<String, bool> _groupCollapsed = {};

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('zh', timeago.ZhCnMessages());
    _contactService = widget.contactService ?? ContactDataService();
    _directory = ChatRoomDirectory.of(
      chatService: widget.chatService,
      realtimeService: widget.realtimeService,
      currentUserId: widget.currentUserId,
    );
    _chatService = _directory.chatService;
    _directory.privateChats.addListener(_onPrivateChatsChanged);
    _restoreSnapshotIfFresh();
    _loadCollapsedSections();
    unawaited(_bootstrapContacts());
    // 测试里注入了假数据服务却没给实时服务时不去连真的 WebSocket。
    if (widget.realtimeService != null || widget.chatService == null) {
      unawaited((widget.realtimeService ?? WebSocketService()).connect());
    }
  }

  void _onPrivateChatsChanged() {
    runOutsideBuild(() {
      if (mounted) setState(() {});
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
    for (final section in [_sectionGroups, _sectionContacts]) {
      states[_ungroupedCollapseKeyFor(section)] = prefs.getBool(
              '$_groupPrefPrefix${_ungroupedCollapseKeyFor(section)}') ??
          false;
    }
    return states;
  }

  static String _groupCollapseKeyFor(String groupId) => 'group:$groupId';

  static String _ungroupedCollapseKeyFor(String section) =>
      'ungrouped:$section';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.compact) {
      return _buildCompactScaffold();
    }
    if (PMBreakpoints.isDesktop(context)) {
      return _buildDesktopScaffold();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('联系人'),
        actions: [
          IconButton(
            tooltip: '搜索联系人',
            icon: const Icon(Icons.search),
            onPressed: () => _searchFocusNode.requestFocus(),
          ),
          IconButton(
            tooltip: '添加联系人',
            icon: const Icon(Icons.person_add),
            onPressed: _showAddContactSheet,
          ),
          IconButton(
            tooltip: '联系人选项',
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

  @override
  void dispose() {
    _directory.privateChats.removeListener(_onPrivateChatsChanged);
    _searchController.dispose();
    _addSearchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _setViewState(VoidCallback change) {
    if (mounted) setState(change);
  }
}

/// 联系人列表里的一个人：好友，或者私聊过的非好友；[chat] 是和他的私聊（可能还没有）。
class _ContactEntry {
  const _ContactEntry({
    required this.user,
    required this.isFriend,
    this.chat,
  });

  final User user;
  final bool isFriend;
  final Chat? chat;

  bool get isPinned => chat?.isPinned ?? false;
  bool get isMuted => chat?.isMuted ?? false;
  bool get isBlocked => chat?.isBlocked ?? false;
  int get unreadCount => chat?.unreadCount ?? 0;
  DateTime? get lastMessageAt => chat?.lastMessage?.timestamp;
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
