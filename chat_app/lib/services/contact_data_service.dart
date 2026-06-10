import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/chat.dart';
import '../models/contact_group.dart';
import '../models/user.dart';
import 'auth_service.dart';

typedef ContactAuthenticatedRequest = Future<http.Response> Function(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
});

class ContactDataException implements Exception {
  const ContactDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FriendshipRequest {
  const FriendshipRequest({
    required this.id,
    required this.status,
    required this.user,
    required this.friend,
    this.statusDescription,
    this.friendAlias,
    this.isBlocked = false,
    this.isPinned = false,
    this.createdAt,
    this.updatedAt,
    this.acceptedAt,
  });

  final String id;
  final String status;
  final String? statusDescription;
  final User user;
  final User friend;
  final String? friendAlias;
  final bool isBlocked;
  final bool isPinned;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? acceptedAt;

  factory FriendshipRequest.fromJson(Map<String, dynamic> json) {
    return FriendshipRequest(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      statusDescription: json['statusDescription']?.toString(),
      user: User.fromJson(_asMap(json['user'])),
      friend: User.fromJson(_asMap(json['friend'])),
      friendAlias:
          json['friendAlias']?.toString() ?? json['friend_alias']?.toString(),
      isBlocked: json['isBlocked'] ?? json['is_blocked'] ?? false,
      isPinned: json['isPinned'] ?? json['is_pinned'] ?? false,
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
      acceptedAt: _parseDate(json['acceptedAt'] ?? json['accepted_at']),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }
}

class ContactDataService {
  ContactDataService({
    AuthService? authService,
    ContactAuthenticatedRequest? authenticatedRequest,
  })  : _authService = authService ?? AuthService(),
        _authenticatedRequest = authenticatedRequest;

  final AuthService _authService;
  final ContactAuthenticatedRequest? _authenticatedRequest;

  Future<List<User>> getFriends() async {
    final response = await _request('GET', ApiConstants.friends);
    final data = _decodeResponse(response);
    return _extractList(data, keys: const ['friends', 'data', 'content'])
        .whereType<Map<String, dynamic>>()
        .map(User.fromJson)
        .toList();
  }

  Future<List<FriendshipRequest>> getReceivedFriendRequests() async {
    final response = await _request('GET', ApiConstants.receivedFriendRequests);
    final data = _decodeResponse(response);
    return _extractList(data, keys: const ['requests', 'data', 'content'])
        .whereType<Map<String, dynamic>>()
        .map(FriendshipRequest.fromJson)
        .toList();
  }

  Future<List<FriendshipRequest>> getSentFriendRequests() async {
    final response = await _request('GET', ApiConstants.sentFriendRequests);
    final data = _decodeResponse(response);
    return _extractList(data, keys: const ['requests', 'data', 'content'])
        .whereType<Map<String, dynamic>>()
        .map(FriendshipRequest.fromJson)
        .toList();
  }

  Future<List<User>> searchUsers(String keyword, {int limit = 20}) async {
    if (keyword.trim().isEmpty) {
      return const [];
    }

    final uri = Uri.parse(ApiConstants.profileSearch).replace(
      queryParameters: {
        'keyword': keyword.trim(),
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

  Future<FriendshipRequest> sendFriendRequest(String userId) async {
    final response = await _request(
      'POST',
      ApiConstants.sendFriendRequest(_parseUserId(userId)),
    );
    return _extractFriendship(_decodeResponse(response));
  }

  Future<FriendshipRequest> acceptFriendRequest(String userId) async {
    final response = await _request(
      'POST',
      ApiConstants.acceptFriendRequest(_parseUserId(userId)),
    );
    return _extractFriendship(_decodeResponse(response));
  }

  Future<void> declineFriendRequest(String userId) async {
    final response = await _request(
      'POST',
      ApiConstants.declineFriendRequest(_parseUserId(userId)),
    );
    _decodeResponse(response);
  }

  Future<void> removeFriend(String userId) async {
    final response = await _request(
      'DELETE',
      ApiConstants.removeFriend(_parseUserId(userId)),
    );
    _decodeResponse(response);
  }

  Future<ContactGroupBundle> getContactGroups() async {
    final response = await _request('GET', ApiConstants.contactGroups);
    return ContactGroupBundle.fromJson(_decodeResponse(response));
  }

  Future<ContactGroup> createContactGroup(String name) async {
    final response = await _request(
      'POST',
      ApiConstants.contactGroups,
      body: {'name': name.trim()},
    );
    final data = _decodeResponse(response);
    return ContactGroup.fromJson(_asStringMap(data['group'] ?? data['data']));
  }

  Future<ContactGroup> updateContactGroup(
    String groupId, {
    required String name,
    int? sortOrder,
  }) async {
    final response = await _request(
      'PUT',
      ApiConstants.contactGroup(_parseUserId(groupId)),
      body: {
        'name': name.trim(),
        if (sortOrder != null) 'sortOrder': sortOrder,
      },
    );
    final data = _decodeResponse(response);
    return ContactGroup.fromJson(_asStringMap(data['group'] ?? data['data']));
  }

  Future<void> deleteContactGroup(String groupId) async {
    final response = await _request(
      'DELETE',
      ApiConstants.contactGroup(_parseUserId(groupId)),
    );
    _decodeResponse(response);
  }

  Future<List<ContactGroup>> reorderContactGroups(List<String> groupIds) async {
    final response = await _request(
      'POST',
      ApiConstants.contactGroupReorder,
      body: {'groupIds': groupIds.map(_parseUserId).toList()},
    );
    final data = _decodeResponse(response);
    return _extractList(data, keys: const ['groups', 'data'])
        .whereType<Map<String, dynamic>>()
        .map(ContactGroup.fromJson)
        .toList();
  }

  Future<ContactGroupAssignment?> assignContactGroupItem({
    required ContactGroupTargetType targetType,
    required String targetId,
    String? groupId,
  }) async {
    final response = await _request(
      'PUT',
      ApiConstants.contactGroupItems,
      body: {
        'targetType': targetType.wireName,
        'targetId': _parseUserId(targetId),
        if (groupId != null) 'groupId': _parseUserId(groupId),
      },
    );
    final data = _decodeResponse(response);
    final assignment = data['assignment'] ?? data['data'];
    if (assignment == null) {
      return null;
    }
    return ContactGroupAssignment.fromJson(_asStringMap(assignment));
  }

  Future<Chat> createPrivateChat(String userId) async {
    final response = await _request(
      'POST',
      ApiConstants.createPrivateChat(_parseUserId(userId)),
    );
    final data = _decodeResponse(response);
    final chatJson = data['chatRoom'] ?? data['data'];
    if (chatJson is! Map<String, dynamic>) {
      throw const ContactDataException('创建私聊成功但响应中没有聊天室数据');
    }
    return Chat.fromJson(chatJson);
  }

  Future<Chat> createGroupChat({
    required String name,
    String? description,
    List<String> memberIds = const [],
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.createGroupChat,
      body: {
        'name': name,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'memberIds': memberIds.map(_parseUserId).toList(),
      },
    );
    final data = _decodeResponse(response);
    final chatJson = data['chatRoom'] ?? data['data'];
    if (chatJson is! Map<String, dynamic>) {
      throw const ContactDataException('创建群聊成功但响应中没有聊天室数据');
    }
    return Chat.fromJson(chatJson);
  }

  Future<http.Response> _request(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final request = _authenticatedRequest ?? _authService.authenticatedRequest;
    return request(method, url, headers: headers, body: body);
  }

  FriendshipRequest _extractFriendship(Map<String, dynamic> data) {
    final friendshipJson = data['friendship'] ?? data['data'];
    if (friendshipJson is! Map<String, dynamic>) {
      throw const ContactDataException('响应中没有好友请求数据');
    }
    return FriendshipRequest.fromJson(friendshipJson);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ContactDataException(_extractError(response.body));
    }
    if (response.bodyBytes.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
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

  int _parseUserId(String userId) {
    final parsed = int.tryParse(userId);
    if (parsed == null) {
      throw ContactDataException('无效用户ID: $userId');
    }
    return parsed;
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }
}
