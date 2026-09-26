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
    _privateChats = List<Chat>.from(snapshot.privateChats);
    _contactGroups = List<ContactGroup>.from(snapshot.contactGroups);
    _groupAssignmentsByTarget = Map<String, ContactGroupAssignment>.from(
        snapshot.groupAssignmentsByTarget);
    _groupCollapsed = Map<String, bool>.from(snapshot.groupCollapsed);
    _isLoading = false;
  }

  Future<void> _bootstrapContacts() async {
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
      final snapshot = await _ContactsPageState._fetchSnapshot(
        contactService: _contactService,
        chatService: _chatService,
      );
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
      if (!showLoading && _contacts.isNotEmpty) {
        return;
      }
      _setViewState(() {
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
      // 服务器不再下发别人的邮箱和手机号，只按名字匹配。
      return contact.displayName.toLowerCase().contains(keyword) ||
          contact.username.toLowerCase().contains(keyword);
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
}
