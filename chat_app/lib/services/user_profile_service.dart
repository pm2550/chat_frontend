import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/chat_customization.dart';
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

typedef ProfileBackgroundMultipartRequest = Future<dynamic> Function(
  String url, {
  required PickedChatBackground background,
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

class PickedChatBackground {
  const PickedChatBackground({
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
    this.chatBackgroundPreset = ChatCustomizationCatalog.defaultBackground,
    this.chatBackgroundCustomUrl,
    this.avatarFramePreset = ChatCustomizationCatalog.defaultAvatarFrame,
    this.bubbleStylePreset = ChatCustomizationCatalog.defaultBubbleStyle,
  });

  final bool messageNotificationsEnabled;
  final bool showOnlineStatus;
  final bool allowFriendRequests;
  final bool allowDirectMessages;
  final bool readReceiptsEnabled;
  final String chatBackgroundPreset;
  final String? chatBackgroundCustomUrl;
  final String avatarFramePreset;
  final String bubbleStylePreset;

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
      chatBackgroundPreset: _parsePreset(
        json['chatBackgroundPreset'] ?? json['chat_background_preset'],
        ChatCustomizationCatalog.defaultBackground,
        ChatCustomizationCatalog.isValidBackground,
      ),
      chatBackgroundCustomUrl: _parseNullableString(
          json['chatBackgroundCustomUrl'] ??
              json['chat_background_custom_url']),
      avatarFramePreset: _parsePreset(
        json['avatarFramePreset'] ?? json['avatar_frame_preset'],
        ChatCustomizationCatalog.defaultAvatarFrame,
        ChatCustomizationCatalog.isValidAvatarFrame,
      ),
      bubbleStylePreset: _parsePreset(
        json['bubbleStylePreset'] ?? json['bubble_style_preset'],
        ChatCustomizationCatalog.defaultBubbleStyle,
        ChatCustomizationCatalog.isValidBubbleStyle,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageNotificationsEnabled': messageNotificationsEnabled,
      'showOnlineStatus': showOnlineStatus,
      'allowFriendRequests': allowFriendRequests,
      'allowDirectMessages': allowDirectMessages,
      'readReceiptsEnabled': readReceiptsEnabled,
      'chatBackgroundPreset': chatBackgroundPreset,
      'chatBackgroundCustomUrl': chatBackgroundCustomUrl,
      'avatarFramePreset': avatarFramePreset,
      'bubbleStylePreset': bubbleStylePreset,
    };
  }

  UserAppSettings copyWith({
    bool? messageNotificationsEnabled,
    bool? showOnlineStatus,
    bool? allowFriendRequests,
    bool? allowDirectMessages,
    bool? readReceiptsEnabled,
    String? chatBackgroundPreset,
    String? chatBackgroundCustomUrl,
    bool clearChatBackgroundCustomUrl = false,
    String? avatarFramePreset,
    String? bubbleStylePreset,
  }) {
    return UserAppSettings(
      messageNotificationsEnabled:
          messageNotificationsEnabled ?? this.messageNotificationsEnabled,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      allowFriendRequests: allowFriendRequests ?? this.allowFriendRequests,
      allowDirectMessages: allowDirectMessages ?? this.allowDirectMessages,
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
      chatBackgroundPreset: chatBackgroundPreset ?? this.chatBackgroundPreset,
      chatBackgroundCustomUrl: clearChatBackgroundCustomUrl
          ? null
          : chatBackgroundCustomUrl ?? this.chatBackgroundCustomUrl,
      avatarFramePreset: avatarFramePreset ?? this.avatarFramePreset,
      bubbleStylePreset: bubbleStylePreset ?? this.bubbleStylePreset,
    );
  }

  static bool _parseBool(dynamic value, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  static String _parsePreset(
    dynamic value,
    String fallback,
    bool Function(String?) isValid,
  ) {
    final preset = value?.toString();
    return isValid(preset) ? preset! : fallback;
  }

  static String? _parseNullableString(dynamic value) {
    final string = value?.toString().trim();
    return string == null || string.isEmpty ? null : string;
  }
}

class UserProfileService {
  UserProfileService({
    AuthService? authService,
    ProfileAuthenticatedRequest? authenticatedRequest,
    ProfileMultipartRequest? multipartRequest,
    ProfileBackgroundMultipartRequest? backgroundMultipartRequest,
  })  : _authService = authService ?? AuthService(),
        _authenticatedRequest = authenticatedRequest,
        _multipartRequest = multipartRequest,
        _backgroundMultipartRequest = backgroundMultipartRequest;

  final AuthService _authService;
  final ProfileAuthenticatedRequest? _authenticatedRequest;
  final ProfileMultipartRequest? _multipartRequest;
  final ProfileBackgroundMultipartRequest? _backgroundMultipartRequest;

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

  Future<UserAppSettings> uploadChatBackground(
    PickedChatBackground background,
  ) async {
    final response = await _requestBackgroundMultipart(
      ApiConstants.profileChatBackground,
      background: background,
    );
    return _extractSettings(_decodeResponse(response));
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
        avatarFramePreset: currentUser.avatarFramePreset,
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
    final saved = _extractSettings(_decodeResponse(response));
    final currentUser = _authService.currentUser;
    if (currentUser != null) {
      await _authService.replaceCurrentUser(currentUser.copyWith(
        avatarFramePreset: saved.avatarFramePreset,
      ));
    }
    return saved;
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

  Future<dynamic> _requestBackgroundMultipart(
    String url, {
    required PickedChatBackground background,
  }) async {
    if (_backgroundMultipartRequest != null) {
      return _backgroundMultipartRequest(url, background: background);
    }

    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      final token = _authService.accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final bytes = background.bytes;
      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'background',
          bytes,
          filename: background.name,
        ));
      } else if (background.path != null && background.path!.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath(
          'background',
          background.path!,
          filename: background.name,
        ));
      } else {
        throw const UserProfileException('请选择有效聊天背景');
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
