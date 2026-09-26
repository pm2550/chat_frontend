part of '../chat_list_page_test.dart';

class FakeChatListService extends ChatDataService {
  FakeChatListService({
    this.chats = const [],
    this.mentionedMessages = const {},
    this.error,
  }) : super(authenticatedRequest: _unusedRequest);

  List<Chat> chats;
  final Map<String, List<Message>> mentionedMessages;
  final Object? error;
  final List<String> loadedMentionRoomIds = [];
  final List<String> clearedRoomIds = [];
  final List<String> hiddenRoomIds = [];
  final List<String> blockedRoomIds = [];
  final List<String> pinnedRoomIds = [];
  final List<bool> forceRefreshRequests = [];

  static Future<dynamic> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Chat>> getChatRooms({
    int page = 0,
    int size = 30,
    bool includeDetails = true,
    int detailLimit = 8,
    bool includeHidden = false,
    bool includeBlocked = false,
    ChatType? type,
    ChatType? excludeType,
    bool forceRefresh = false,
  }) async {
    // 只记消息页那一路（群聊 + 频道）的请求；私聊列表由联系人目录单独拉。
    if (type != ChatType.private) forceRefreshRequests.add(forceRefresh);
    final err = error;
    if (err != null) {
      throw err;
    }
    if (page > 0) return const [];
    return chats
        .where((chat) => type == null || chat.type == type)
        .where((chat) => excludeType == null || chat.type != excludeType)
        .toList();
  }

  @override
  Future<MessagePage> getMentionedMessages(
    String chatRoomId, {
    int page = 0,
    int size = 20,
  }) async {
    loadedMentionRoomIds.add(chatRoomId);
    final messages = mentionedMessages[chatRoomId] ?? const <Message>[];
    return MessagePage(
      messages: messages,
      currentPage: page,
      totalPages: messages.isEmpty ? 0 : 1,
      totalElements: messages.length,
      hasNext: false,
      hasPrevious: false,
    );
  }

  @override
  Future<void> clearChatHistory(String chatRoomId) async {
    clearedRoomIds.add(chatRoomId);
  }

  @override
  Future<void> hideChatRoom(String chatRoomId) async {
    hiddenRoomIds.add(chatRoomId);
  }

  @override
  Future<void> blockChatRoom(String chatRoomId) async {
    blockedRoomIds.add(chatRoomId);
  }

  @override
  Future<Map<String, dynamic>> updateNotificationSettings(
    String chatRoomId, {
    bool? muted,
    bool? pinned,
  }) async {
    if (pinned == true) {
      pinnedRoomIds.add(chatRoomId);
    }
    return {'pinned': pinned ?? false, 'muted': muted ?? false};
  }
}

class FakeRealtimeService implements ChatRealtimeService {
  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final StreamController<Message> _messageUpdateController =
      StreamController<Message>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _statusController =
      StreamController<Map<String, dynamic>>.broadcast();

  int connectCalls = 0;
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<Message> get onMessage => _messageController.stream;

  @override
  Stream<Message> get onMessageUpdated => _messageUpdateController.stream;

  @override
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;

  @override
  Stream<Map<String, dynamic>> get onStatusChange => _statusController.stream;

  @override
  Future<void> connect() async {
    connectCalls += 1;
    _isConnected = true;
  }

  @override
  void disconnect() {
    _isConnected = false;
  }

  @override
  void sendMessage(Map<String, dynamic> message) {}

  @override
  bool sendTextMessage(
    int chatRoomId,
    String content, {
    bool isAnonymous = false,
    String? replyToId,
  }) =>
      false;

  @override
  void sendTyping(int chatRoomId, bool isTyping) {}

  void emitMessage(Message message) {
    _messageController.add(message);
  }

  void emitMessageUpdate(Message message) {
    _messageUpdateController.add(message);
  }

  void emitStatus(Map<String, dynamic> status) {
    _statusController.add(status);
  }
}
