import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';

class ChatHistoryService {
  final String? authToken;

  ChatHistoryService({this.authToken});

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (authToken != null) 'Authorization': 'Bearer $authToken',
  };

  /// 获取私聊历史记录
  Future<Map<String, dynamic>> getPrivateChatHistory(
      int userId, {int page = 0, int size = 20}) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/api/chat-history/private?userId=$userId&page=$page&size=$size'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取私聊记录失败: ${response.statusCode}');
  }

  /// 获取群聊历史记录
  Future<Map<String, dynamic>> getGroupChatHistory(
      int chatRoomId, {int page = 0, int size = 20}) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/api/chat-history/group?chatRoomId=$chatRoomId&page=$page&size=$size'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取群聊记录失败: ${response.statusCode}');
  }

  /// 搜索私聊消息
  Future<Map<String, dynamic>> searchPrivateMessages(
      int userId, String keyword, {int page = 0, int size = 20}) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/api/chat-history/private/search?userId=$userId&keyword=$keyword&page=$page&size=$size'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('搜索消息失败: ${response.statusCode}');
  }

  /// 搜索群聊消息
  Future<Map<String, dynamic>> searchGroupMessages(
      int chatRoomId, String keyword, {int page = 0, int size = 20}) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/api/chat-history/group/search?chatRoomId=$chatRoomId&keyword=$keyword&page=$page&size=$size'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('搜索消息失败: ${response.statusCode}');
  }

  /// 撤回消息
  Future<Map<String, dynamic>> recallMessage(int messageId) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/api/chat-history/recall/$messageId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('撤回消息失败: ${response.statusCode}');
  }

  /// 删除消息
  Future<void> deleteMessage(int messageId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/api/chat-history/$messageId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('删除消息失败: ${response.statusCode}');
    }
  }
}
