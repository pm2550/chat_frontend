part of '../ai_hub_page.dart';

extension _AiHubData1Parts on _AiHubPageState {
  void _restoreSnapshotIfFresh() {
    if (!_canUseSnapshot) return;
    final snapshot = _AiHubPageState._cachedSnapshot;
    final snapshotAt = _AiHubPageState._cachedSnapshotAt;
    if (snapshot == null ||
        snapshotAt == null ||
        DateTime.now().difference(snapshotAt) >= _AiHubPageState._snapshotTtl) {
      return;
    }
    _bots = List<BotConfig>.from(snapshot.bots);
    _rooms = List<Chat>.from(snapshot.rooms);
    Chat? restoredImageRoom;
    if (snapshot.selectedImageRoomId != null) {
      for (final room in _rooms) {
        if (room.id == snapshot.selectedImageRoomId) {
          restoredImageRoom = room;
          break;
        }
      }
    }
    _selectedImageRoom = restoredImageRoom ?? _resolveSelectedImageRoom(_rooms);
    _loading = false;
  }

  Future<void> _bootstrapData() async {
    if (_canUseSnapshot && _loading) {
      final results = await Future.wait<dynamic>([
        _botService.loadPersistedMyBots(),
        _chatDataService.loadPersistedChatRooms(includeDetails: false),
      ]);
      if (mounted) {
        final cachedBots = results[0] as List<BotConfig>?;
        final cachedRooms = results[1] as List<Chat>?;
        if ((cachedBots?.isNotEmpty ?? false) ||
            (cachedRooms?.isNotEmpty ?? false)) {
          _setViewState(() {
            _bots = cachedBots ?? const [];
            _rooms = cachedRooms ?? const [];
            _selectedImageRoom = _resolveSelectedImageRoom(_rooms);
            _loading = false;
          });
        }
      }
    }
    await _load(showLoading: _loading);
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && _bots.isEmpty && _rooms.isEmpty) {
      _setViewState(() {
        _loading = true;
        _error = null;
      });
    } else if (showLoading) {
      _setViewState(() {
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _botService.getMyBots(),
        _chatDataService.getChatRooms(includeDetails: false),
      ]);
      if (!mounted) return;
      final bots = results[0] as List<BotConfig>;
      final rooms = results[1] as List<Chat>;
      final selectedImageRoom = _resolveSelectedImageRoom(rooms);
      if (_canUseSnapshot) {
        _AiHubPageState._cachedSnapshot = _AiHubSnapshot(
          bots: List<BotConfig>.from(bots),
          rooms: List<Chat>.from(rooms),
          selectedImageRoomId: selectedImageRoom?.id,
        );
        _AiHubPageState._cachedSnapshotAt = DateTime.now();
      }
      _setViewState(() {
        _bots = bots;
        _rooms = rooms;
        _selectedImageRoom = selectedImageRoom;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (!showLoading && (_bots.isNotEmpty || _rooms.isNotEmpty)) {
        return;
      }
      _setViewState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }
}
