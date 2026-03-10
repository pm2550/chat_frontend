class ApiConstants {
  // Base URLs - configurable per environment
  static const String baseUrl = 'http://localhost:8080';
  static const String apiPrefix = '/api';
  static const String apiVersion = '/v1';
  static const String apiBaseUrl = '$baseUrl$apiPrefix$apiVersion';
  static const String authBaseUrl = '$baseUrl$apiPrefix/auth';

  // WebSocket
  static const String wsBaseUrl = 'ws://localhost:8080';
  static const String wsEndpoint = '$wsBaseUrl$apiPrefix/ws';

  // Auth endpoints
  static const String login = '$authBaseUrl/login';
  static const String register = '$authBaseUrl/register';
  static const String logout = '$authBaseUrl/logout';
  static const String refreshToken = '$authBaseUrl/refresh';
  static const String validateToken = '$authBaseUrl/validate';
  static const String checkUsername = '$authBaseUrl/check-username';

  // User endpoints
  static const String userProfile = '$apiBaseUrl/users/profile';
  static const String searchUsers = '$apiBaseUrl/users/search';
  static String getUserById(int id) => '$apiBaseUrl/users/$id';
  static String uploadAvatar(int id) => '$apiBaseUrl/users/$id/avatar';

  // Chat room endpoints
  static const String chatRooms = '$apiBaseUrl/chat-rooms';
  static String createPrivateChat(int friendId) => '$apiBaseUrl/chat-rooms/private/$friendId';
  static const String createGroupChat = '$apiBaseUrl/chat-rooms/group';
  static String chatRoomDetail(int roomId) => '$apiBaseUrl/chat-rooms/$roomId';
  static String chatRoomMembers(int roomId) => '$apiBaseUrl/chat-rooms/$roomId/members';
  static String joinChatRoom(int roomId) => '$apiBaseUrl/chat-rooms/$roomId/join';
  static String leaveChatRoom(int roomId) => '$apiBaseUrl/chat-rooms/$roomId/leave';
  static const String searchChatRooms = '$apiBaseUrl/chat-rooms/search';

  // Message endpoints
  static const String sendMessage = '$apiBaseUrl/messages';
  static String chatRoomMessages(int roomId) => '$apiBaseUrl/messages/chat-room/$roomId';
  static String recentMessages(int roomId) => '$apiBaseUrl/messages/chat-room/$roomId/recent';
  static String markMessageRead(int messageId) => '$apiBaseUrl/messages/$messageId/read';
  static String markAllRead(int roomId) => '$apiBaseUrl/messages/chat-room/$roomId/read-all';
  static String recallMessage(int messageId) => '$apiBaseUrl/messages/$messageId/recall';
  static String deleteMessage(int messageId) => '$apiBaseUrl/messages/$messageId';
  static const String searchMessages = '$apiBaseUrl/messages/search';
  static const String unreadCount = '$apiBaseUrl/messages/unread-count';

  // File endpoints
  static const String uploadFile = '$apiBaseUrl/files/upload';
  static String downloadFile(int fileId) => '$apiBaseUrl/files/$fileId';

  // Friendship endpoints
  static const String friendships = '$apiBaseUrl/friendships';
  static String sendFriendRequest(int userId) => '$apiBaseUrl/friendships/$userId/request';
  static String acceptFriend(int userId) => '$apiBaseUrl/friendships/$userId/accept';
  static String declineFriend(int userId) => '$apiBaseUrl/friendships/$userId/decline';
  static String removeFriend(int userId) => '$apiBaseUrl/friendships/$userId';
  static String blockUser(int userId) => '$apiBaseUrl/friendships/$userId/block';
  static const String pendingRequests = '$apiBaseUrl/friendships/pending';

  // Key exchange (E2EE)
  static const String uploadKeys = '$apiBaseUrl/keys/upload';
  static String getKeyBundle(int userId) => '$apiBaseUrl/keys/bundle/$userId';
  static String keyExists(int userId) => '$apiBaseUrl/keys/exists/$userId';
  static const String deleteMyKeys = '$apiBaseUrl/keys/my-keys';

  // Anonymous chat
  static String enterAnonymous(int roomId) => '$apiBaseUrl/chat-rooms/$roomId/anonymous/enter';
  static String renameAnonymous(int roomId) => '$apiBaseUrl/chat-rooms/$roomId/anonymous/rename';
  static String toggleAnonymous(int roomId) => '$apiBaseUrl/chat-rooms/$roomId/anonymous/toggle';

  // Bot endpoints
  static const String createBot = '$apiBaseUrl/bots';
  static const String myBots = '$apiBaseUrl/bots/my';
  static String botDetail(int botId) => '$apiBaseUrl/bots/$botId';
  static String addBotToRoom(int roomId, int botId) => '$apiBaseUrl/bots/chat-rooms/$roomId/bots/$botId/add';
  static String removeBotFromRoom(int roomId, int botId) => '$apiBaseUrl/bots/chat-rooms/$roomId/bots/$botId';
  static String botsInRoom(int roomId) => '$apiBaseUrl/bots/chat-rooms/$roomId/bots';

  // Device token (push notifications)
  static const String registerDevice = '$apiBaseUrl/device-tokens/register';
  static const String unregisterDevice = '$apiBaseUrl/device-tokens/unregister';

  // Timeouts
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);
}
