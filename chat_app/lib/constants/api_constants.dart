class ApiConstants {
  // 基础URL配置
  static const String baseUrl = 'http://localhost:8080';
  static const String apiVersion = '/api/v1';
  static const String apiBaseUrl = '$baseUrl$apiVersion';
  
  // 认证相关
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';
  
  // 用户相关
  static const String userProfile = '/users/profile';
  static const String updateProfile = '/users/profile';
  static const String getUserById = '/users'; // /users/{id}
  static const String searchUsers = '/users/search';
  
  // 聊天室相关
  static const String chatRooms = '/chat-rooms';
  static const String createChatRoom = '/chat-rooms';
  static const String joinChatRoom = '/chat-rooms'; // /chat-rooms/{id}/join
  static const String leaveChatRoom = '/chat-rooms'; // /chat-rooms/{id}/leave
  static const String getChatRoomMembers = '/chat-rooms'; // /chat-rooms/{id}/members
  
  // 消息相关
  static const String messages = '/messages';
  static const String sendMessage = '/messages';
  static const String getChatRoomMessages = '/messages/chat-room'; // /messages/chat-room/{chatRoomId}
  static const String markAsRead = '/messages'; // /messages/{id}/read
  
  // 文件上传
  static const String uploadFile = '/files/upload';
  static const String uploadImage = '/files/upload/image';
  
  // WebSocket
  static const String wsBaseUrl = 'ws://localhost:8080';
  static const String chatWebSocket = '$wsBaseUrl/ws/chat';
  
  // 请求头
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  
  // 获取带认证头的请求头
  static Map<String, String> getAuthHeaders(String token) {
    return {
      ...defaultHeaders,
      'Authorization': 'Bearer $token',
    };
  }
} 