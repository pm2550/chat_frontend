class ApiConstants {
  // Base URLs configurable at build time via --dart-define.
  // Example:
  //   flutter build web --dart-define=API_BASE_URL=https://chat.example.com \
  //                     --dart-define=WS_BASE_URL=wss://chat.example.com
  // Defaults match the local dev backend on port 18080.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:18080',
  );
  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://localhost:18080',
  );
  static const String webAppUrl = String.fromEnvironment(
    'WEB_APP_URL',
    defaultValue: baseUrl,
  );
  static const String webrtcIceServersRaw = String.fromEnvironment(
    'WEBRTC_ICE_SERVERS',
    defaultValue: 'stun:stun.l.google.com:19302',
  );
  static const String webrtcTurnUsername = String.fromEnvironment(
    'WEBRTC_TURN_USERNAME',
    defaultValue: '',
  );
  static const String webrtcTurnCredential = String.fromEnvironment(
    'WEBRTC_TURN_CREDENTIAL',
    defaultValue: '',
  );
  static List<String> get webrtcIceServers => webrtcIceServersRaw
      .split(',')
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
  static bool get hasWebrtcTurnCredentials =>
      webrtcTurnUsername.isNotEmpty && webrtcTurnCredential.isNotEmpty;

  static const String apiPrefix = '/api';
  static const String apiVersion = '/v1';
  static const String apiBaseUrl = '$baseUrl$apiPrefix$apiVersion';
  static const String authBaseUrl = '$baseUrl$apiPrefix/auth';

  // WebSocket
  static const String wsEndpoint = '$wsBaseUrl$apiPrefix/ws';

  // Auth endpoints
  static const String login = '$authBaseUrl/login';
  static const String register = '$authBaseUrl/register';
  static const String logout = '$authBaseUrl/logout';
  static const String refreshToken = '$authBaseUrl/refresh';
  static const String validateToken = '$authBaseUrl/validate';
  static const String checkUsername = '$authBaseUrl/check-username';

  // User endpoints
  static const String profileBaseUrl = '$baseUrl$apiPrefix/profile';
  static const String profile = profileBaseUrl;
  static const String profileAvatar = '$profileBaseUrl/avatar';
  static const String profileHeartbeat = '$profileBaseUrl/heartbeat';
  static const String profileSettings = '$profileBaseUrl/settings';
  static const String profilePassword = '$profileBaseUrl/password';
  static String profileStatus(String status) =>
      '$profileBaseUrl/status?status=$status';

  static const String userProfile = profile;
  static const String searchUsers = '$apiBaseUrl/users/search';
  static const String profileSearch = '$profileBaseUrl/search';
  static String getUserById(int id) => '$apiBaseUrl/users/$id';
  static String uploadAvatar(int id) => '$apiBaseUrl/users/$id/avatar';

  // Chat room endpoints
  static const String chatRooms = '$apiBaseUrl/chat-rooms';
  static String createPrivateChat(int friendId) =>
      '$apiBaseUrl/chat-rooms/private/$friendId';
  static const String createGroupChat = '$apiBaseUrl/chat-rooms/group';
  static String chatRoomDetail(int roomId) => '$apiBaseUrl/chat-rooms/$roomId';
  static String chatRoomMembers(int roomId) =>
      '$apiBaseUrl/chat-rooms/$roomId/members';
  static String addChatRoomMember(int roomId, int userId) =>
      '$apiBaseUrl/chat-rooms/$roomId/members/$userId';
  static String kickChatRoomMember(int roomId, int userId) =>
      '$apiBaseUrl/chat-rooms/$roomId/members/$userId/kick';
  static String toggleChatRoomAdmin(int roomId, int userId) =>
      '$apiBaseUrl/chat-rooms/$roomId/members/$userId/toggle-admin';
  static String toggleChatRoomMute(int roomId, int userId) =>
      '$apiBaseUrl/chat-rooms/$roomId/members/$userId/toggle-mute';
  static String joinChatRoom(int roomId) =>
      '$apiBaseUrl/chat-rooms/$roomId/join';
  static String leaveChatRoom(int roomId) =>
      '$apiBaseUrl/chat-rooms/$roomId/leave';
  static String chatRoomNotificationSettings(int roomId) =>
      '$apiBaseUrl/chat-rooms/$roomId/notification-settings';
  static const String searchChatRooms = '$apiBaseUrl/chat-rooms/search';

  // Message endpoints
  static const String sendMessage = '$apiBaseUrl/messages';
  static const String sendFileMessage = '$apiBaseUrl/messages/file';
  static String chatRoomMessages(int roomId) =>
      '$apiBaseUrl/messages/chat-room/$roomId';
  static String recentMessages(int roomId) =>
      '$apiBaseUrl/messages/chat-room/$roomId/recent';
  static String chatRoomFiles(int roomId) =>
      '$apiBaseUrl/messages/chat-room/$roomId/files';
  static String markMessageRead(int messageId) =>
      '$apiBaseUrl/messages/$messageId/read';
  static String markAllRead(int roomId) =>
      '$apiBaseUrl/messages/chat-room/$roomId/read-all';
  static String clearChatHistory(int roomId) =>
      '$apiBaseUrl/messages/chat-room/$roomId/clear';
  static String recallMessage(int messageId) =>
      '$apiBaseUrl/messages/$messageId/recall';
  static String deleteMessage(int messageId) =>
      '$apiBaseUrl/messages/$messageId';
  static const String searchMessages = '$apiBaseUrl/messages/search';
  static const String unreadCount = '$apiBaseUrl/messages/unread-count';

  // File endpoints
  static const String filesBaseUrl = '$baseUrl$apiPrefix/files';
  static const String uploadFile = sendFileMessage;
  static String resolveFileUrl(String fileUrl) =>
      fileUrl.startsWith('http') ? fileUrl : '$baseUrl$fileUrl';
  static bool isAbsoluteHttpUrl(String fileUrl) =>
      fileUrl.startsWith(RegExp(r'https?://', caseSensitive: false));
  static bool requiresAuthHeaderForFile(String fileUrl) =>
      resolveFileUrl(fileUrl).startsWith(baseUrl);

  // Friendship endpoints
  static const String friends = '$apiBaseUrl/friends';
  static const String receivedFriendRequests = '$friends/requests/received';
  static const String sentFriendRequests = '$friends/requests/sent';
  static const String friendStats = '$friends/stats';
  static String sendFriendRequest(int userId) => '$friends/request/$userId';
  static String acceptFriendRequest(int userId) => '$friends/accept/$userId';
  static String declineFriendRequest(int userId) => '$friends/decline/$userId';
  static String removeFriend(int userId) => '$friends/$userId';
  static String blockUser(int userId) => '$friends/block/$userId';
  static String unblockUser(int userId) => '$friends/unblock/$userId';
  static String setFriendAlias(int userId) => '$friends/$userId/alias';
  static String togglePinFriend(int userId) => '$friends/$userId/pin';
  static String checkFriendship(int userId) => '$friends/check/$userId';
  static String searchFriends(String keyword) =>
      '$friends/search?keyword=$keyword';

  // Key exchange (E2EE)
  static const String uploadKeys = '$apiBaseUrl/keys/upload';
  static String getKeyBundle(int userId) => '$apiBaseUrl/keys/bundle/$userId';
  static String keyExists(int userId) => '$apiBaseUrl/keys/exists/$userId';
  static const String deleteMyKeys = '$apiBaseUrl/keys/my-keys';

  // Anonymous chat
  static String enterAnonymous(int roomId) =>
      '$apiBaseUrl/chat-rooms/$roomId/anonymous/enter';
  static String renameAnonymous(int roomId) =>
      '$apiBaseUrl/chat-rooms/$roomId/anonymous/rename';
  static String toggleAnonymous(int roomId) =>
      '$apiBaseUrl/chat-rooms/$roomId/anonymous/toggle';

  // Bot endpoints
  static const String createBot = '$apiBaseUrl/bots';
  static const String myBots = '$apiBaseUrl/bots/my';
  static String botDetail(int botId) => '$apiBaseUrl/bots/$botId';
  static String addBotToRoom(int roomId, int botId) =>
      '$apiBaseUrl/bots/chat-rooms/$roomId/bots/$botId/add';
  static String removeBotFromRoom(int roomId, int botId) =>
      '$apiBaseUrl/bots/chat-rooms/$roomId/bots/$botId';
  static String botsInRoom(int roomId) =>
      '$apiBaseUrl/bots/chat-rooms/$roomId/bots';

  // Agent workflow endpoints
  static const String agentTasks = '$apiBaseUrl/agent-tasks';

  // Call / WebRTC endpoints
  static const String callIceServers = '$apiBaseUrl/calls/ice-servers';

  // Workspace file library
  static const String workspaces = '$apiBaseUrl/workspaces';
  static String workspaceDetail(int workspaceId) => '$workspaces/$workspaceId';
  static String workspaceLock(int workspaceId) =>
      '$workspaces/$workspaceId/lock';
  static String workspaceMembers(int workspaceId) =>
      '$workspaces/$workspaceId/members';
  static String workspacePermissions(int workspaceId) =>
      '$workspaces/$workspaceId/permissions';
  static String workspacePermissionDetail(int workspaceId, int permissionId) =>
      '$workspaces/$workspaceId/permissions/$permissionId';
  static String workspaceContents(int workspaceId) =>
      '$workspaces/$workspaceId/contents';
  static String workspaceFolders(int workspaceId) =>
      '$workspaces/$workspaceId/folders';
  static String workspaceFolderLock(int workspaceId, int folderId) =>
      '$workspaces/$workspaceId/folders/$folderId/lock';
  static String workspaceFolderDetail(int workspaceId, int folderId) =>
      '$workspaces/$workspaceId/folders/$folderId';
  static String workspaceFolderRestore(int workspaceId, int folderId) =>
      '$workspaces/$workspaceId/folders/$folderId/restore';
  static String workspaceFiles(int workspaceId) =>
      '$workspaces/$workspaceId/files';
  static String workspaceFileDetail(int workspaceId, int fileId) =>
      '$workspaces/$workspaceId/files/$fileId';
  static String workspaceFileDownload(int workspaceId, int fileId) =>
      '$workspaces/$workspaceId/files/$fileId/download';
  static String workspaceFilePreview(int workspaceId, int fileId) =>
      '$workspaces/$workspaceId/files/$fileId/preview';
  static String workspaceFileVersions(int workspaceId, int fileId) =>
      '$workspaces/$workspaceId/files/$fileId/versions';
  static String workspaceFileVersionRestore(
          int workspaceId, int fileId, int versionNumber) =>
      '$workspaces/$workspaceId/files/$fileId/versions/$versionNumber/restore';
  static String workspaceFileLock(int workspaceId, int fileId) =>
      '$workspaces/$workspaceId/files/$fileId/lock';
  static String workspaceFileRestore(int workspaceId, int fileId) =>
      '$workspaces/$workspaceId/files/$fileId/restore';
  static String workspaceTrash(int workspaceId) =>
      '$workspaces/$workspaceId/trash';
  static String workspaceOrphanMaintenance(int workspaceId) =>
      '$workspaces/$workspaceId/maintenance/orphans';

  // Admin
  static const String auditLogs = '$apiBaseUrl/admin/audit-logs';

  // Device token (push notifications)
  static const String registerDevice = '$apiBaseUrl/device-tokens/register';
  static const String unregisterDevice = '$apiBaseUrl/device-tokens/unregister';

  // App version / OTA update
  static const String appVersionCheck = '$apiBaseUrl/app/version';
  static String appDownload(String platform, String filename) =>
      '$apiBaseUrl/app/download/$platform/$filename';

  // Timeouts
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);
}
