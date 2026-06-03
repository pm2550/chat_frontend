import 'dart:convert';

import '../constants/api_constants.dart';
import '../models/memory_entry.dart';
import 'auth_service.dart';

class MemoryException implements Exception {
  const MemoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Client for the room memory library (F2):
/// /api/v1/rooms/{roomId}/memories (list/search/create/update/pin/archive/delete).
///
/// Structure mirrors [WorkspaceService]: auth-aware requests with auto-refresh on
/// 401/403 handled by [AuthService.authenticatedRequest], `{data: ...}` envelope decode.
class MemoryService {
  MemoryService({
    AuthService? authService,
    Future<dynamic> Function(
      String method,
      String url, {
      Map<String, String>? headers,
      Object? body,
    })? authenticatedRequest,
  })  : _authService = authService ?? AuthService(),
        _authenticatedRequest = authenticatedRequest;

  final AuthService _authService;
  final Future<dynamic> Function(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  })? _authenticatedRequest;

  Future<List<MemoryEntry>> listMemories({
    required int roomId,
    String? q,
    bool includeArchived = false,
  }) async {
    final uri = Uri.parse(ApiConstants.roomMemories(roomId)).replace(
      queryParameters: {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (includeArchived) 'includeArchived': 'true',
      },
    );
    final response = await _request('GET', uri.toString());
    final raw = _decode(response)['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MemoryEntry.fromJson)
        .toList();
  }

  Future<MemoryEntry> createMemory({
    required int roomId,
    required String title,
    required String content,
    String? keywords,
    required MemoryVisibility visibility,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.roomMemories(roomId),
      body: {
        'title': title,
        'content': content,
        if (keywords != null && keywords.trim().isNotEmpty)
          'keywords': keywords.trim(),
        'visibility':
            visibility == MemoryVisibility.private ? 'PRIVATE' : 'ROOM',
      },
    );
    return MemoryEntry.fromJson(_extractData(_decode(response)));
  }

  Future<MemoryEntry> updateMemory({
    required int roomId,
    required int memoryId,
    required String title,
    required String content,
    String? keywords,
    required MemoryVisibility visibility,
  }) async {
    final response = await _request(
      'PUT',
      ApiConstants.roomMemoryDetail(roomId, memoryId),
      body: {
        'title': title,
        'content': content,
        if (keywords != null && keywords.trim().isNotEmpty)
          'keywords': keywords.trim(),
        'visibility':
            visibility == MemoryVisibility.private ? 'PRIVATE' : 'ROOM',
      },
    );
    return MemoryEntry.fromJson(_extractData(_decode(response)));
  }

  Future<void> setPinned({
    required int roomId,
    required int memoryId,
    required bool pinned,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.roomMemoryPin(roomId, memoryId),
      body: {'pinned': pinned},
    );
    _decode(response);
  }

  Future<void> setArchived({
    required int roomId,
    required int memoryId,
    required bool archived,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.roomMemoryArchive(roomId, memoryId),
      body: {'archived': archived},
    );
    _decode(response);
  }

  Future<void> deleteMemory({
    required int roomId,
    required int memoryId,
  }) async {
    final response = await _request(
      'DELETE',
      ApiConstants.roomMemoryDetail(roomId, memoryId),
    );
    _decode(response);
  }

  Future<dynamic> _request(
    String method,
    String url, {
    Object? body,
  }) {
    final request = _authenticatedRequest ?? _authService.authenticatedRequest;
    return request(method, url, body: body);
  }

  Map<String, dynamic> _decode(dynamic response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MemoryException(_extractError(response.body));
    }
    if (response.bodyBytes.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Map<String, dynamic> _extractData(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    throw const MemoryException('响应中没有记忆数据');
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded['message']?.toString() ??
            decoded['error']?.toString() ??
            '请求失败';
      }
    } catch (_) {}
    return '请求失败';
  }
}
