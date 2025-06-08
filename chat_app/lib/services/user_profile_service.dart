import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../models/user.dart';

class UserProfileService {
  /// 获取用户资料
  static Future<User> getProfile(String token) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return User.fromJson(data['data']);
      } else {
        throw Exception(data['message'] ?? '获取用户资料失败');
      }
    } else {
      throw Exception('获取用户资料失败: ${response.statusCode}');
    }
  }

  /// 更新用户资料
  static Future<User> updateProfile(String token, UserProfileUpdateRequest request) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(request.toJson()),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return User.fromJson(data['data']);
      } else {
        throw Exception(data['message'] ?? '更新用户资料失败');
      }
    } else {
      throw Exception('更新用户资料失败: ${response.statusCode}');
    }
  }

  /// 上传头像
  static Future<String> uploadAvatar(String token, File avatarFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConstants.baseUrl}/profile/avatar'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('avatar', avatarFile.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return data['data']['avatarUrl'];
      } else {
        throw Exception(data['message'] ?? '头像上传失败');
      }
    } else {
      throw Exception('头像上传失败: ${response.statusCode}');
    }
  }

  /// 删除头像
  static Future<void> deleteAvatar(String token) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/profile/avatar'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (!data['success']) {
        throw Exception(data['message'] ?? '删除头像失败');
      }
    } else {
      throw Exception('删除头像失败: ${response.statusCode}');
    }
  }

  /// 更新在线状态
  static Future<OnlineStatus> updateOnlineStatus(String token, OnlineStatus status) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/profile/status?status=${status.name.toUpperCase()}'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return OnlineStatus.values.firstWhere(
          (e) => e.name.toUpperCase() == data['data']['onlineStatus'].toString().toUpperCase(),
          orElse: () => OnlineStatus.offline,
        );
      } else {
        throw Exception(data['message'] ?? '更新状态失败');
      }
    } else {
      throw Exception('更新状态失败: ${response.statusCode}');
    }
  }

  /// 搜索用户
  static Future<List<User>> searchUsers(String keyword, {int limit = 10}) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/profile/search?keyword=$keyword&limit=$limit'),
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success']) {
        return (data['data'] as List)
            .map((userJson) => User.fromJson(userJson))
            .toList();
      } else {
        throw Exception(data['message'] ?? '搜索用户失败');
      }
    } else {
      throw Exception('搜索用户失败: ${response.statusCode}');
    }
  }

  /// 发送心跳（更新最后在线时间）
  static Future<void> sendHeartbeat(String token) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/profile/heartbeat'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (!data['success']) {
        throw Exception(data['message'] ?? '心跳更新失败');
      }
    } else {
      throw Exception('心跳更新失败: ${response.statusCode}');
    }
  }
}

/// 用户资料更新请求模型
class UserProfileUpdateRequest {
  final String? displayName;
  final String? email;
  final String? phone;
  final String? bio;
  final String? onlineStatus;

  UserProfileUpdateRequest({
    this.displayName,
    this.email,
    this.phone,
    this.bio,
    this.onlineStatus,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (displayName != null) json['displayName'] = displayName;
    if (email != null) json['email'] = email;
    if (phone != null) json['phone'] = phone;
    if (bio != null) json['bio'] = bio;
    if (onlineStatus != null) json['onlineStatus'] = onlineStatus;
    return json;
  }
} 