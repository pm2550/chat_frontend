import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../constants/api_constants.dart';
import '../models/agent_task.dart';
import '../models/chat.dart';
import '../models/chat_room_member.dart';
import '../models/message.dart';
import '../models/poll.dart';
import '../models/read_receipt.dart';
import '../models/sticker.dart';
import '../models/user.dart';
import 'auth_service.dart';
import 'chat_upload.dart';
import 'encryption_service.dart';
import 'image_upload/image_upload_preparer.dart';
import 'persistent_data_cache.dart';
import 'request_coordinator.dart';

typedef AuthenticatedRequest = Future<dynamic> Function(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
});

typedef AuthenticatedMultipartRequest = Future<dynamic> Function(
  String url, {
  required Map<String, String> fields,
  required PickedChatFile file,
});

typedef AuthenticatedMultipartFilesRequest = Future<dynamic> Function(
  String url, {
  required Map<String, String> fields,
  required Map<String, List<PickedChatFile>> files,
});

class PickedChatFile {
  const PickedChatFile({
    required this.name,
    required this.size,
    this.path,
    this.mimeType,
    this.bytes,
    this.thumbnail,
  });

  final String name;
  final int size;
  final String? path;
  final String? mimeType;
  final List<int>? bytes;

  /// 图片的小预览图（长边约 400px），发图前压缩时顺带做好。只有端到端加密的私聊才用得上：
  /// 服务器看不到图，由发送端加密后一起上传；明文会话的预览图由服务器生成。
  final Future<Uint8List?> Function()? thumbnail;
}

class DownloadedChatFile {
  const DownloadedChatFile({
    required this.name,
    required this.bytes,
    this.mimeType,
  });

  final String name;
  final List<int> bytes;
  final String? mimeType;
}

class MessagePage {
  const MessagePage({
    required this.messages,
    required this.currentPage,
    required this.totalPages,
    required this.totalElements,
    required this.hasNext,
    required this.hasPrevious,
  });

  final List<Message> messages;
  final int currentPage;
  final int totalPages;
  final int totalElements;
  final bool hasNext;
  final bool hasPrevious;
}

class ChatDataException implements Exception {
  final String message;

  const ChatDataException(this.message);

  @override
  String toString() => message;
}

/// 给一张图做小预览图（做不了返回 null）。
typedef ImageThumbnailer = Future<Uint8List?> Function(Uint8List imageBytes);

class ChatDataService {
  ChatDataService({
    AuthService? authService,
    AuthenticatedRequest? authenticatedRequest,
    AuthenticatedMultipartRequest? multipartRequest,
    AuthenticatedMultipartFilesRequest? multipartFilesRequest,
    MultipartUploadTransport? uploadTransport,
    EncryptionService? encryptionService,
    ImageThumbnailer? imageThumbnailer,
  })  : _authService = authService ?? AuthService(),
        _authenticatedRequest = authenticatedRequest,
        _multipartRequest = multipartRequest,
        _multipartFilesRequest = multipartFilesRequest,
        _uploadTransport = uploadTransport ?? dioMultipartUpload,
        _encryptionService = encryptionService,
        _imageThumbnailer = imageThumbnailer;

  final AuthService _authService;
  final EncryptionService? _encryptionService;
  EncryptionService get _e2ee => _encryptionService ?? EncryptionService();
  final AuthenticatedRequest? _authenticatedRequest;
  final AuthenticatedMultipartRequest? _multipartRequest;
  final AuthenticatedMultipartFilesRequest? _multipartFilesRequest;
  final MultipartUploadTransport _uploadTransport;
  final ImageThumbnailer? _imageThumbnailer;

  static const Duration _chatRoomsCacheTtl = Duration(seconds: 30);
  static List<Chat>? _cachedChatRooms;
  static DateTime? _cachedChatRoomsAt;
  static int? _cachedChatRoomsPage;
  static int? _cachedChatRoomsSize;
  static final Map<String, Message> _cachedLastMessagesByRoomId =
      <String, Message>{};

  static void clearChatRoomsCache() {
    _cachedChatRooms = null;
    _cachedChatRoomsAt = null;
    _cachedChatRoomsPage = null;
    _cachedChatRoomsSize = null;
    _cachedLastMessagesByRoomId.clear();
  }

  static void clearChatRoomsCacheForTesting() {
    clearChatRoomsCache();
    RequestCoordinator.clearForTesting();
  }

  static List<Chat>? cachedChatRoomsSnapshot({
    int page = 0,
    int size = 30,
  }) {
    final cached = _cachedChatRooms;
    final cachedAt = _cachedChatRoomsAt;
    if (cached == null ||
        cachedAt == null ||
        _cachedChatRoomsPage != page ||
        _cachedChatRoomsSize != size ||
        DateTime.now().difference(cachedAt) >= _chatRoomsCacheTtl) {
      return null;
    }
    return List<Chat>.from(cached);
  }

  static void patchCachedChatRoom(Chat chat) {
    final cached = _cachedChatRooms;
    if (cached == null) return;
    final index = cached.indexWhere((room) => room.id == chat.id);
    if (index == -1) return;
    final patched = List<Chat>.from(cached);
    patched[index] = chat;
    _rememberLastMessages(patched);
    _cachedChatRooms = _sortChatsInPlace(patched);
    _cachedChatRoomsAt = DateTime.now();
  }

  /// 会话被移出列表（被踢、退出、解散、隐藏）：同步去掉内存缓存里的这一项，
  /// 免得 30 秒缓存期内切回列表又看到它。
  static void removeCachedChatRoom(String chatRoomId) {
    final cached = _cachedChatRooms;
    if (cached == null) return;
    _cachedChatRooms =
        cached.where((room) => room.id != chatRoomId).toList();
  }

  Future<List<Chat>> getChatRooms({
    int page = 0,
    int size = 30,
    bool includeDetails = true,
    int detailLimit = 8,
    bool includeHidden = false,
    bool includeBlocked = false,
    ChatType? type,
    bool forceRefresh = false,
  }) async {
    final useSharedCache = _canUseSharedChatRoomsCache(
      includeDetails: includeDetails,
      page: page,
      size: size,
      includeHidden: includeHidden,
      includeBlocked: includeBlocked,
      type: type,
    );
    if (useSharedCache && !forceRefresh) {
      final cached = cachedChatRoomsSnapshot(page: page, size: size);
      if (cached != null) {
        return cached;
      }
    }

    Future<List<Chat>> load() => _loadChatRooms(
          page: page,
          size: size,
          includeDetails: includeDetails,
          includeHidden: includeHidden,
          includeBlocked: includeBlocked,
          type: type,
          useSharedCache: useSharedCache,
        );
    if (forceRefresh ||
        _authenticatedRequest != null ||
        _multipartRequest != null ||
        _multipartFilesRequest != null) {
      return load();
    }

    final userKey = _authService.currentUser?.id ?? 'anonymous';
    final requestKey = <Object?>[
      'chat-rooms',
      userKey,
      page,
      size,
      includeDetails,
      includeHidden,
      includeBlocked,
      type?.name,
    ].join(':');
    return RequestCoordinator.run<List<Chat>>(requestKey, load);
  }

  Future<List<Chat>> _loadChatRooms({
    required int page,
    required int size,
    required bool includeDetails,
    required bool includeHidden,
    required bool includeBlocked,
    required ChatType? type,
    required bool useSharedCache,
  }) async {
    final endpoint = includeDetails
        ? ApiConstants.chatRoomSummaries
        : ApiConstants.chatRooms;
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
        'sortBy': 'updatedAt',
        'sortDir': 'desc',
        if (includeHidden) 'includeHidden': 'true',
        if (includeBlocked) 'includeBlocked': 'true',
        if (type != null) 'roomType': type.name.toUpperCase(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final rooms =
        _extractList(data, keys: const ['chatRooms', 'data', 'content'])
            .whereType<Map<String, dynamic>>()
            .map(Chat.fromJson)
            .map(_mergeCachedLastMessage)
            .toList();

    final sortedRooms = _sortChats(rooms);
    _rememberLastMessages(sortedRooms);
    if (useSharedCache) {
      _cacheChatRooms(sortedRooms, page: page, size: size);
    }
    final userId = _authService.currentUser?.id;
    if (_authenticatedRequest == null && userId != null) {
      unawaited(PersistentDataCache.write(
        userId: userId,
        namespace: _roomCacheNamespace(
          page: page,
          size: size,
          includeDetails: includeDetails,
          includeHidden: includeHidden,
          includeBlocked: includeBlocked,
          type: type,
        ),
        payload: {
          'rooms': sortedRooms.map((room) => room.toJson()).toList(),
        },
      ));
    }
    return sortedRooms;
  }

  Future<List<Chat>?> loadPersistedChatRooms({
    int page = 0,
    int size = 30,
    bool includeDetails = true,
    bool includeHidden = false,
    bool includeBlocked = false,
    ChatType? type,
  }) async {
    final userId = _authService.currentUser?.id;
    if (_authenticatedRequest != null || userId == null) return null;
    final record = await PersistentDataCache.read(
      userId: userId,
      namespace: _roomCacheNamespace(
        page: page,
        size: size,
        includeDetails: includeDetails,
        includeHidden: includeHidden,
        includeBlocked: includeBlocked,
        type: type,
      ),
    );
    final rawRooms = record?['payload']?['rooms'];
    if (rawRooms is! List<dynamic>) return null;
    final rooms = rawRooms
        .whereType<Map<String, dynamic>>()
        .map(Chat.fromJson)
        .toList(growable: false);
    if (includeDetails &&
        page == 0 &&
        !includeHidden &&
        !includeBlocked &&
        type == null) {
      _cacheChatRooms(rooms, page: page, size: size);
    }
    return _sortChats(rooms);
  }

  static String _roomCacheNamespace({
    required int page,
    required int size,
    required bool includeDetails,
    required bool includeHidden,
    required bool includeBlocked,
    required ChatType? type,
  }) =>
      'rooms:$page:$size:$includeDetails:$includeHidden:$includeBlocked:${type?.name ?? 'all'}';

  bool _canUseSharedChatRoomsCache({
    required bool includeDetails,
    required int page,
    required int size,
    required bool includeHidden,
    required bool includeBlocked,
    required ChatType? type,
  }) {
    return includeDetails &&
        page >= 0 &&
        size > 0 &&
        !includeHidden &&
        !includeBlocked &&
        type == null &&
        _authenticatedRequest == null &&
        _multipartRequest == null &&
        _multipartFilesRequest == null;
  }

  void _cacheChatRooms(
    List<Chat> rooms, {
    required int page,
    required int size,
  }) {
    _rememberLastMessages(rooms);
    _cachedChatRooms = List<Chat>.from(rooms);
    _cachedChatRoomsAt = DateTime.now();
    _cachedChatRoomsPage = page;
    _cachedChatRoomsSize = size;
  }

  static Chat _mergeCachedLastMessage(Chat chat) {
    final lastMessage = chat.lastMessage;
    if (lastMessage != null) {
      _cachedLastMessagesByRoomId[chat.id] = lastMessage;
      return chat;
    }

    final cachedLastMessage = _cachedLastMessagesByRoomId[chat.id] ??
        _lastMessageFromCachedRooms(chat.id);
    if (cachedLastMessage == null) {
      return chat;
    }
    return chat.copyWith(
      lastMessage: cachedLastMessage,
      updatedAt: _updatedAtWithLastMessage(chat, cachedLastMessage),
    );
  }

  static Message? _lastMessageFromCachedRooms(String chatRoomId) {
    final cached = _cachedChatRooms;
    if (cached == null) return null;
    for (final room in cached) {
      if (room.id == chatRoomId && room.lastMessage != null) {
        return room.lastMessage;
      }
    }
    return null;
  }

  static void _rememberLastMessages(List<Chat> rooms) {
    for (final room in rooms) {
      final lastMessage = room.lastMessage;
      if (lastMessage != null) {
        _cachedLastMessagesByRoomId[room.id] = lastMessage;
      }
    }
  }

  Future<Chat> getChatRoom(
    String chatRoomId, {
    bool includeDetails = true,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request('GET', ApiConstants.chatRoomDetail(roomId));
    final data = _decodeResponse(response);
    final chatRoomJson = data['chatRoom'] ?? data['data'];
    if (chatRoomJson is! Map<String, dynamic>) {
      throw const ChatDataException('聊天室详情响应中没有聊天室数据');
    }

    final chat = Chat.fromJson(chatRoomJson);
    return includeDetails ? _enrichChat(chat) : chat;
  }

  Future<Chat> updateChatRoom(
    String chatRoomId, {
    String? name,
    String? description,
    String? avatarUrl,
    String? announcement,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'PATCH',
      ApiConstants.chatRoomDetail(roomId),
      body: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (announcement != null) 'announcement': announcement,
      },
    );
    final data = _decodeResponse(response);
    final chatRoomJson = data['chatRoom'] ?? data['data'];
    if (chatRoomJson is! Map<String, dynamic>) {
      throw const ChatDataException('聊天室更新成功但响应中没有聊天室数据');
    }
    return Chat.fromJson(chatRoomJson);
  }

  Future<Chat> uploadRoomAvatar(
    String chatRoomId,
    PickedChatFile file,
  ) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _requestMultipart(
      ApiConstants.chatRoomAvatar(roomId),
      fields: const {},
      file: file,
    );
    final data = _decodeResponse(response);
    final chatRoomJson = data['chatRoom'] ?? data['data'];
    if (chatRoomJson is! Map<String, dynamic>) {
      throw const ChatDataException('群头像上传成功但响应中没有聊天室数据');
    }
    return Chat.fromJson(chatRoomJson);
  }

  Future<Chat> updateRoomBackgroundPreset(
    String chatRoomId,
    String preset,
  ) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'PUT',
      ApiConstants.chatRoomBackgroundPreset(roomId),
      body: {'preset': preset},
    );
    return _chatFromBackgroundResponse(response);
  }

  Future<Chat> uploadRoomBackground(
    String chatRoomId,
    PickedChatFile file,
  ) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _requestMultipart(
      ApiConstants.chatRoomBackgroundUpload(roomId),
      fields: const {},
      file: file,
    );
    return _chatFromBackgroundResponse(response);
  }

  Future<Chat> clearRoomBackground(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'DELETE',
      ApiConstants.chatRoomBackground(roomId),
    );
    return _chatFromBackgroundResponse(response);
  }

  Future<Chat> createGroupChat({
    required String name,
    String? description,
    List<String> memberIds = const [],
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.createGroupChat,
      body: {
        'name': name,
        if (description != null) 'description': description,
        'memberIds': memberIds.map(_parseRoomId).toList(),
      },
    );
    final data = _decodeResponse(response);
    final chatRoomJson = data['chatRoom'] ?? data['data'];
    if (chatRoomJson is! Map<String, dynamic>) {
      throw const ChatDataException('群聊创建成功但响应中没有聊天室数据');
    }
    return Chat.fromJson(chatRoomJson);
  }

  Future<List<ChatRoomMember>> getChatRoomMembers(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    final response =
        await _request('GET', ApiConstants.chatRoomMembers(roomId));
    final data = _decodeResponse(response);
    return _extractMembers(data);
  }

  Future<List<ChatRoomMember>> addChatRoomMember(
    String chatRoomId,
    String userId,
  ) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    final response = await _request(
      'POST',
      ApiConstants.addChatRoomMember(roomId, targetId),
    );
    final data = _decodeResponse(response);
    final members = _extractMembers(data);
    return members.isNotEmpty ? members : getChatRoomMembers(chatRoomId);
  }

  Future<void> leaveChatRoom(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    await _request('POST', ApiConstants.leaveChatRoom(roomId));
  }

  Future<Map<String, dynamic>> getNotificationSettings(
    String chatRoomId,
  ) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
        'GET', ApiConstants.chatRoomNotificationSettings(roomId));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> updateNotificationSettings(
    String chatRoomId, {
    bool? muted,
    bool? pinned,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'PUT',
      ApiConstants.chatRoomNotificationSettings(roomId),
      body: {
        if (muted != null) 'muted': muted,
        if (pinned != null) 'pinned': pinned,
      },
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> updateChatRoomDisplayState(
    String chatRoomId, {
    required String action,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'PUT',
      ApiConstants.chatRoomDisplayState(roomId),
      body: {'action': action},
    );
    clearChatRoomsCache();
    final data = _decodeResponse(response);
    final state = data['state'];
    return state is Map<String, dynamic> ? state : data;
  }

  Future<void> hideChatRoom(String chatRoomId) async {
    await updateChatRoomDisplayState(
      chatRoomId,
      action: 'REMOVE_FROM_LIST',
    );
  }

  Future<void> blockChatRoom(String chatRoomId) async {
    await updateChatRoomDisplayState(chatRoomId, action: 'BLOCK');
  }

  Future<void> unblockChatRoom(String chatRoomId) async {
    await updateChatRoomDisplayState(chatRoomId, action: 'UNBLOCK');
  }

  Future<void> restoreChatRoom(String chatRoomId) async {
    await updateChatRoomDisplayState(chatRoomId, action: 'RESTORE');
  }

  Future<void> kickChatRoomMember(String chatRoomId, String userId) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    await _request('POST', ApiConstants.kickChatRoomMember(roomId, targetId));
  }

  Future<void> toggleChatRoomAdmin(String chatRoomId, String userId) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    await _request('POST', ApiConstants.toggleChatRoomAdmin(roomId, targetId));
  }

  Future<void> toggleChatRoomMute(String chatRoomId, String userId) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    await _request('POST', ApiConstants.toggleChatRoomMute(roomId, targetId));
  }

  // F5: owner-only operations (server returns 403 for non-owners; UI also gates them).
  Future<void> transferChatRoomOwnership({
    required String chatRoomId,
    required String newOwnerId,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(newOwnerId);
    await _request(
      'POST',
      ApiConstants.transferChatRoomOwnership(roomId),
      body: {'newOwnerId': targetId},
    );
  }

  /// Sets a member's role. Only ADMIN | MODERATOR | MEMBER are accepted; OWNER is
  /// reachable only via [transferChatRoomOwnership].
  Future<void> setChatRoomMemberRole({
    required String chatRoomId,
    required String userId,
    required String role,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    await _request(
      'PUT',
      ApiConstants.setChatRoomMemberRole(roomId, targetId),
      body: {'role': role},
    );
  }

  /// Sets a bot's per-room moderation grant: NONE | MUTE | KICK.
  Future<void> setChatRoomBotModerationGrant({
    required String chatRoomId,
    required int botId,
    required String grant,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    await _request(
      'PUT',
      ApiConstants.setChatRoomBotModerationGrant(roomId, botId),
      body: {'grant': grant},
    );
  }

  Future<ChatRoomMember> updateChatRoomMemberProfile(
    String chatRoomId,
    String userId, {
    String? nickname,
    String? memberTitle,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final targetId = _parseRoomId(userId);
    final response = await _request(
      'PUT',
      ApiConstants.chatRoomMemberProfile(roomId, targetId),
      body: {
        if (nickname != null) 'nickname': nickname,
        if (memberTitle != null) 'memberTitle': memberTitle,
      },
    );
    final data = _decodeResponse(response);
    final memberJson = data['member'] ?? data['data'];
    if (memberJson is! Map<String, dynamic>) {
      throw const ChatDataException('群名片更新成功但响应中没有成员数据');
    }
    return ChatRoomMember.fromJson(memberJson);
  }

  Future<List<Message>> getMessages(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    final messagePage =
        await getMessagePage(chatRoomId, page: page, size: size);
    return messagePage.messages;
  }

  Future<MessagePage> getMessagePage(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    Future<MessagePage> load() => _loadMessagePage(
          chatRoomId,
          page: page,
          size: size,
        );
    if (_authenticatedRequest != null) return load();
    return RequestCoordinator.run<MessagePage>(
      'messages:${_authService.currentUser?.id ?? 'anonymous'}:$chatRoomId:$page:$size',
      load,
    );
  }

  Future<MessagePage> _loadMessagePage(
    String chatRoomId, {
    required int page,
    required int size,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.chatRoomMessages(roomId)).replace(
      queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, chatRoomId);
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return _messagePageFromData(data, messages);
  }

  Future<List<Message>> getMessageDelta(
    String chatRoomId, {
    required String afterMessageId,
    int size = 50,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.chatRoomMessages(roomId)).replace(
      queryParameters: {
        'afterMessageId': afterMessageId,
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, chatRoomId);
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  Future<List<Message>?> loadPersistedMessages(String chatRoomId) async {
    final userId = _authService.currentUser?.id;
    if (_authenticatedRequest != null || userId == null) return null;
    final record = await PersistentDataCache.read(
      userId: userId,
      namespace: 'messages:$chatRoomId',
    );
    final rawMessages = record?['payload']?['messages'];
    if (rawMessages is! List<dynamic>) return null;
    return rawMessages
        .whereType<Map<String, dynamic>>()
        .map((json) => Message.fromJson(
              json,
              fallbackChatRoomId: chatRoomId,
            ))
        .toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> persistMessages(
    String chatRoomId,
    List<Message> messages, {
    int limit = 50,
  }) async {
    final userId = _authService.currentUser?.id;
    if (_authenticatedRequest != null || userId == null) return;
    final sorted = List<Message>.from(messages)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final retained =
        sorted.length <= limit ? sorted : sorted.sublist(sorted.length - limit);
    await PersistentDataCache.write(
      userId: userId,
      namespace: 'messages:$chatRoomId',
      payload: {
        'messages': retained.map((message) => message.toJson()).toList(),
        'newestMessageId': retained.isEmpty ? null : retained.last.id,
      },
    );
  }

  Future<List<Message>> getRecentMessages(
    String chatRoomId, {
    int limit = 20,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.recentMessages(roomId)).replace(
      queryParameters: {'limit': limit.toString()},
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    return _extractMessages(data, chatRoomId);
  }

  /// 发文本。[encryptedContent] 是端到端加密的密文信封：有它时 content 只发占位文字，
  /// 明文不离开本机。
  Future<Message> sendTextMessage(
    String chatRoomId,
    String content, {
    bool isAnonymous = false,
    String? replyToId,
    String? encryptedContent,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final encrypted = encryptedContent != null && encryptedContent.isNotEmpty;
    final response = await _request(
      'POST',
      ApiConstants.sendMessage,
      body: {
        'chatRoomId': roomId,
        'content': encrypted ? kE2eeServerPlaceholder : content,
        if (encrypted) ...{
          'messageType': 'TEXT',
          'encryptedContent': encryptedContent,
          'encryptionVersion': kE2eeEncryptionVersion,
        },
        if (replyToId != null) 'replyToId': _parseRoomId(replyToId),
        if (isAnonymous) 'isAnonymous': true,
      },
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  Future<Message> sendTypedMessage(
    String chatRoomId,
    String content, {
    MessageType type = MessageType.text,
    bool isAnonymous = false,
    String? replyToId,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.sendMessage,
      body: {
        'chatRoomId': roomId,
        'content': content,
        'messageType': type.name.toUpperCase(),
        if (replyToId != null) 'replyToId': _parseRoomId(replyToId),
        if (isAnonymous) 'isAnonymous': true,
      },
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  Future<Message> sendStickerMessage(
    String chatRoomId,
    int stickerId, {
    bool isAnonymous = false,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.sendMessage,
      body: {
        'chatRoomId': roomId,
        'messageType': 'STICKER',
        'stickerId': stickerId,
        'isAnonymous': isAnonymous,
      },
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'] ?? data['message'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有贴纸消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  Future<Message> generateImageMessage(
    String chatRoomId, {
    required String prompt,
    String size = '1024*1024',
    bool expand = true,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.generateImage,
      body: {
        'roomId': roomId,
        'prompt': prompt,
        'n': 1,
        'size': size,
        'expand': expand,
      },
    );
    final data = _decodeResponse(response);
    final responseData = data['data'];
    final messageJson =
        responseData is Map<String, dynamic> ? responseData['message'] : null;
    if (messageJson is Map<String, dynamic>) {
      return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
    }
    if (responseData is Map<String, dynamic> &&
        responseData['messageId'] != null) {
      return Message(
        id: responseData['messageId'].toString(),
        content: prompt,
        senderId: _authService.currentUser?.id.toString() ?? '',
        senderName: _authService.currentUser?.displayName ??
            _authService.currentUser?.username ??
            '',
        chatRoomId: chatRoomId,
        type: MessageType.imageGeneration,
        status: MessageStatus.sending,
        timestamp: DateTime.now(),
        imageGenPrompt: prompt,
        imageGenStatus: responseData['status']?.toString() ?? 'QUEUED',
      );
    }
    throw const ChatDataException('图片生成任务已提交但响应中没有消息数据');
  }

  Future<List<MessageReaction>> addReaction(
    String messageId,
    String emoji,
  ) async {
    final id = _parseRoomId(messageId);
    final response = await _request(
      'POST',
      ApiConstants.messageReactions(id),
      body: {'emoji': emoji},
    );
    return _extractReactions(_decodeResponse(response));
  }

  Future<List<MessageReaction>> removeReaction(
    String messageId,
    String emoji,
  ) async {
    final id = _parseRoomId(messageId);
    final response = await _request(
      'DELETE',
      ApiConstants.messageReaction(id, emoji),
    );
    return _extractReactions(_decodeResponse(response));
  }

  Future<PollInfo> createPoll(
    String chatRoomId, {
    required String question,
    required List<String> options,
    bool multiSelect = false,
    bool anonymous = false,
    DateTime? expiresAt,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.polls,
      body: {
        'chatRoomId': roomId,
        'question': question,
        'options': options,
        'multiSelect': multiSelect,
        'anonymous': anonymous,
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      },
    );
    return _pollFromResponse(_decodeResponse(response));
  }

  Future<PollInfo> votePoll(int pollId, List<int> optionIndexes) async {
    final response = await _request(
      'POST',
      ApiConstants.pollVotes(pollId),
      body: {'optionIndexes': optionIndexes},
    );
    return _pollFromResponse(_decodeResponse(response));
  }

  Future<PollInfo> getPoll(int pollId) async {
    final response = await _request('GET', ApiConstants.pollDetail(pollId));
    return _pollFromResponse(_decodeResponse(response));
  }

  Future<List<ReadReceipt>> getReadBy(String messageId) async {
    final id = _parseRoomId(messageId);
    final response = await _request('GET', ApiConstants.messageReadBy(id));
    final data = _decodeResponse(response);
    final value = data['data'] ?? data['receipts'] ?? data['readBy'];
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(ReadReceipt.fromJson)
        .toList();
  }

  Future<List<StickerPack>> getStickerPacks() async {
    final response = await _request('GET', ApiConstants.stickerPacks);
    final data = _decodeResponse(response);
    final value = data['data'] ?? data['packs'] ?? data['stickerPacks'];
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(StickerPack.fromJson)
        .toList();
  }

  Future<List<StickerItem>> getStickers(int packId) async {
    final response = await _request(
      'GET',
      ApiConstants.stickerPackStickers(packId),
    );
    final data = _decodeResponse(response);
    final value = data['data'] ?? data['stickers'];
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(StickerItem.fromJson)
        .toList();
  }

  Future<StickerPack> uploadStickerPack({
    required String name,
    required List<PickedChatFile> stickers,
    PickedChatFile? cover,
    bool isPublic = false,
  }) async {
    if (stickers.isEmpty) {
      throw const ChatDataException('至少选择 1 张贴纸图片');
    }
    final response = await _requestMultipartFiles(
      ApiConstants.stickerPacks,
      fields: {
        'name': name.trim().isEmpty ? '我的贴纸包' : name.trim(),
        'isPublic': isPublic.toString(),
      },
      files: {
        if (cover != null) 'cover': [cover],
        'files': stickers,
      },
    );
    final data = _decodeResponse(response);
    final value = data['data'] ?? data['pack'];
    if (value is! Map<String, dynamic>) {
      throw const ChatDataException('贴纸包上传成功但响应无数据');
    }
    return StickerPack.fromJson(value);
  }

  /// 发附件。传了 [chat] 且它是双方都开了端到端加密的私聊时，文件先在本机加密：
  /// 服务器只收到一个 encrypted.bin 和密文信封（真实文件名、类型、文件密钥都在信封里），
  /// 也就不会转码语音。转发附件走同一条路：先下载解密，到了目标会话再按它的状态加密。
  ///
  /// [onProgress] 报真实的上传字节进度；[cancelToken] 能中止上传；整次上传超过
  /// [uploadTimeoutForBytes] 算出的时限就中止并抛 [UploadTimeoutException]。
  /// [clientMessageId] 交给服务器，它推回这条消息时带上，发送端据此换掉本地的上传气泡。
  Future<Message> sendFileMessage(
    String chatRoomId,
    PickedChatFile file, {
    MessageType? messageType,
    Chat? chat,
    String? clientMessageId,
    UploadProgressCallback? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final kind = _attachmentKind(file, messageType);
    final sealed = chat == null
        ? null
        : await _e2ee.sealFile(
            chat,
            name: file.name,
            mimeType: file.mimeType ??
                _mimeTypeFromFileName(file.name) ??
                'application/octet-stream',
            kind: kind,
            readBytes: () => _readPickedFileBytes(file),
            // 服务器看不到加密的图，小预览图只能在这边做好、加密后一起传；
            // 发图前压缩时已经顺带做好了，转发等没有现成的就现做一张。
            readThumbnail: kind != 'image'
                ? null
                : file.thumbnail ??
                    () async => (_imageThumbnailer ??
                        ImageUploadPreparer.shared.thumbnailFor)(
                      await _readPickedFileBytes(file),
                    ),
          );
    if (cancelToken?.isCancelled == true) {
      throw const UploadCancelledException();
    }
    final fields = {
      'chatRoomId': roomId.toString(),
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
      if (sealed != null) ...{
        'messageType': 'FILE',
        'encryptedContent': sealed.envelope,
        'encryptionVersion': kE2eeEncryptionVersion.toString(),
      } else if (messageType != null)
        'messageType': messageType.name.toUpperCase(),
    };
    final upload = sealed == null
        ? file
        : PickedChatFile(
            name: 'encrypted.bin',
            size: sealed.ciphertext.length,
            mimeType: 'application/octet-stream',
            bytes: sealed.ciphertext,
          );
    final thumbnailCiphertext = sealed?.thumbnailCiphertext;
    final response = await _requestMultipart(
      ApiConstants.sendFileMessage,
      fields: fields,
      file: upload,
      extraFiles: [
        if (thumbnailCiphertext != null)
          MultipartExtraFile(
            field: 'thumbnail',
            fileName: 'encrypted.bin',
            bytes: thumbnailCiphertext,
            contentType: MediaType('application', 'octet-stream'),
          ),
      ],
      onSendProgress: onProgress,
      cancelToken: cancelToken,
      timeout: uploadTimeoutForBytes(
          upload.size + (thumbnailCiphertext?.length ?? 0)),
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有文件消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  static String _attachmentKind(PickedChatFile file, MessageType? type) {
    switch (type) {
      case MessageType.image:
        return 'image';
      case MessageType.voice:
        return 'voice';
      case MessageType.audio:
        return 'audio';
      case MessageType.video:
        return 'video';
      case MessageType.file:
        return 'file';
      default:
        break;
    }
    final mime = (file.mimeType ?? '').toLowerCase();
    final name = file.name.toLowerCase();
    if (mime.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|gif|webp)$').hasMatch(name)) {
      return 'image';
    }
    if (mime.startsWith('video/') || RegExp(r'\.(mp4|mov)$').hasMatch(name)) {
      return 'video';
    }
    if (mime.startsWith('audio/') ||
        RegExp(r'\.(mp3|m4a|wav|aac|ogg|webm)$').hasMatch(name)) {
      return 'voice';
    }
    return 'file';
  }

  /// 取文件字节：web 选的文件本来就在内存里，原生平台按路径读（借 http 的 fromPath，
  /// 这样这个文件不用直接依赖 dart:io，web 照样能编译）。
  static Future<Uint8List> _readPickedFileBytes(PickedChatFile file) async {
    final bytes = file.bytes;
    if (bytes != null) return Uint8List.fromList(bytes);
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const ChatDataException('请选择有效文件');
    }
    final part = await http.MultipartFile.fromPath('file', path);
    return part.finalize().toBytes();
  }

  /// 把远程图片取回来（不发消息），用于粘贴后在发送栏里预览。
  Future<PickedChatFile> fetchRemoteImage(String url) async {
    final response = await _request(
      'POST',
      ApiConstants.fetchRemoteImage,
      body: {'url': url},
    );
    final data = _decodeResponse(response);
    final payload = data['data'];
    if (payload is! Map<String, dynamic>) {
      throw const ChatDataException('响应中没有图片数据');
    }
    final base64Content = payload['base64'];
    if (base64Content is! String || base64Content.isEmpty) {
      throw const ChatDataException('响应中没有图片内容');
    }
    final bytes = base64Decode(base64Content);
    return PickedChatFile(
      name: payload['fileName']?.toString() ?? 'paste.png',
      size: bytes.length,
      mimeType: payload['contentType']?.toString(),
      bytes: bytes,
    );
  }

  /// 按图片地址发图：粘贴网页图片时剪贴板里只有远程 URL，
  /// 浏览器 fetch 会被 CORS 挡住，交给服务端代抓。
  Future<Message> sendImageFromUrl(
    String chatRoomId,
    String url, {
    String? clientMessageId,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.sendFileFromUrl,
      body: {
        'chatRoomId': roomId,
        'url': url,
        if (clientMessageId != null) 'clientMessageId': clientMessageId,
      },
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('发送成功但响应中没有图片消息数据');
    }
    return Message.fromJson(messageJson, fallbackChatRoomId: chatRoomId);
  }

  Future<MessagePage> searchMessages(
    String chatRoomId,
    String keyword, {
    int page = 0,
    int size = 20,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.searchMessagesInRoom(roomId)).replace(
      queryParameters: {
        'q': keyword,
        'offset': (page * size).toString(),
        'limit': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, chatRoomId);
    return _messagePageFromData(data, messages);
  }

  /// 在当前用户所在的全部聊天里搜索消息（遵守各自的“清空记录”起点）。
  Future<MessagePage> searchAllMessages(
    String keyword, {
    int page = 0,
    int size = 20,
  }) async {
    final uri = Uri.parse(ApiConstants.searchAllMessages).replace(
      queryParameters: {
        'q': keyword,
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, '');
    return _messagePageFromData(data, messages);
  }

  Future<LinkPreview> fetchUrlPreview(String url) async {
    final response = await _request(
      'POST',
      ApiConstants.urlPreview,
      body: {'url': url},
    );
    final data = _decodeResponse(response);
    final previewJson = data['data'] ?? data['preview'];
    if (previewJson is! Map<String, dynamic>) {
      throw const ChatDataException('链接预览响应中没有预览数据');
    }
    return LinkPreview.fromJson(previewJson);
  }

  Future<MessagePage> getMentionedMessages(
    String chatRoomId, {
    int page = 0,
    int size = 20,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.chatRoomMentionsMe(roomId)).replace(
      queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, chatRoomId);
    return _messagePageFromData(data, messages);
  }

  Future<MessagePage> getFileMessages(
    String chatRoomId, {
    MessageType? type,
    int page = 0,
    int size = 50,
  }) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.chatRoomFiles(roomId)).replace(
      queryParameters: {
        if (type == MessageType.image || type == MessageType.file)
          'messageType': type!.name.toUpperCase(),
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, chatRoomId);
    return _messagePageFromData(data, messages);
  }

  Future<Message> recallMessage(String messageId) async {
    final id = _parseRoomId(messageId);
    final response = await _request('POST', ApiConstants.recallMessage(id));
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('消息已撤回但响应中没有消息数据');
    }
    return Message.fromJson(messageJson);
  }

  Future<Message> deleteMessage(String messageId) async {
    final id = _parseRoomId(messageId);
    final response = await _request('DELETE', ApiConstants.deleteMessage(id));
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('消息已删除但响应中没有消息数据');
    }
    return Message.fromJson(messageJson);
  }

  /// 编辑。加密消息要传重新加密后的 [encryptedContent]（服务器不接受把它改成明文）。
  Future<Message> editMessage(
    String messageId,
    String content, {
    String? encryptedContent,
  }) async {
    final id = _parseRoomId(messageId);
    final encrypted = encryptedContent != null && encryptedContent.isNotEmpty;
    final response = await _request(
      'PUT',
      ApiConstants.editMessage(id),
      body: {
        'content': encrypted ? kE2eeServerPlaceholder : content,
        if (encrypted) ...{
          'encryptedContent': encryptedContent,
          'encryptionVersion': kE2eeEncryptionVersion,
        },
      },
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('消息已编辑但响应中没有消息数据');
    }
    return Message.fromJson(messageJson);
  }

  Future<Message> forwardMessage(
    String messageId,
    String targetChatRoomId,
  ) async {
    final id = _parseRoomId(messageId);
    final targetId = _parseRoomId(targetChatRoomId);
    final response = await _request(
      'POST',
      ApiConstants.forwardMessage(id),
      body: {'targetChatRoomId': targetId},
    );
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('消息已转发但响应中没有消息数据');
    }
    return Message.fromJson(
      messageJson,
      fallbackChatRoomId: targetChatRoomId,
    );
  }

  Future<List<Message>> pinMessage(String chatRoomId, String messageId) async {
    final roomId = _parseRoomId(chatRoomId);
    final id = _parseRoomId(messageId);
    final response =
        await _request('POST', ApiConstants.pinMessage(roomId, id));
    return _extractMessages(_decodeResponse(response), chatRoomId);
  }

  Future<List<Message>> unpinMessage(
      String chatRoomId, String messageId) async {
    final roomId = _parseRoomId(chatRoomId);
    final id = _parseRoomId(messageId);
    final response =
        await _request('DELETE', ApiConstants.pinMessage(roomId, id));
    return _extractMessages(_decodeResponse(response), chatRoomId);
  }

  Future<List<Message>> getPinnedMessages(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    final response = await _request('GET', ApiConstants.roomPins(roomId));
    return _extractMessages(_decodeResponse(response), chatRoomId);
  }

  Future<Message> starMessage(String messageId) async {
    final id = _parseRoomId(messageId);
    final response = await _request('POST', ApiConstants.starMessage(id));
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('消息已收藏但响应中没有消息数据');
    }
    return Message.fromJson(messageJson);
  }

  Future<Message> unstarMessage(String messageId) async {
    final id = _parseRoomId(messageId);
    final response = await _request('DELETE', ApiConstants.starMessage(id));
    final data = _decodeResponse(response);
    final messageJson = data['data'];
    if (messageJson is! Map<String, dynamic>) {
      throw const ChatDataException('消息已取消收藏但响应中没有消息数据');
    }
    return Message.fromJson(messageJson);
  }

  Future<MessagePage> getStarredMessages({
    int page = 0,
    int size = 20,
  }) async {
    final uri = Uri.parse(ApiConstants.myStarredMessages).replace(
      queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final messages = _extractMessages(data, '');
    return _messagePageFromData(data, messages);
  }

  Future<DownloadedChatFile> downloadFile(Message message) async {
    final fileUrl = message.fileUrl?.isNotEmpty == true
        ? message.fileUrl
        : message.imageGenUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      throw const ChatDataException('消息没有可下载的文件');
    }

    final resolvedUrl = ApiConstants.resolveFileUrl(fileUrl);
    final response = ApiConstants.requiresAuthHeaderForFile(fileUrl)
        ? await _request('GET', resolvedUrl)
        : await http
            .get(Uri.parse(resolvedUrl))
            .timeout(ApiConstants.requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatDataException(_extractError(response.body));
    }

    if (message.isEncrypted) {
      // 端到端加密附件：服务器上是密文，用消息密文里的文件密钥在本机解开。
      final key = _e2ee.attachmentKeyFor(message);
      if (key == null) {
        throw const ChatDataException('无法解密这个附件');
      }
      return DownloadedChatFile(
        name: key.name,
        bytes: await _e2ee.openAttachment(message, response.bodyBytes),
        mimeType: key.mimeType,
      );
    }

    return DownloadedChatFile(
      name: message.fileName ?? message.content,
      bytes: List<int>.from(response.bodyBytes),
      mimeType: response.headers['content-type'] ?? message.fileType,
    );
  }

  Future<void> markAllRead(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    await _request(
      'POST',
      ApiConstants.markAllRead(roomId),
    );
  }

  Future<void> markMessageRead(String messageId) async {
    final id = _parseRoomId(messageId);
    await _request('POST', ApiConstants.markMessageRead(id));
  }

  Future<void> clearChatHistory(String chatRoomId) async {
    await updateChatRoomDisplayState(chatRoomId, action: 'CLEAR');
  }

  Future<int> getUnreadCount(String chatRoomId) async {
    final roomId = _parseRoomId(chatRoomId);
    final uri = Uri.parse(ApiConstants.unreadCount).replace(
      queryParameters: {'chatRoomId': roomId.toString()},
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final count = data['unreadCount'] ?? data['totalUnreadCount'] ?? 0;
    return count is int ? count : int.tryParse(count.toString()) ?? 0;
  }

  @Deprecated(
      'Use normal chat messages with @bot mentions; kept for legacy clients.')
  Future<AgentTask> createAgentTask(
    String chatRoomId,
    String prompt, {
    String? botId,
    String? kind,
    String? artifactWorkspaceId,
    String? artifactFolderId,
    String? artifactFileName,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.agentTasks,
      body: {
        'chatRoomId': _parseRoomId(chatRoomId),
        'prompt': prompt,
        if (kind != null && kind.trim().isNotEmpty) 'kind': kind.trim(),
        if (botId != null) 'botId': _parseRoomId(botId),
        if (artifactWorkspaceId != null)
          'artifactWorkspaceId': _parseRoomId(artifactWorkspaceId),
        if (artifactFolderId != null)
          'artifactFolderId': _parseRoomId(artifactFolderId),
        if (artifactFileName != null && artifactFileName.trim().isNotEmpty)
          'artifactFileName': artifactFileName.trim(),
      },
    );
    final data = _decodeResponse(response);
    final taskJson = data['data'];
    if (taskJson is! Map<String, dynamic>) {
      throw const ChatDataException('Agent 任务已创建但响应中没有任务数据');
    }
    return AgentTask.fromJson(taskJson);
  }

  @Deprecated(
      'Use normal chat messages with @bot mentions; kept for legacy clients.')
  Future<List<AgentTask>> getAgentTasks(
    String chatRoomId, {
    int page = 0,
    int size = 20,
  }) async {
    final uri = Uri.parse(ApiConstants.agentTasks).replace(
      queryParameters: {
        'chatRoomId': _parseRoomId(chatRoomId).toString(),
        'page': page.toString(),
        'size': size.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    final taskContainer = data['data'] is Map<String, dynamic>
        ? data['data'] as Map<String, dynamic>
        : data;
    return _extractList(taskContainer, keys: const ['tasks', 'data', 'content'])
        .whereType<Map<String, dynamic>>()
        .map(AgentTask.fromJson)
        .toList();
  }

  Future<Chat> _enrichChat(Chat chat) async {
    Message? lastMessage = chat.lastMessage;
    int unreadCount = chat.unreadCount;
    List<User>? participants;

    try {
      final recent = await getRecentMessages(chat.id, limit: 1);
      if (recent.isNotEmpty) {
        lastMessage = recent.first;
      }
    } catch (_) {
      // Last-message decoration should not block the room list.
    }
    if (lastMessage == null) {
      try {
        final page = await getMessagePage(chat.id, page: 0, size: 1);
        if (page.messages.isNotEmpty) {
          lastMessage = page.messages.last;
        }
      } catch (_) {
        // Private-room summaries must still render even when message decoration fails.
      }
    }

    try {
      unreadCount = await getUnreadCount(chat.id);
    } catch (_) {
      // Unread decoration should not block the room list.
    }

    try {
      final members = await getChatRoomMembers(chat.id);
      if (members.isNotEmpty) {
        participants = members.map((member) => member.user).toList();
      }
    } catch (_) {
      // Member decoration should not block the room list.
    }

    bool isPinned = chat.isPinned;
    bool isMuted = chat.isMuted;
    DateTime? hiddenAt = chat.hiddenAt;
    bool isBlocked = chat.isBlocked;
    String? clearedBeforeMessageId = chat.clearedBeforeMessageId;
    try {
      final settings = await getNotificationSettings(chat.id);
      isPinned = _parseBool(settings['pinned']);
      isMuted = _parseBool(settings['muted']);
      hiddenAt = _parseDateTime(settings['hiddenAt'] ?? settings['hidden_at']);
      isBlocked = _parseBool(
        settings['isBlocked'] ?? settings['blocked'] ?? settings['is_blocked'],
      );
      clearedBeforeMessageId = (settings['clearedBeforeMessageId'] ??
              settings['cleared_before_message_id'])
          ?.toString();
    } catch (_) {
      // Per-room preferences are decorative for list loading.
    }

    return chat.copyWith(
      lastMessage: lastMessage,
      updatedAt: _updatedAtWithLastMessage(chat, lastMessage),
      unreadCount: unreadCount,
      participants: participants,
      isPinned: isPinned,
      isMuted: isMuted,
      hiddenAt: hiddenAt,
      isBlocked: isBlocked,
      clearedBeforeMessageId: clearedBeforeMessageId,
    );
  }

  static DateTime? _updatedAtWithLastMessage(Chat chat, Message? lastMessage) {
    final existing = chat.updatedAt;
    if (lastMessage == null) return existing;
    if (existing == null || lastMessage.timestamp.isAfter(existing)) {
      return lastMessage.timestamp;
    }
    return existing;
  }

  Future<dynamic> _request(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final request = _authenticatedRequest ?? _authService.authenticatedRequest;
    return request(method, url, headers: headers, body: body);
  }

  Chat _chatFromBackgroundResponse(dynamic response) {
    final data = _decodeResponse(response);
    final chatRoomJson = data['chatRoom'] ?? data['data'];
    if (chatRoomJson is! Map<String, dynamic>) {
      throw const ChatDataException('房间背景更新成功但响应中没有聊天室数据');
    }
    return Chat.fromJson(chatRoomJson);
  }

  /// 单文件 multipart 上传：带真实进度、可取消、有硬时限；401/403 时刷新令牌再发一次
  /// （和原来 http.MultipartRequest 的做法一致）。时限到了就中止请求，别让 XHR 挂在后台。
  Future<dynamic> _requestMultipart(
    String url, {
    required Map<String, String> fields,
    required PickedChatFile file,
    List<MultipartExtraFile> extraFiles = const [],
    UploadProgressCallback? onSendProgress,
    UploadCancelToken? cancelToken,
    Duration timeout = ApiConstants.uploadTimeout,
  }) async {
    if (_multipartRequest != null) {
      return _multipartRequest(url, fields: fields, file: file);
    }
    final bytes = file.bytes;
    final path = file.path;
    if (bytes == null && (path == null || path.isEmpty)) {
      throw const ChatDataException('请选择有效文件');
    }

    // 内部令牌：调用方取消或超时都走它，真正中止正在进行的请求。
    final abort = UploadCancelToken();
    var timedOut = false;
    final deadline = Timer(timeout, () {
      timedOut = true;
      abort.cancel();
    });
    final forwardCancel = cancelToken?.whenCancelled.then((_) => abort.cancel());
    unawaited(forwardCancel);

    Future<http.Response> send() {
      final token = _authService.accessToken;
      return _uploadTransport(
        url,
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
        fields: fields,
        fileField: 'file',
        fileName: file.name,
        bytes: bytes,
        path: path,
        contentType: _mediaTypeFor(file),
        extraFiles: extraFiles,
        onSendProgress: onSendProgress,
        cancelToken: abort,
      );
    }

    try {
      if (cancelToken?.isCancelled == true) {
        throw const UploadCancelledException();
      }
      var response = await send();
      if ((response.statusCode == 401 || response.statusCode == 403) &&
          await _authService.refreshAccessToken()) {
        if (abort.isCancelled) throw const UploadCancelledException();
        response = await send();
      }
      return response;
    } on UploadCancelledException {
      if (timedOut) throw UploadTimeoutException(timeout);
      rethrow;
    } finally {
      deadline.cancel();
    }
  }

  Future<dynamic> _requestMultipartFiles(
    String url, {
    required Map<String, String> fields,
    required Map<String, List<PickedChatFile>> files,
  }) async {
    if (_multipartFilesRequest != null) {
      return _multipartFilesRequest(url, fields: fields, files: files);
    }

    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      final token = _authService.accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields.addAll(fields);

      for (final entry in files.entries) {
        for (final file in entry.value) {
          final bytes = file.bytes;
          if (bytes != null) {
            request.files.add(http.MultipartFile.fromBytes(
              entry.key,
              bytes,
              filename: file.name,
              contentType: _mediaTypeFor(file),
            ));
          } else if (file.path != null && file.path!.isNotEmpty) {
            request.files.add(await http.MultipartFile.fromPath(
              entry.key,
              file.path!,
              filename: file.name,
              contentType: _mediaTypeFor(file),
            ));
          } else {
            throw const ChatDataException('请选择有效文件');
          }
        }
      }

      final streamedResponse =
          await request.send().timeout(ApiConstants.uploadTimeout);
      return http.Response.fromStream(streamedResponse);
    }

    var response = await send();
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        await _authService.refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  MediaType? _mediaTypeFor(PickedChatFile file) {
    final mimeType = file.mimeType ?? _mimeTypeFromFileName(file.name);
    if (mimeType == null) return null;
    final parts = mimeType.split('/');
    if (parts.length != 2 || parts.any((part) => part.isEmpty)) return null;
    return MediaType(parts[0], parts[1]);
  }

  String? _mimeTypeFromFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.zip')) return 'application/zip';
    return null;
  }

  List<Chat> _sortChats(List<Chat> chats) {
    return _sortChatsInPlace(chats);
  }

  static List<Chat> _sortChatsInPlace(List<Chat> chats) {
    chats.sort((a, b) {
      final aTime = a.lastMessage?.timestamp ?? a.updatedAt ?? a.createdAt;
      final bTime = b.lastMessage?.timestamp ?? b.updatedAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return chats;
  }

  Map<String, dynamic> _decodeResponse(dynamic response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatDataException(_extractHttpError(
        response.statusCode,
        response.body,
      ));
    }
    if (response.bodyBytes.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is List<dynamic>) {
      return {'data': decoded};
    }
    return {};
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['error'] ?? decoded['message'] ?? '请求失败').toString();
      }
    } catch (_) {
      // Fall through to generic message.
    }
    return '请求失败';
  }

  /// 请求被 401 后已经试过续期仍失败：只有服务器明确拒绝了 refresh token 才算登录过期；
  /// 否则是后端重启/网络抖动，给一句不会触发退出登录的提示。
  String _sessionExpiredOrTransient() {
    if (_authService.refreshTokenRejected) {
      return '登录状态已过期，请重新登录';
    }
    return '暂时连不上服务器，稍后会自动重试';
  }

  String _extractHttpError(int statusCode, String body) {
    final error = _extractError(body);
    if (statusCode == 401) {
      return _sessionExpiredOrTransient();
    }
    if (statusCode == 403) {
      final lower = error.toLowerCase();
      if (lower == 'forbidden' ||
          lower.contains('jwt') ||
          lower.contains('token') ||
          lower.contains('authentication')) {
        return _sessionExpiredOrTransient();
      }
      return error == '请求失败' ? '没有权限访问此内容' : error;
    }
    return error;
  }

  List<dynamic> _extractList(
    Map<String, dynamic> data, {
    required List<String> keys,
  }) {
    for (final key in keys) {
      final value = data[key];
      if (value is List<dynamic>) {
        return value;
      }
      if (value is Map<String, dynamic>) {
        final nested = _extractList(value, keys: keys);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    }
    return const [];
  }

  List<Message> _extractMessages(Map<String, dynamic> data, String chatRoomId) {
    return _extractList(data, keys: const ['messages', 'data', 'content'])
        .whereType<Map<String, dynamic>>()
        .map((json) => Message.fromJson(json, fallbackChatRoomId: chatRoomId))
        .toList();
  }

  List<MessageReaction> _extractReactions(Map<String, dynamic> data) {
    final value = data['data'] ?? data['reactions'];
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(MessageReaction.fromJson)
        .toList();
  }

  PollInfo _pollFromResponse(Map<String, dynamic> data) {
    final value = data['data'] ?? data['poll'];
    if (value is! Map<String, dynamic>) {
      throw const ChatDataException('投票响应中没有投票数据');
    }
    return PollInfo.fromJson(value);
  }

  MessagePage _messagePageFromData(
    Map<String, dynamic> data,
    List<Message> messages,
  ) {
    final currentPage = _parseInt(data['currentPage']) ?? 0;
    final totalPages = _parseInt(data['totalPages']) ??
        (messages.isEmpty ? 0 : currentPage + 1);
    final totalElements = _parseInt(data['totalElements']) ?? messages.length;
    final hasNext = _parseBool(data['hasNext']) ||
        (totalPages > 0 && currentPage < totalPages - 1);
    final hasPrevious = _parseBool(data['hasPrevious']) || currentPage > 0;

    return MessagePage(
      messages: messages,
      currentPage: currentPage,
      totalPages: totalPages,
      totalElements: totalElements,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
  }

  List<ChatRoomMember> _extractMembers(Map<String, dynamic> data) {
    return _extractList(data, keys: const ['members', 'data', 'content'])
        .whereType<Map<String, dynamic>>()
        .map(ChatRoomMember.fromJson)
        .toList();
  }

  int _parseRoomId(String chatRoomId) {
    final parsed = int.tryParse(chatRoomId);
    if (parsed == null) {
      throw ChatDataException('无效聊天室ID: $chatRoomId');
    }
    return parsed;
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
