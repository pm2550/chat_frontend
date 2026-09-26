import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'auth_service.dart';
import 'chat_data_service.dart';
import 'websocket_service.dart';

/// 目录可能在别的页面 build 期间变化（例如那一页在 initState 里用缓存填列表），
/// 这时监听它的页面不能立即 setState，要等这一帧建完。
void runOutsideBuild(VoidCallback action) {
  final binding = SchedulerBinding.instance;
  if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    binding.addPostFrameCallback((_) => action());
  } else {
    action();
  }
}

/// 会话分两处展示：消息页只列群聊和频道，私聊全部作为联系人出现在联系人页。
enum ChatRoomScope { conversations, privateChats }

/// 一条新消息已经落到某个会话上（列表已更新），页面据此弹提醒、记 @ 我。
class ChatRoomMessageActivity {
  const ChatRoomMessageActivity({
    required this.scope,
    required this.chat,
    required this.previous,
    required this.message,
    required this.isIncoming,
  });

  final ChatRoomScope scope;

  /// 更新后的会话。
  final Chat chat;

  /// 收到这条消息之前的会话（免打扰、屏蔽等状态以它为准）。
  final Chat previous;
  final Message message;

  /// 别人发来的（不是自己在另一台设备上发的）。
  final bool isIncoming;
}

/// 一份会话列表（消息页的群聊 / 频道，或全部私聊）及其实时更新。
///
/// 实时事件由 [ChatRoomDirectory] 统一分发到认识该会话的那一份列表；
/// 两份列表的处理逻辑相同，只在"移出 / 屏蔽"上不同：消息页把它们拿掉，
/// 联系人里的私聊只打上标记（联系人不会因为移出列表而消失）。
class ChatRoomListController extends ChangeNotifier {
  ChatRoomListController._(this.scope, this._directory);

  final ChatRoomScope scope;
  final ChatRoomDirectory _directory;
  List<Chat> _rooms = <Chat>[];
  bool _hasLoaded = false;
  Future<void>? _running;
  Future<void>? _queued;
  bool _queuedForce = false;

  /// 按最后一条消息时间倒序。
  List<Chat> get rooms => UnmodifiableListView(_rooms);

  /// 已经从服务器成功拉过一次。
  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _running != null;

  /// 未读合计。屏蔽的会话服务器不再计未读，这里也不算。
  int get totalUnread => _rooms.fold<int>(
        0,
        (sum, chat) => chat.isBlocked ? sum : sum + chat.unreadCount,
      );

  bool contains(String roomId) => _indexOf(roomId) != -1;

  Chat? roomById(String roomId) {
    final index = _indexOf(roomId);
    return index == -1 ? null : _rooms[index];
  }

  /// 这份列表收不收这个会话：消息页不收私聊，联系人只收私聊。
  bool accepts(Chat chat) => scope == ChatRoomScope.privateChats
      ? chat.type == ChatType.private
      : chat.type != ChatType.private;

  /// 从服务器重新拉取。正在拉的时候再次请求，会在这一轮结束后补拉一轮
  /// （正在进行的那一轮可能早于触发刷新的变化），多次请求合并成一轮。
  Future<void> load({bool forceRefresh = false}) {
    final running = _running;
    if (running == null) {
      final next = _fetch(forceRefresh);
      _running = next;
      return next.whenComplete(() {
        if (identical(_running, next)) _running = null;
      });
    }
    _queuedForce = _queuedForce || forceRefresh;
    return _queued ??= running.then<void>((_) {}, onError: (_) {}).then((_) {
      final force = _queuedForce;
      _queued = null;
      _queuedForce = false;
      return load(forceRefresh: force);
    });
  }

  /// 还没拉过就拉一次；失败只留到下次再试，不抛给调用方。
  Future<void> ensureLoaded() async {
    if (_hasLoaded) return;
    try {
      await (_running ?? load());
    } catch (_) {
      // 列表拿不到时页面各自显示错误状态；这里只是后台预热。
    }
  }

  /// 冷启动时先用上次存在本地的列表占位（只在还没有任何数据时）。
  Future<void> restorePersisted() async {
    if (_hasLoaded || _rooms.isNotEmpty) return;
    final service = _directory.chatService;
    final List<Chat>? persisted;
    try {
      persisted = scope == ChatRoomScope.conversations
          ? await service.loadPersistedChatRooms(excludeType: ChatType.private)
          : await service.loadPersistedChatRooms(
              size: 100,
              includeHidden: true,
              includeBlocked: true,
              type: ChatType.private,
            );
    } catch (_) {
      return; // 本地缓存坏了就等网络结果。
    }
    if (persisted == null || persisted.isEmpty) return;
    if (_hasLoaded || _rooms.isNotEmpty) return;
    _setRooms(persisted);
  }

  Future<void> _reloadQuietly({bool forceRefresh = true}) async {
    try {
      await load(forceRefresh: forceRefresh);
    } catch (_) {
      // 实时事件触发的刷新失败时保留现有列表，下次事件或回到前台再刷新。
    }
  }

  Future<void> _fetch(bool forceRefresh) async {
    final service = _directory.chatService;
    final rooms = scope == ChatRoomScope.conversations
        ? await service.getChatRooms(
            excludeType: ChatType.private,
            forceRefresh: forceRefresh,
          )
        : await service.getAllChatRooms(
            type: ChatType.private,
            includeHidden: true,
            includeBlocked: true,
            forceRefresh: forceRefresh,
          );
    _hasLoaded = true;
    _setRooms(rooms);
  }

  /// 用缓存（内存快照 / 本地持久化）先把列表填上，不算真正加载过。
  void replaceAll(Iterable<Chat> rooms) => _setRooms(rooms);

  void _setRooms(Iterable<Chat> rooms) {
    _rooms = rooms.where(accepts).toList();
    _sort();
    notifyListeners();
  }

  /// 本地新建 / 找回的会话（例如刚发起的私聊），先放进列表，服务器事件稍后会校正。
  void upsert(Chat chat) {
    if (!accepts(chat)) return;
    final index = _indexOf(chat.id);
    if (index == -1) {
      _rooms.add(chat);
    } else {
      _rooms[index] = chat;
    }
    _patchStaticCache(chat);
    _sort();
    notifyListeners();
  }

  void updateRoom(String roomId, Chat Function(Chat chat) change) {
    final index = _indexOf(roomId);
    if (index == -1) return;
    _rooms[index] = change(_rooms[index]);
    _patchStaticCache(_rooms[index]);
    _sort();
    notifyListeners();
  }

  void removeRoom(String roomId) {
    if (scope == ChatRoomScope.conversations) {
      ChatDataService.removeCachedChatRoom(roomId);
    }
    final index = _indexOf(roomId);
    if (index == -1) return;
    _rooms.removeAt(index);
    notifyListeners();
  }

  int _indexOf(String roomId) => _rooms.indexWhere((chat) => chat.id == roomId);

  void _sort() {
    _rooms.sort((a, b) {
      final aTime = a.lastMessage?.timestamp ?? a.updatedAt ?? a.createdAt;
      final bTime = b.lastMessage?.timestamp ?? b.updatedAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
  }

  void _patchStaticCache(Chat chat) {
    // 内存快照只存消息页那一份。
    if (scope == ChatRoomScope.conversations) {
      ChatDataService.patchCachedChatRoom(chat);
    }
  }

  void _applyMessage(Message message) {
    final index = _indexOf(message.chatRoomId);
    if (index == -1) return;
    final currentUserId = _directory.currentUserId;
    final isIncoming =
        currentUserId != null && !message.isFromCurrentUser(currentUserId);
    final original = _rooms[index];
    final currentLastMessage = original.lastMessage;
    final replacesLastMessage = currentLastMessage?.id == message.id;
    final shouldPromoteToLast = replacesLastMessage ||
        currentLastMessage == null ||
        !message.timestamp.isBefore(currentLastMessage.timestamp);
    final countsAsUnread = isIncoming &&
        !message.isRemoved &&
        !replacesLastMessage &&
        !original.isBlocked;
    final updated = original.copyWith(
      lastMessage: shouldPromoteToLast ? message : currentLastMessage,
      unreadCount:
          countsAsUnread ? original.unreadCount + 1 : original.unreadCount,
      updatedAt: shouldPromoteToLast ? message.timestamp : original.updatedAt,
      // 新消息会让服务器把"已移出"的会话放回来（屏蔽的除外）。
      clearHiddenAt: countsAsUnread,
    );
    _rooms[index] = updated;
    _patchStaticCache(updated);
    _sort();
    notifyListeners();
    _directory._emitActivity(ChatRoomMessageActivity(
      scope: scope,
      chat: updated,
      previous: original,
      message: message,
      isIncoming: isIncoming,
    ));
  }

  /// 编辑 / 撤回 / 删除 / 生成进度：只刷新会话预览（如果改的正是最后一条），
  /// 不加未读、不弹提醒。
  void _applyMessageUpdate(Message message) {
    final index = _indexOf(message.chatRoomId);
    if (index == -1) return;
    final original = _rooms[index];
    if (original.lastMessage?.id != message.id) return;
    _rooms[index] = original.copyWith(lastMessage: message);
    _patchStaticCache(_rooms[index]);
    notifyListeners();
  }

  /// 自己在另一台设备上置顶 / 免打扰 / 隐藏 / 屏蔽 / 清空 / 恢复了会话。
  void _applyDisplayState(String roomId, Map<dynamic, dynamic> state) {
    final hidden = state['isHidden'] == true || state['hiddenAt'] != null;
    final blocked = state['isBlocked'] == true || state['blocked'] == true;
    final index = _indexOf(roomId);
    if (scope == ChatRoomScope.conversations && (hidden || blocked)) {
      removeRoom(roomId);
      return;
    }
    final clearedBefore = state['clearedBeforeMessageId']?.toString();
    if (index == -1 || clearedBefore != _rooms[index].clearedBeforeMessageId) {
      // 恢复显示或清空了记录：最后一条消息要从服务器重新取。
      unawaited(_reloadQuietly());
      return;
    }
    final unread = state['unreadCount'];
    final original = _rooms[index];
    _rooms[index] = original.copyWith(
      isPinned: state['pinned'] == true,
      isMuted: state['muted'] == true,
      unreadCount: unread is num ? unread.toInt() : null,
      isBlocked: blocked,
      hiddenAt: hidden ? original.hiddenAt ?? DateTime.now() : null,
      clearHiddenAt: !hidden,
    );
    _patchStaticCache(_rooms[index]);
    _sort();
    notifyListeners();
  }

  /// 自己在另一台设备上读完了会话：这里的未读数也要清掉。
  void _applyOwnReadReceipt(Map<String, dynamic> event) {
    final roomId = event['chatRoomId']?.toString();
    final readerId = event['userId']?.toString();
    if (roomId == null ||
        readerId == null ||
        readerId != _directory.currentUserId) {
      return;
    }
    final index = _indexOf(roomId);
    if (index == -1) return;
    final unread = event['unreadCount'];
    final nextUnread = unread is num
        ? unread.toInt()
        : (event['lastReadMessageId'] != null ? 0 : _rooms[index].unreadCount);
    if (nextUnread == _rooms[index].unreadCount) return;
    _rooms[index] = _rooms[index].copyWith(unreadCount: nextUnread);
    _patchStaticCache(_rooms[index]);
    notifyListeners();
  }

  void _applyRoomUpdate(String roomId, Map<String, dynamic> chatRoomJson) {
    final index = _indexOf(roomId);
    if (index == -1) return;
    _rooms[index] = _rooms[index].withRoomUpdate(chatRoomJson);
    _patchStaticCache(_rooms[index]);
    notifyListeners();
  }

  bool _applyPresence(String userId, OnlineStatus status) {
    var changed = false;
    for (var i = 0; i < _rooms.length; i++) {
      final chat = _rooms[i];
      if (!chat.participants.any((user) => user.id == userId)) continue;
      changed = true;
      _rooms[i] = chat.copyWith(
        participants: [
          for (final user in chat.participants)
            user.id == userId ? user.copyWith(onlineStatus: status) : user,
        ],
      );
    }
    return changed;
  }

  void _notifyChanged() => notifyListeners();
}

/// 当前用户的全部会话：消息页那一份（群聊 + 频道）和联系人那一份（全部私聊），
/// 以及它们共用的一路实时事件。未读角标、系统角标都从这里算。
class ChatRoomDirectory {
  ChatRoomDirectory({
    required this.chatService,
    required this.realtimeService,
    String? Function()? currentUserId,
  }) : _currentUserId =
            currentUserId ?? (() => AuthService().currentUser?.id) {
    conversations =
        ChatRoomListController._(ChatRoomScope.conversations, this);
    privateChats = ChatRoomListController._(ChatRoomScope.privateChats, this);
    _subscriptions.addAll([
      realtimeService.onMessage.listen(_handleMessage),
      realtimeService.onMessageUpdated.listen(_handleMessageUpdate),
      realtimeService.onStatusChange.listen(_handleStatusChange),
    ]);
  }

  final ChatDataService chatService;
  final ChatRealtimeService realtimeService;
  final String? Function() _currentUserId;
  late final ChatRoomListController conversations;
  late final ChatRoomListController privateChats;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  // 同步分发：活动总是在处理实时事件时产生（不在 build 里），页面要在同一轮里弹出提醒。
  final StreamController<ChatRoomMessageActivity> _activity =
      StreamController<ChatRoomMessageActivity>.broadcast(sync: true);
  final Map<String, OnlineStatus> _presence = {};

  static ChatRoomDirectory? _shared;
  static String? _sharedUserId;
  static final Expando<ChatRoomDirectory> _byService =
      Expando<ChatRoomDirectory>('ChatRoomDirectory');

  /// 当前登录用户的那一份；换了账号就重新建。
  static ChatRoomDirectory get shared {
    final userId = AuthService().currentUser?.id;
    final existing = _shared;
    if (existing != null && _sharedUserId == userId) return existing;
    existing?._detach();
    _sharedUserId = userId;
    return _shared = ChatRoomDirectory(
      chatService: ChatDataService(),
      realtimeService: WebSocketService(),
    );
  }

  /// 页面取目录：没有注入服务时用 [shared]；注入了服务（测试、桌面聊天页里的
  /// 中间栏）时，同一个 [chatService] 的页面共用一份，彼此的变化互相可见。
  static ChatRoomDirectory of({
    ChatDataService? chatService,
    ChatRealtimeService? realtimeService,
    String? currentUserId,
  }) {
    if (chatService == null) return shared;
    return _byService[chatService] ??= ChatRoomDirectory(
      chatService: chatService,
      realtimeService: realtimeService ?? WebSocketService(),
      currentUserId: currentUserId == null ? null : () => currentUserId,
    );
  }

  @visibleForTesting
  static void resetSharedForTesting() {
    _shared?._detach();
    _shared = null;
    _sharedUserId = null;
  }

  String? get currentUserId => _currentUserId();

  Stream<ChatRoomMessageActivity> get messageActivity => _activity.stream;

  /// 联系人 tab 的角标：私聊未读。
  int get privateUnread => privateChats.totalUnread;

  /// 消息 tab 的角标：群聊 + 频道未读。
  int get conversationUnread => conversations.totalUnread;

  /// 系统 / 桌面 / 图标角标：两边都算。
  int get totalUnread => conversationUnread + privateUnread;

  /// 任一份列表变化（含未读数）都会通知。
  Listenable get changes => Listenable.merge([conversations, privateChats]);

  /// 最近一次实时推送的在线状态（没有私聊的好友也能跟着变）。
  OnlineStatus? presenceOf(String userId) => _presence[userId];

  void _detach() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _emitActivity(ChatRoomMessageActivity activity) {
    if (!_activity.isClosed) _activity.add(activity);
  }

  ChatRoomListController? _listFor(String roomId) {
    if (privateChats.contains(roomId)) return privateChats;
    if (conversations.contains(roomId)) return conversations;
    return null;
  }

  void _handleMessage(Message message) {
    if (message.chatRoomId.isEmpty) return;
    final list = _listFor(message.chatRoomId);
    if (list != null) {
      list._applyMessage(message);
      return;
    }
    // 不认识的会话：新建 / 被恢复的群、排在第一页之外的群，或者私聊还没拉到。
    unawaited(conversations._reloadQuietly());
    if (!privateChats.hasLoaded) unawaited(privateChats.ensureLoaded());
  }

  void _handleMessageUpdate(Message message) {
    if (message.chatRoomId.isEmpty) return;
    _listFor(message.chatRoomId)?._applyMessageUpdate(message);
  }

  void _handleStatusChange(Map<String, dynamic> event) {
    final roomId = event['chatRoomId']?.toString();
    switch (event['type']) {
      case 'room_display_state_changed':
        final state = event['state'];
        if (roomId == null || state is! Map) {
          unawaited(conversations._reloadQuietly());
          unawaited(privateChats._reloadQuietly());
          return;
        }
        (privateChats.contains(roomId) ? privateChats : conversations)
            ._applyDisplayState(roomId, state);
        return;
      case 'read_receipt':
        if (roomId != null) _listFor(roomId)?._applyOwnReadReceipt(event);
        return;
      case 'room_membership_added':
        // 事件里没有会话类型：两份都刷新（新私聊也走这里）。
        unawaited(conversations._reloadQuietly());
        unawaited(privateChats._reloadQuietly());
        return;
      case 'room_membership_removed':
        if (roomId != null) {
          conversations.removeRoom(roomId);
          privateChats.removeRoom(roomId);
        }
        return;
      case 'room_updated':
        final chatRoomJson = event['chatRoom'];
        if (roomId == null || chatRoomJson is! Map) return;
        _listFor(roomId)
            ?._applyRoomUpdate(roomId, Map<String, dynamic>.from(chatRoomJson));
        return;
    }

    final userId = event['userId']?.toString();
    final statusValue = event['onlineStatus'] ?? event['online_status'];
    if (userId == null || statusValue == null) return;
    final status = OnlineStatus.values.firstWhere(
      (value) =>
          value.name.toUpperCase() == statusValue.toString().toUpperCase(),
      orElse: () => OnlineStatus.offline,
    );
    _presence[userId] = status;
    if (conversations._applyPresence(userId, status)) {
      conversations._notifyChanged();
    }
    // 联系人里没有私聊的好友也显示在线状态，所以总要通知一次。
    privateChats._applyPresence(userId, status);
    privateChats._notifyChanged();
  }
}
