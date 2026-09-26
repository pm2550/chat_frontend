part of '../chat_screen_test.dart';

class FakeChatDataService extends ChatDataService {
  FakeChatDataService({
    required this.messages,
    this.searchResults = const [],
    this.sendError,
    this.sendFileError,
    this.messagePageError,
    this.routeChat,
  }) : super(authenticatedRequest: _unusedRequest);

  final List<Message> messages;
  final List<Message> searchResults;
  final Object? sendError;
  final Object? sendFileError;
  final Object? messagePageError;
  final Chat? routeChat;
  final List<PickedChatFile> sentFiles = [];
  final List<String> sentTexts = [];
  final List<String?> sentEncryptedContents = [];
  final List<String?> sentReplyIds = [];
  final List<String> searchKeywords = [];
  final List<String> deletedMessageIds = [];
  final List<String> recalledMessageIds = [];
  final List<String> loadedChatRoomIds = [];
  final List<String> readMessageIds = [];
  bool markAllReadCalled = false;
  int deltaRequestCount = 0;
  int messagePageRequestCount = 0;

  static Future<http.Response> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Chat> getChatRoom(
    String chatRoomId, {
    bool includeDetails = true,
  }) async {
    loadedChatRoomIds.add(chatRoomId);
    return routeChat ??
        Chat(
          id: chatRoomId,
          name: 'Loaded Room',
          type: ChatType.group,
          createdAt: DateTime.parse('2024-01-01T10:00:00'),
        );
  }

  @override
  Future<MessagePage> getMessagePage(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    messagePageRequestCount += 1;
    if (messagePageError != null) {
      throw messagePageError!;
    }
    return MessagePage(
      messages: messages,
      currentPage: page,
      totalPages: 1,
      totalElements: messages.length,
      hasNext: false,
      hasPrevious: page > 0,
    );
  }

  @override
  Future<List<Message>> getMessageDelta(
    String chatRoomId, {
    required String afterMessageId,
    int size = 50,
  }) async {
    deltaRequestCount += 1;
    final cursor = int.tryParse(afterMessageId) ?? -1;
    return messages
        .where((message) => (int.tryParse(message.id) ?? -1) > cursor)
        .toList();
  }

  @override
  Future<List<Message>> getMessages(
    String chatRoomId, {
    int page = 0,
    int size = 50,
  }) async {
    return messages;
  }

  @override
  Future<MessagePage> searchMessages(
    String chatRoomId,
    String keyword, {
    int page = 0,
    int size = 20,
  }) async {
    searchKeywords.add(keyword);
    return MessagePage(
      messages: searchResults,
      currentPage: page,
      totalPages: 1,
      totalElements: searchResults.length,
      hasNext: false,
      hasPrevious: false,
    );
  }

  @override
  Future<Message> deleteMessage(String messageId) async {
    deletedMessageIds.add(messageId);
    final message = messages.firstWhere((message) => message.id == messageId);
    return message.copyWith(
      content: '[消息已删除]',
      isDeleted: true,
      chatRoomId: message.chatRoomId,
    );
  }

  @override
  Future<Message> recallMessage(String messageId) async {
    recalledMessageIds.add(messageId);
    final message = messages.firstWhere((message) => message.id == messageId);
    return message.copyWith(
      content: '[消息已撤回]',
      isDeleted: true,
      isRecalled: true,
      chatRoomId: message.chatRoomId,
    );
  }

  @override
  Future<void> markAllRead(String chatRoomId) async {
    markAllReadCalled = true;
  }

  @override
  Future<void> markMessageRead(String messageId) async {
    readMessageIds.add(messageId);
  }

  Message? _findMessage(String? messageId) {
    if (messageId == null) return null;
    for (final message in messages) {
      if (message.id == messageId) return message;
    }
    return null;
  }

  @override
  Future<Message> sendTextMessage(
    String chatRoomId,
    String content, {
    bool isAnonymous = false,
    String? replyToId,
    String? encryptedContent,
  }) async {
    final error = sendError;
    if (error != null) {
      throw error;
    }
    sentTexts.add(content);
    sentEncryptedContents.add(encryptedContent);
    sentReplyIds.add(replyToId);
    return Message(
      id: 'sent-1',
      content: content,
      senderId: 'user1',
      senderName: isAnonymous ? '匿名用户' : '我',
      chatRoomId: chatRoomId,
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
      replyToId: replyToId,
      replyToMessage: _findMessage(replyToId),
      replyToMessageId: replyToId,
      isAnonymous: isAnonymous,
      anonymousName: isAnonymous ? '匿名用户' : null,
    );
  }

  @override
  Future<Message> sendFileMessage(
    String chatRoomId,
    PickedChatFile file, {
    MessageType? messageType,
    Chat? chat,
    String? clientMessageId,
    UploadProgressCallback? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    sentFiles.add(file);
    final error = sendFileError;
    if (error != null) {
      throw error;
    }
    final isImage = file.mimeType?.startsWith('image/') == true ||
        file.name.toLowerCase().endsWith('.png');
    return Message(
      id: 'file-1',
      content: file.name,
      senderId: 'user1',
      senderName: '我',
      chatRoomId: chatRoomId,
      type: messageType ?? (isImage ? MessageType.image : MessageType.file),
      status: MessageStatus.sent,
      timestamp: DateTime.parse('2024-01-01T10:02:00'),
      fileUrl: '/api/files/chat/${file.name}',
      fileName: file.name,
      fileSize: file.size,
      fileType: file.mimeType,
    );
  }

  @override
  Future<DownloadedChatFile> downloadFile(Message message) async {
    return DownloadedChatFile(
      name: message.fileName ?? message.content,
      bytes: const [1, 2, 3],
      mimeType: message.fileType,
    );
  }

  @override
  Future<List<StickerPack>> getStickerPacks() async {
    return const <StickerPack>[];
  }

  @override
  Future<List<StickerItem>> getStickers(int packId) async {
    return const <StickerItem>[];
  }
}

class FakeBotService extends BotService {
  FakeBotService({this.roomBots = const []});

  final List<BotConfig> roomBots;

  @override
  Future<List<BotConfig>> getBotsInRoom(int roomId) async => roomBots;
}

class FakeContactDataService extends ContactDataService {
  FakeContactDataService({
    this.friends = const [],
    this.sentRequests = const [],
    this.privateChatsByUserId = const {},
  }) : super(authenticatedRequest: _unusedRequest);

  final List<User> friends;
  final List<FriendshipRequest> sentRequests;
  final Map<String, Chat> privateChatsByUserId;
  final List<String> sentFriendRequestIds = [];
  final List<String> createdPrivateChatUserIds = [];

  static Future<http.Response> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<User>> getFriends() async => friends;

  @override
  Future<List<FriendshipRequest>> getSentFriendRequests() async => sentRequests;

  @override
  Future<FriendshipRequest> sendFriendRequest(String userId) async {
    sentFriendRequestIds.add(userId);
    final target = User(
      id: userId,
      username: 'target$userId',
      email: 'target$userId@test.com',
      displayName: '成员$userId',
      createdAt: DateTime.parse('2024-01-01T10:00:00'),
    );
    return FriendshipRequest(
      id: 'request-$userId',
      status: 'PENDING',
      user: User(
        id: '1',
        username: 'me',
        email: 'me@test.com',
        displayName: '我',
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      ),
      friend: target,
    );
  }

  @override
  Future<Chat> createPrivateChat(String userId) async {
    createdPrivateChatUserIds.add(userId);
    final chat = privateChatsByUserId[userId];
    if (chat != null) return chat;
    final now = DateTime.parse('2024-01-01T10:00:00');
    return Chat(
      id: 'private-$userId',
      name: '成员$userId',
      type: ChatType.private,
      createdAt: now,
      participants: [
        User(
          id: '1',
          username: 'me',
          email: 'me@test.com',
          displayName: '我',
          createdAt: now,
        ),
        User(
          id: userId,
          username: 'target$userId',
          email: 'target$userId@test.com',
          displayName: '成员$userId',
          createdAt: now,
        ),
      ],
    );
  }
}

class _NoSocketAuthService extends AuthService {
  _NoSocketAuthService() : super.test();

  String? _token = 'test-stale-access-token';

  @override
  String? get accessToken => _token;

  @override
  Future<bool> ensureAuthenticated() async => true;

  @override
  Future<bool> refreshAccessToken() async {
    _token = null;
    return false;
  }
}

class _CurrentUserNoSocketAuthService extends AuthService {
  _CurrentUserNoSocketAuthService({required this.userId}) : super.test();

  final String userId;
  String? _token = 'test-stale-access-token';

  @override
  User? get currentUser => User(
        id: userId,
        username: 'me',
        email: 'me@test.com',
        displayName: '我',
        createdAt: DateTime.parse('2024-01-01T10:00:00'),
      );

  @override
  String? get accessToken => _token;

  @override
  Future<bool> ensureAuthenticated() async => true;

  @override
  Future<bool> refreshAccessToken() async {
    _token = null;
    return false;
  }
}

class RecordingCallService extends ChatCallService {
  RecordingCallService() : super(webSocketService: WebSocketService());

  int? startedRoomId;
  int? startedPeerUserId;
  CallMediaKind? startedMediaKind;
  String? startedPeerName;

  @override
  Future<void> startOutgoingCall({
    required int chatRoomId,
    required CallMediaKind mediaKind,
    required String peerName,
    int? peerUserId,
  }) async {
    startedRoomId = chatRoomId;
    startedMediaKind = mediaKind;
    startedPeerName = peerName;
    startedPeerUserId = peerUserId;
  }
}

class FixedStateCallService extends ChatCallService {
  FixedStateCallService(this.fixedState)
      : super(webSocketService: WebSocketService());

  final ChatCallState fixedState;

  @override
  ChatCallState get state => fixedState;

  @override
  Future<void> hangUp({bool sendSignal = true}) async {}
}

/// 能进入来电/接听/拒绝状态、但不碰真实媒体的通话服务。
class AnswerableCallService extends ChatCallService {
  AnswerableCallService() : super(webSocketService: WebSocketService());

  ChatCallState _fakeState = const ChatCallState();
  bool accepted = false;
  bool rejected = false;

  @override
  ChatCallState get state => _fakeState;

  @override
  bool get isSupported => true;

  void _set(ChatCallState next) {
    _fakeState = next;
    notifyListeners();
  }

  @override
  Future<void> handleSignal(Map<String, dynamic> signal) async {
    if (signal['action'] == 'invite') {
      _set(ChatCallState(
        phase: CallPhase.incoming,
        callId: signal['callId']?.toString(),
        chatRoomId: int.tryParse(signal['chatRoomId'].toString()),
        mediaKind: CallMediaKind.audio,
        participants: [
          CallParticipant(
            userId: 7,
            displayName: signal['fromName']?.toString() ?? '好友',
          ),
        ],
      ));
    }
  }

  // 真实的接听/拒绝是异步的：状态在按钮回调之后的几帧里才变化。
  @override
  Future<void> acceptIncoming() async {
    accepted = true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    _set(_fakeState.copyWith(phase: CallPhase.connecting));
  }

  @override
  void rejectIncoming() {
    rejected = true;
    Future<void>.delayed(const Duration(milliseconds: 20), () {
      _set(const ChatCallState());
    });
  }

  void cancelByCaller() {
    _set(const ChatCallState(
      phase: CallPhase.ended,
      errorMessage: '对方已取消通话',
    ));
  }

  @override
  Future<void> hangUp({bool sendSignal = true}) async {}
}
