import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/user.dart';
import '../models/workspace.dart';
import 'auth_service.dart';

class PickedWorkspaceFile {
  const PickedWorkspaceFile({
    required this.name,
    required this.size,
    this.path,
    this.bytes,
  });

  final String name;
  final int size;
  final String? path;
  final List<int>? bytes;
}

class DownloadedWorkspaceFile {
  const DownloadedWorkspaceFile({
    required this.name,
    required this.bytes,
    this.mimeType,
  });

  final String name;
  final List<int> bytes;
  final String? mimeType;
}

class WorkspaceException implements Exception {
  const WorkspaceException(this.message, {this.statusCode});

  final String message;

  /// HTTP status of the failed response, when known (e.g. 409/412 for a version conflict).
  final int? statusCode;

  bool get isConflict => statusCode == 409 || statusCode == 412;

  @override
  String toString() => message;
}

class WorkspaceService {
  WorkspaceService({
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

  Future<List<Workspace>> listWorkspaces() async {
    final response = await _request('GET', ApiConstants.workspaces);
    final data = _decode(response);
    final raw = data['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Workspace.fromJson)
        .toList();
  }

  Future<Workspace> getWorkspace(int workspaceId) async {
    final response = await _request(
      'GET',
      ApiConstants.workspaceDetail(workspaceId),
    );
    return Workspace.fromJson(_extractData(_decode(response)));
  }

  Future<Workspace> createWorkspace({
    required String name,
    String workspaceType = 'TEAM',
    String? description,
    bool botAccessEnabled = false,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.workspaces,
      body: {
        'name': name,
        'workspaceType': workspaceType,
        'botAccessEnabled': botAccessEnabled,
        if (description != null) 'description': description,
      },
    );
    return Workspace.fromJson(_extractData(_decode(response)));
  }

  Future<List<WorkspaceMember>> listMembers(int workspaceId) async {
    final response = await _request(
      'GET',
      ApiConstants.workspaceMembers(workspaceId),
    );
    final raw = _decode(response)['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(WorkspaceMember.fromJson)
        .toList();
  }

  Future<WorkspaceMember> addMember({
    required int workspaceId,
    required int userId,
    required String role,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.workspaceMembers(workspaceId),
      body: {
        'userId': userId,
        'role': role,
      },
    );
    return WorkspaceMember.fromJson(_extractData(_decode(response)));
  }

  Future<List<WorkspacePermissionEntry>> listPermissions(
      int workspaceId) async {
    final response = await _request(
      'GET',
      ApiConstants.workspacePermissions(workspaceId),
    );
    final raw = _decode(response)['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(WorkspacePermissionEntry.fromJson)
        .toList();
  }

  Future<WorkspacePermissionEntry> grantPermission({
    required int workspaceId,
    required String resourceType,
    int? resourceId,
    required String principalType,
    required int principalId,
    required String accessLevel,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.workspacePermissions(workspaceId),
      body: {
        'resourceType': resourceType,
        if (resourceId != null) 'resourceId': resourceId,
        'principalType': principalType,
        'principalId': principalId,
        'accessLevel': accessLevel,
      },
    );
    return WorkspacePermissionEntry.fromJson(_extractData(_decode(response)));
  }

  Future<void> revokePermission({
    required int workspaceId,
    required int permissionId,
  }) async {
    final response = await _request(
      'DELETE',
      ApiConstants.workspacePermissionDetail(workspaceId, permissionId),
    );
    _decode(response);
  }

  Future<List<User>> searchUsers(String keyword, {int limit = 10}) async {
    if (keyword.trim().isEmpty) return const [];
    final uri = Uri.parse(ApiConstants.profileSearch).replace(
      queryParameters: {
        'keyword': keyword.trim(),
        'limit': limit.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    final raw = _decode(response)['data'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(User.fromJson).toList();
  }

  Future<Workspace> setWorkspaceLock(
    int workspaceId, {
    required bool locked,
    String? reason,
  }) async {
    final response = await _request(
      'PUT',
      ApiConstants.workspaceLock(workspaceId),
      body: {
        'locked': locked,
        if (reason != null) 'reason': reason,
      },
    );
    return Workspace.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceContents> getContents(
    int workspaceId, {
    int? folderId,
  }) async {
    final uri = Uri.parse(ApiConstants.workspaceContents(workspaceId)).replace(
      queryParameters: {
        if (folderId != null) 'folderId': folderId.toString(),
      },
    );
    final response = await _request('GET', uri.toString());
    return WorkspaceContents.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFolder> createFolder({
    required int workspaceId,
    required String name,
    int? parentFolderId,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.workspaceFolders(workspaceId),
      body: {
        'name': name,
        if (parentFolderId != null) 'parentFolderId': parentFolderId,
      },
    );
    return WorkspaceFolder.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFolder> setFolderLock({
    required int workspaceId,
    required int folderId,
    required bool locked,
    String? reason,
  }) async {
    final response = await _request(
      'PUT',
      ApiConstants.workspaceFolderLock(workspaceId, folderId),
      body: {
        'locked': locked,
        if (reason != null) 'reason': reason,
      },
    );
    return WorkspaceFolder.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFolder> deleteFolder({
    required int workspaceId,
    required int folderId,
  }) async {
    final response = await _request(
      'DELETE',
      ApiConstants.workspaceFolderDetail(workspaceId, folderId),
    );
    return WorkspaceFolder.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFolder> restoreFolder({
    required int workspaceId,
    required int folderId,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.workspaceFolderRestore(workspaceId, folderId),
    );
    return WorkspaceFolder.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFileItem> uploadFile({
    required int workspaceId,
    int? folderId,
    required PickedWorkspaceFile file,
    String? versionNote,
  }) async {
    final url = Uri.parse(ApiConstants.workspaceFiles(workspaceId)).replace(
      queryParameters: {
        if (folderId != null) 'folderId': folderId.toString(),
        if (versionNote != null && versionNote.isNotEmpty)
          'versionNote': versionNote,
      },
    );
    final response = await _multipart(url.toString(), file);
    return WorkspaceFileItem.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFileItem> addVersion({
    required int workspaceId,
    required int fileId,
    required PickedWorkspaceFile file,
    String? versionNote,
  }) async {
    final url =
        Uri.parse(ApiConstants.workspaceFileVersions(workspaceId, fileId))
            .replace(
      queryParameters: {
        if (versionNote != null && versionNote.isNotEmpty)
          'versionNote': versionNote,
      },
    );
    final response = await _multipart(url.toString(), file);
    return WorkspaceFileItem.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFileItem> restoreVersion({
    required int workspaceId,
    required int fileId,
    required int versionNumber,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.workspaceFileVersionRestore(
        workspaceId,
        fileId,
        versionNumber,
      ),
    );
    return WorkspaceFileItem.fromJson(_extractData(_decode(response)));
  }

  // F6: inline text editing ----------------------------------------------

  Future<WorkspaceTextContent> readText({
    required int workspaceId,
    required int fileId,
  }) async {
    final response = await _request(
      'GET',
      ApiConstants.workspaceFileText(workspaceId, fileId),
    );
    return WorkspaceTextContent.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFileItem> createTextFile({
    required int workspaceId,
    required String fileName,
    required String content,
    int? folderId,
    int? sourceBotId,
    String? versionNote,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.workspaceCreateTextFile(workspaceId),
      body: {
        'fileName': fileName,
        'content': content,
        if (folderId != null) 'folderId': folderId,
        if (sourceBotId != null) 'sourceBotId': sourceBotId,
        if (versionNote != null && versionNote.isNotEmpty)
          'versionNote': versionNote,
      },
    );
    return WorkspaceFileItem.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFileItem> saveText({
    required int workspaceId,
    required int fileId,
    required String content,
    int? sourceBotId,
    String? versionNote,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.workspaceFileText(workspaceId, fileId),
      body: {
        'content': content,
        if (sourceBotId != null) 'sourceBotId': sourceBotId,
        if (versionNote != null && versionNote.isNotEmpty)
          'versionNote': versionNote,
      },
    );
    return WorkspaceFileItem.fromJson(_extractData(_decode(response)));
  }

  Future<List<WorkspaceVersion>> listVersions({
    required int workspaceId,
    required int fileId,
  }) async {
    final response = await _request(
      'GET',
      ApiConstants.workspaceFileVersions(workspaceId, fileId),
    );
    final raw = _decode(response)['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(WorkspaceVersion.fromJson)
        .toList();
  }

  Future<WorkspaceFileItem> setFileLock({
    required int workspaceId,
    required int fileId,
    required bool locked,
    String? reason,
  }) async {
    final response = await _request(
      'PUT',
      ApiConstants.workspaceFileLock(workspaceId, fileId),
      body: {
        'locked': locked,
        if (reason != null) 'reason': reason,
      },
    );
    return WorkspaceFileItem.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFileItem> deleteFile({
    required int workspaceId,
    required int fileId,
  }) async {
    final response = await _request(
      'DELETE',
      ApiConstants.workspaceFileDetail(workspaceId, fileId),
    );
    return WorkspaceFileItem.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceFileItem> restoreFile({
    required int workspaceId,
    required int fileId,
  }) async {
    final response = await _request(
      'POST',
      ApiConstants.workspaceFileRestore(workspaceId, fileId),
    );
    return WorkspaceFileItem.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceTrash> listTrash(int workspaceId) async {
    final response = await _request(
      'GET',
      ApiConstants.workspaceTrash(workspaceId),
    );
    return WorkspaceTrash.fromJson(_extractData(_decode(response)));
  }

  Future<WorkspaceMaintenanceResult> cleanupOrphans(
    int workspaceId, {
    bool dryRun = true,
  }) async {
    final uri = Uri.parse(ApiConstants.workspaceOrphanMaintenance(workspaceId))
        .replace(queryParameters: {'dryRun': dryRun.toString()});
    final response = await _request('POST', uri.toString());
    return WorkspaceMaintenanceResult.fromJson(_extractData(_decode(response)));
  }

  Future<DownloadedWorkspaceFile> downloadFile(WorkspaceFileItem file) async {
    return _downloadBytes(
      url: ApiConstants.workspaceFileDownload(file.workspaceId, file.id),
      name: file.displayName,
    );
  }

  Future<DownloadedWorkspaceFile> previewFile(WorkspaceFileItem file) async {
    return _downloadBytes(
      url: ApiConstants.workspaceFilePreview(file.workspaceId, file.id),
      name: file.displayName,
    );
  }

  Future<DownloadedWorkspaceFile> _downloadBytes({
    required String url,
    required String name,
  }) async {
    Future<http.Response> send() {
      return http.get(
        Uri.parse(url),
        headers: {
          if (_authService.accessToken != null)
            'Authorization': 'Bearer ${_authService.accessToken}',
        },
      ).timeout(ApiConstants.requestTimeout);
    }

    var response = await send();
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        await _authService.refreshAccessToken()) {
      response = await send();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkspaceException(_extractError(response.body));
    }
    return DownloadedWorkspaceFile(
      name: name,
      bytes: response.bodyBytes,
      mimeType: response.headers['content-type'],
    );
  }

  Future<dynamic> _request(
    String method,
    String url, {
    Object? body,
  }) {
    final request = _authenticatedRequest ?? _authService.authenticatedRequest;
    return request(method, url, body: body);
  }

  Future<http.Response> _multipart(String url, PickedWorkspaceFile file) async {
    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      final token = _authService.accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      if (file.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));
      } else if (file.path != null && file.path!.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path!,
          filename: file.name,
        ));
      } else {
        throw const WorkspaceException('请选择有效文件');
      }
      final streamed = await request.send().timeout(ApiConstants.uploadTimeout);
      return http.Response.fromStream(streamed);
    }

    var response = await send();
    if (response.statusCode == 401 && await _authService.refreshAccessToken()) {
      response = await send();
    }
    return response;
  }

  Map<String, dynamic> _decode(dynamic response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkspaceException(_extractError(response.body),
          statusCode: response.statusCode);
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
    throw const WorkspaceException('响应中没有资料库数据');
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
