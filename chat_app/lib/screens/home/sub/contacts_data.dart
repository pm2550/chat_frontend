part of '../contacts_page.dart';

extension _ContactsData1Parts on _ContactsPageState {
  void _restoreSnapshotIfFresh() {
    if (!_canUseSnapshot) return;
    final snapshot = _ContactsPageState._cachedSnapshot;
    final snapshotAt = _ContactsPageState._cachedSnapshotAt;
    if (snapshot == null ||
        snapshotAt == null ||
        DateTime.now().difference(snapshotAt) >=
            _ContactsPageState._snapshotTtl) {
      return;
    }
    _contacts = List<User>.from(snapshot.contacts);
    _receivedRequests = List<FriendshipRequest>.from(snapshot.receivedRequests);
    _groupChats = List<Chat>.from(snapshot.groupChats);
    _contactGroups = List<ContactGroup>.from(snapshot.contactGroups);
    _groupAssignmentsByTarget = Map<String, ContactGroupAssignment>.from(
        snapshot.groupAssignmentsByTarget);
    _groupCollapsed = Map<String, bool>.from(snapshot.groupCollapsed);
    _isLoading = false;
  }

  Future<void> _bootstrapContacts() async {
    if (_canUseSnapshot) {
      unawaited(_directory.privateChats.restorePersisted());
    }
    if (_canUseSnapshot && _isLoading) {
      final userId = AuthService().currentUser?.id;
      if (userId != null) {
        final record = await PersistentDataCache.read(
          userId: userId,
          namespace: 'contacts-directory',
        );
        final payload = record?['payload'];
        if (mounted && payload is Map<String, dynamic>) {
          final snapshot = _ContactsSnapshot.fromJson(payload);
          _setViewState(() {
            _applySnapshot(snapshot);
            _isLoading = false;
          });
        }
      }
    }
    await _loadContacts(showLoading: _isLoading);
  }

  Future<void> _loadCollapsedSections() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _setViewState(() {
      for (final section in _sectionCollapsed.keys) {
        _sectionCollapsed[section] =
            prefs.getBool('${_ContactsPageState._sectionPrefPrefix}$section') ??
                false;
      }
    });
  }

  bool _isSectionCollapsed(String section) =>
      _sectionCollapsed[section] ?? false;

  bool _isGroupBlockCollapsed(String key) => _groupCollapsed[key] ?? false;

  Future<void> _loadContacts({bool showLoading = true}) async {
    if (mounted && showLoading && _contacts.isEmpty) {
      _setViewState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (mounted && showLoading) {
      _setViewState(() {
        _errorMessage = null;
      });
    }

    try {
      final privateChats = _directory.privateChats;
      Object? privateError;
      // 私聊跟着实时事件更新：静默刷新（例如桌面切换会话时新建的中间栏）不必再翻一遍全部私聊。
      final privateLoad = (showLoading || !privateChats.hasLoaded
              ? privateChats.load()
              : Future<void>.value())
          .then<void>(
        (_) {},
        onError: (Object error) => privateError = error,
      );
      final snapshot = await _ContactsPageState._fetchSnapshot(
        contactService: _contactService,
        chatService: _chatService,
      );
      await privateLoad;
      // 私聊是联系人的一半：一次都没拉到时按加载失败处理，拉到过就先用旧的。
      final failure = privateError;
      if (failure != null && !privateChats.hasLoaded) throw failure;
      if (_canUseSnapshot) {
        _ContactsPageState._cachedSnapshot = snapshot;
        _ContactsPageState._cachedSnapshotAt = DateTime.now();
        final userId = AuthService().currentUser?.id;
        if (userId != null) {
          unawaited(PersistentDataCache.write(
            userId: userId,
            namespace: 'contacts-directory',
            payload: snapshot.toJson(),
          ));
        }
      }
      if (!mounted) return;
      _setViewState(() {
        _applySnapshot(snapshot);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!showLoading &&
          (_contacts.isNotEmpty || _directory.privateChats.rooms.isNotEmpty)) {
        return;
      }
      _setViewState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String? get _currentUserId =>
      widget.currentUserId ??
      _directory.currentUserId ??
      AuthService().currentUser?.id;

  /// 好友 ∪ 所有私聊的对方（非好友也在内），每人一行，带上和他的私聊。
  List<_ContactEntry> get _contactEntries {
    final currentUserId = _currentUserId;
    final chatsByPeer = <String, Chat>{};
    final peers = <String, User>{};
    // 私聊按最后消息倒序：同一个人万一有多个私聊房间，取最近的那个。
    for (final chat in _directory.privateChats.rooms) {
      final peer = chat.peerFor(currentUserId);
      if (peer == null || peer.id.isEmpty) continue;
      chatsByPeer.putIfAbsent(peer.id, () => chat);
      peers.putIfAbsent(peer.id, () => peer);
    }
    final friendIds = <String>{};
    final entries = <_ContactEntry>[];
    for (final friend in _contacts) {
      if (!friendIds.add(friend.id)) continue;
      entries.add(_ContactEntry(
        user: _withLivePresence(friend, peers[friend.id]),
        isFriend: true,
        chat: chatsByPeer[friend.id],
      ));
    }
    for (final peer in peers.values) {
      if (friendIds.contains(peer.id)) continue;
      entries.add(_ContactEntry(
        user: _withLivePresence(peer, peer),
        isFriend: false,
        chat: chatsByPeer[peer.id],
      ));
    }
    return entries;
  }

  /// 好友接口里的在线状态是拉取时的快照；实时推送过的以推送为准。
  User _withLivePresence(User user, User? chatPeer) {
    final status = _directory.presenceOf(user.id) ?? chatPeer?.onlineStatus;
    if (status == null || status == user.onlineStatus) return user;
    return user.copyWith(onlineStatus: status);
  }

  List<_ContactEntry> get _filteredContactEntries {
    final entries = _contactEntries;
    if (_searchQuery.isEmpty) {
      return entries;
    }
    final keyword = _searchQuery.toLowerCase();
    return entries.where((entry) {
      // 服务器不再下发别人的邮箱和手机号，只按名字匹配。
      return entry.user.displayName.toLowerCase().contains(keyword) ||
          entry.user.username.toLowerCase().contains(keyword);
    }).toList();
  }

  /// 同一个分组里：置顶在前，然后按最后一条消息时间倒序，没聊过的按名字排。
  int _compareContactEntries(_ContactEntry a, _ContactEntry b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    final aTime = a.lastMessageAt;
    final bTime = b.lastMessageAt;
    if (aTime != null && bTime != null) {
      final byTime = bTime.compareTo(aTime);
      if (byTime != 0) return byTime;
    } else if (aTime != null) {
      return -1;
    } else if (bTime != null) {
      return 1;
    }
    return _displayName(a.user)
        .toLowerCase()
        .compareTo(_displayName(b.user).toLowerCase());
  }

  List<Chat> get _filteredGroupChats => _filterChats(_groupChats);

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
}
