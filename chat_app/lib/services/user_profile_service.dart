import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/user.dart';
import 'auth_service.dart';

typedef ProfileAuthenticatedRequest = Future<dynamic> Function(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
});

typedef ProfileMultipartRequest = Future<dynamic> Function(
  String url, {
  required PickedProfileAvatar avatar,
});

class PickedProfileAvatar {
  const PickedProfileAvatar({
    required this.name,
    required this.size,
    this.path,
    this.mimeType,
    this.bytes,
  });

  final String name;
  final int size;
  final String? path;
  final String? mimeType;
  final List<int>? bytes;
}

class UserProfileException implements Exception {
  const UserProfileException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UserAppSettings {
  const UserAppSettings({
    this.messageNotificationsEnabled = true,
    this.showOnlineStatus = true,
    this.allowFriendRequests = true,
    this.allowDirectMessages = true,
    this.readReceiptsEnabled = true,
  });

  final bool messageNotificationsEnabled;
  final bool showOnlineStatus;
  final bool allowFriendRequests;
  final bool allowDirectMessages;
  final bool readReceiptsEnabled;

  factory UserAppSettings.fromJson(Map<String, dynamic> json) {
    return UserAppSettings(
      messageNotificationsEnabled: _parseBool(
          json['messageNotificationsEnabled'] ??
              json['message_notifications_enabled'],
          true),
      showOnlineStatus: _parseBool(
          json['showOnlineStatus'] ?? json['show_online_status'], true),
      allowFriendRequests: _parseBool(
          json['allowFriendRequests'] ?? json['allow_friend_requests'], true),
      allowDirectMessages: _parseBool(
          json['allowDirectMessages'] ?? json['allow_direct_messages'], true),
      readReceiptsEnabled: _parseBool(
          json['readReceiptsEnabled'] ?? json['read_receipts_enabled'], true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageNotificationsEnabled': messageNotificationsEnabled,
      'showOnlineStatus': showOnlineStatus,
      'allowFriendRequests': allowFriendRequests,
      'allowDirectMessages': allowDirectMessages,
      'readReceiptsEnabled': readReceiptsEnabled,
    };
  }

  UserAppSettings copyWith({
    bool? messageNotificationsEnabled,
    bool? showOnlineStatus,
    bool? allowFriendRequests,
    bool? allowDirectMessages,
    bool? readReceiptsEnabled,
  }) {
    return UserAppSettings(
      messageNotificationsEnabled:
          messageNotificationsEnabled ?? this.messageNotificationsEnabled,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      allowFriendRequests: allowFriendRequests ?? this.allowFriendRequests,
      allowDirectMessages: allowDirectMessages ?? this.allowDirectMessages,
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
    );
  }

  static bool _parseBool(dynamic value, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }
}

class UserProfileService {
  UserProfileService({
    AuthService? authService,
    ProfileAuthenticatedRequest? authenticatedRequest,
    ProfileMultipartRequest? multipartRequest,
  })  : _authService = authService ?? AuthService(),
        _authenticatedRequest = authenticatedRequest,
        _multipartRequest = multipartRequest;

  final AuthService _authService;
  final ProfileAuthenticatedRequest? _authenticatedRequest;
  final ProfileMultipartRequest? _multipartRequest;

  Future<User> getProfile() async {
    final response = await _request('GET', ApiConstants.profile);
    final user = _extractUser(_decodeResponse(response));
    await _authService.replaceCurrentUser(user);
    return user;
  }

  Future<User> updateProfile(UserProfileUpdateRequest request) async {
    final response = await _request(
      'PUT',
      ApiConstants.profile,
      body: request.toJson(),
    );
    final user = _extractUser(_decodeResponse(response));
    await _authService.replaceCurrentUser(user);
    return user;
  }

  Future<String> uploadAvatar(PickedProfileAvatar avatar) async {
    final response = await _requestMultipart(
      ApiConstants.profileAvatar,
      avatar: avatar,
    );
    final data = _decodeResponse(response);
    final payload = data['data'];
    final avatarUrl = payload is Map<String, dynamic>
        ? payload['avatarUrl']?.toString()
        : data['avatarUrl']?.toString();
    if (avatarUrl == null || avatarUrl.isEmpty) {
      throw const UserProfileException('头像上传成功但响应中没有头像地址');
    }

    final currentUser = _authService.currentUser;
    if (currentUser != null) {
      await _authService.replaceCurrentUser(currentUser.copyWith(
        avatarUrl: avatarUrl,
      ));
    }
    return avatarUrl;
  }

  Future<void> deleteAvatar() async {
    await _request('DELETE', ApiConstants.profileAvatar);
    final currentUser = _authService.currentUser;
    if (currentUser != null) {
      await _authService.replaceCurrentUser(User(
        id: currentUser.id,
        username: currentUser.username,
        email: currentUser.email,
        phone: currentUser.phone,
        displayName: currentUser.displayName,
        bio: currentUser.bio,
        onlineStatus: currentUser.onlineStatus,
        lastSeen: currentUser.lastSeen,
        isActive: currentUser.isActive,
        createdAt: currentUser.createdAt,
        updatedAt: currentUser.updatedAt,
        roles: currentUser.roles,
      ));
    }
  }

  Future<OnlineStatus> updateOnlineStatus(OnlineStatus status) async {
    final response = await _request(
      'PUT',
      ApiConstants.profileStatus(status.name.toUpperCase()),
    );
    final data = _decodeResponse(response);
    final statusValue = data['data'] is Map<String, dynamic>
        ? data['data']['onlineStatus']?.toString()
        : data['onlineStatus']?.toString();
    final updatedStatus = OnlineStatus.values.firstWhere(
      (value) => value.name.toUpperCase() == statusValue?.toUpperCase(),
      orElse: () => status,
    );

    final currentUser = _authService.currentUser;
    if (currentUser != null) {
      await _authService.replaceCurrentUser(currentUser.copyWith(
        onlineStatus: updatedStatus,
      ));
    }
    return updatedStatus;
  }

  Future<List<User>> searchUsers(String keyword, {int limit = 10}) async {
    final uri = Uri.parse(ApiConstants.profileSearch).replace(
      queryParameters: {
        'keyword': keyword,
        'limit': limit.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final data = _decodeResponse(response);
    return _extractList(data, keys: const ['data', 'users', 'content'])
        .whereType<Map<String, dynamic>>()
        .map(User.fromJson)
        .toList();
  }

  Future<void> sendHeartbeat() async {
    await _request('POST', ApiConstants.profileHeartbeat);
  }

  Future<UserAppSettings> getSettings() async {
    final response = await _request('GET', ApiConstants.profileSettings);
    return _extractSettings(_decodeResponse(response));
  }

  Future<UserAppSettings> updateSettings(UserAppSettings settings) async {
    final response = await _request(
      'PUT',
      ApiConstants.profileSettings,
      body: settings.toJson(),
    );
    return _extractSettings(_decodeResponse(response));
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

  Future<dynamic> _requestMultipart(
    String url, {
    required PickedProfileAvatar avatar,
  }) async {
    if (_multipartRequest != null) {
      return _multipartRequest(url, avatar: avatar);
    }

    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      final token = _authService.accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final bytes = avatar.bytes;
      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'avatar',
          bytes,
          filename: avatar.name,
        ));
      } else if (avatar.path != null && avatar.path!.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath(
          'avatar',
          avatar.path!,
          filename: avatar.name,
        ));
      } else {
        throw const UserProfileException('请选择有效头像');
      }

      final streamedResponse =
          await request.send().timeout(ApiConstants.uploadTimeout);
      return http.Response.fromStream(streamedResponse);
    }

    var response = await send();
    if (response.statusCode == 401 && await _authService.refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  User _extractUser(Map<String, dynamic> data) {
    final payload = data['data'] ?? data['user'];
    if (payload is Map<String, dynamic>) {
      return User.fromJson(payload);
    }
    throw const UserProfileException('响应中没有用户资料');
  }

  UserAppSettings _extractSettings(Map<String, dynamic> data) {
    final payload = data['data'] ?? data['settings'];
    if (payload is Map<String, dynamic>) {
      return UserAppSettings.fromJson(payload);
    }
    throw const UserProfileException('响应中没有用户设置');
  }

  Map<String, dynamic> _decodeResponse(dynamic response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UserProfileException(_extractError(response.body));
    }
    if (response.bodyBytes.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      if (decoded['success'] == false) {
        throw UserProfileException(
          (decoded['message'] ?? decoded['error'] ?? '请求失败').toString(),
        );
      }
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
}

class UserProfileUpdateRequest {
  UserProfileUpdateRequest({
    this.displayName,
    this.email,
    this.phone,
    this.bio,
    this.onlineStatus,
  });

  final String? displayName;
  final String? email;
  final String? phone;
  final String? bio;
  final String? onlineStatus;

  Map<String, dynamic> toJson() {
    return {
      if (displayName != null) 'displayName': displayName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (bio != null) 'bio': bio,
      if (onlineStatus != null) 'onlineStatus': onlineStatus,
    };
  }
}
