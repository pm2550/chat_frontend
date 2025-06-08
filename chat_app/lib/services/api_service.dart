import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../models/user.dart';
import '../models/chat.dart';
import '../models/message.dart';

class ApiService {
  static const Duration timeoutDuration = Duration(seconds: 30);
  String? _authToken;

  // 设置认证令牌
  void setAuthToken(String token) {
    _authToken = token;
  }

  // 清除认证令牌
  void clearAuthToken() {
    _authToken = null;
  }

  // 获取请求头
  Map<String, String> _getHeaders({bool includeAuth = true}) {
    Map<String, String> headers = Map.from(ApiConstants.defaultHeaders);
    if (includeAuth && _authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  // 处理HTTP响应
  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return {'success': true};
      }
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      throw HttpException('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  // 认证相关API
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.login}'),
      headers: _getHeaders(includeAuth: false),
      body: json.encode({
        'username': username,
        'password': password,
      }),
    ).timeout(timeoutDuration);

    final result = _handleResponse(response);
    if (result['token'] != null) {
      setAuthToken(result['token']);
    }
    return result;
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> userData) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.register}'),
      headers: _getHeaders(includeAuth: false),
      body: json.encode(userData),
    ).timeout(timeoutDuration);

    return _handleResponse(response);
  }

  Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.logout}'),
        headers: _getHeaders(),
      ).timeout(timeoutDuration);
    } finally {
      clearAuthToken();
    }
  }

  // 用户相关API
  Future<User> getCurrentUser() async {
    final response = await http.get(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.userProfile}'),
      headers: _getHeaders(),
    ).timeout(timeoutDuration);

    final result = _handleResponse(response);
    return User.fromJson(result['data'] ?? result);
  }

  Future<User> updateProfile(Map<String, dynamic> userData) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.updateProfile}'),
      headers: _getHeaders(),
      body: json.encode(userData),
    ).timeout(timeoutDuration);

    final result = _handleResponse(response);
    return User.fromJson(result['data'] ?? result);
  }

  Future<List<User>> searchUsers(String query) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.searchUsers}?q=$query'),
      headers: _getHeaders(),
    ).timeout(timeoutDuration);

    final result = _handleResponse(response);
    final List<dynamic> userList = result['data'] ?? result;
    return userList.map((json) => User.fromJson(json)).toList();
  }

  // 聊天室相关API
  Future<List<Chat>> getChatRooms() async {
    final response = await http.get(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.chatRooms}'),
      headers: _getHeaders(),
    ).timeout(timeoutDuration);

    final result = _handleResponse(response);
    final List<dynamic> chatList = result['data'] ?? result;
    return chatList.map((json) => Chat.fromJson(json)).toList();
  }

  Future<Chat> createChatRoom(Map<String, dynamic> chatRoomData) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.createChatRoom}'),
      headers: _getHeaders(),
      body: json.encode(chatRoomData),
    ).timeout(timeoutDuration);

    final result = _handleResponse(response);
    return Chat.fromJson(result['data'] ?? result);
  }

  Future<void> joinChatRoom(String chatRoomId) async {
    await http.post(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.joinChatRoom}/$chatRoomId/join'),
      headers: _getHeaders(),
    ).timeout(timeoutDuration);
  }

  Future<void> leaveChatRoom(String chatRoomId) async {
    await http.post(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.leaveChatRoom}/$chatRoomId/leave'),
      headers: _getHeaders(),
    ).timeout(timeoutDuration);
  }

  // 消息相关API
  Future<List<Message>> getChatRoomMessages(String chatRoomId, {int page = 0, int size = 50}) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.getChatRoomMessages}/$chatRoomId?page=$page&size=$size'),
      headers: _getHeaders(),
    ).timeout(timeoutDuration);

    final result = _handleResponse(response);
    final List<dynamic> messageList = result['data'] ?? result['content'] ?? result;
    return messageList.map((json) => Message.fromJson(json)).toList();
  }

  Future<Message> sendMessage(Map<String, dynamic> messageData) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.sendMessage}'),
      headers: _getHeaders(),
      body: json.encode(messageData),
    ).timeout(timeoutDuration);

    final result = _handleResponse(response);
    return Message.fromJson(result['data'] ?? result);
  }

  Future<void> markMessageAsRead(String messageId) async {
    await http.post(
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.markAsRead}/$messageId/read'),
      headers: _getHeaders(),
    ).timeout(timeoutDuration);
  }

  // 文件上传API
  Future<String> uploadFile(File file, {String type = 'file'}) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.uploadFile}'),
    );

    request.headers.addAll(_getHeaders());
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    request.fields['type'] = type;

    final streamedResponse = await request.send().timeout(timeoutDuration);
    final response = await http.Response.fromStream(streamedResponse);

    final result = _handleResponse(response);
    return result['data']['url'] ?? result['url'];
  }
} 