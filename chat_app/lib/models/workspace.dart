class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    required this.workspaceType,
    required this.isLocked,
    required this.botAccessEnabled,
    this.quotaBytes,
    this.usedBytes,
    this.description,
    this.ownerName,
    this.myAccessLevel,
    this.lockReason,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String? description;
  final String workspaceType;
  final String? ownerName;
  final String? myAccessLevel;
  final bool isLocked;
  final String? lockReason;
  final bool botAccessEnabled;
  final int? quotaBytes;
  final int? usedBytes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      workspaceType: json['workspaceType']?.toString() ?? 'TEAM',
      ownerName: json['ownerName']?.toString(),
      myAccessLevel: json['myAccessLevel']?.toString(),
      isLocked: json['isLocked'] == true,
      lockReason: json['lockReason']?.toString(),
      botAccessEnabled: json['botAccessEnabled'] == true,
      quotaBytes: _asNullableInt(json['quotaBytes']),
      usedBytes: _asNullableInt(json['usedBytes']),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
    );
  }
}

class WorkspaceMember {
  const WorkspaceMember({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.role,
    this.createdAt,
  });

  final int id;
  final int userId;
  final String username;
  final String displayName;
  final String role;
  final DateTime? createdAt;

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      id: _asInt(json['id']),
      userId: _asInt(json['userId']),
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      role: json['role']?.toString() ?? 'VIEWER',
      createdAt: _asDate(json['createdAt']),
    );
  }
}

class WorkspacePermissionEntry {
  const WorkspacePermissionEntry({
    required this.id,
    required this.workspaceId,
    required this.resourceType,
    required this.principalType,
    required this.principalId,
    required this.accessLevel,
    this.resourceId,
    this.resourceName,
    this.principalName,
    this.createdByName,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int workspaceId;
  final String resourceType;
  final int? resourceId;
  final String? resourceName;
  final String principalType;
  final int principalId;
  final String? principalName;
  final String accessLevel;
  final String? createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory WorkspacePermissionEntry.fromJson(Map<String, dynamic> json) {
    return WorkspacePermissionEntry(
      id: _asInt(json['id']),
      workspaceId: _asInt(json['workspaceId']),
      resourceType: json['resourceType']?.toString() ?? 'WORKSPACE',
      resourceId: _asNullableInt(json['resourceId']),
      resourceName: json['resourceName']?.toString(),
      principalType: json['principalType']?.toString() ?? 'USER',
      principalId: _asInt(json['principalId']),
      principalName: json['principalName']?.toString(),
      accessLevel: json['accessLevel']?.toString() ?? 'VIEW',
      createdByName: json['createdByName']?.toString(),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
    );
  }
}

class WorkspaceFolder {
  const WorkspaceFolder({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.isLocked,
    required this.botAccessEnabled,
    this.isDeleted = false,
    this.parentFolderId,
    this.lockReason,
    this.deletedAt,
    this.deletedByName,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int workspaceId;
  final int? parentFolderId;
  final String name;
  final bool isLocked;
  final String? lockReason;
  final bool botAccessEnabled;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory WorkspaceFolder.fromJson(Map<String, dynamic> json) {
    return WorkspaceFolder(
      id: _asInt(json['id']),
      workspaceId: _asInt(json['workspaceId']),
      parentFolderId: _asNullableInt(json['parentFolderId']),
      name: json['name']?.toString() ?? '',
      isLocked: json['isLocked'] == true,
      lockReason: json['lockReason']?.toString(),
      botAccessEnabled: json['botAccessEnabled'] == true,
      isDeleted: json['isDeleted'] == true,
      deletedAt: _asDate(json['deletedAt']),
      deletedByName: json['deletedByName']?.toString(),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
    );
  }
}

class WorkspaceFileItem {
  const WorkspaceFileItem({
    required this.id,
    required this.workspaceId,
    required this.displayName,
    required this.currentVersion,
    required this.sourceType,
    required this.isLocked,
    required this.botAccessEnabled,
    this.isDeleted = false,
    this.folderId,
    this.mimeType,
    this.fileSize,
    this.sourceBotName,
    this.createdByName,
    this.lockReason,
    this.deletedAt,
    this.deletedByName,
    this.scanStatus,
    this.scanSummary,
    this.scannedAt,
    this.storageProvider,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int workspaceId;
  final int? folderId;
  final String displayName;
  final String? mimeType;
  final int? fileSize;
  final int currentVersion;
  final String sourceType;
  final String? sourceBotName;
  final String? createdByName;
  final bool isLocked;
  final String? lockReason;
  final bool botAccessEnabled;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedByName;
  final String? scanStatus;
  final String? scanSummary;
  final DateTime? scannedAt;
  final String? storageProvider;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isBotFile => sourceType == 'BOT';
  bool get isImage => (mimeType ?? '').toLowerCase().startsWith('image/');
  bool get isTextPreview {
    final type = (mimeType ?? '').toLowerCase();
    final name = displayName.toLowerCase();
    return type.startsWith('text/') ||
        name.endsWith('.txt') ||
        name.endsWith('.md') ||
        name.endsWith('.json') ||
        name.endsWith('.csv') ||
        name.endsWith('.log');
  }

  bool get isPreviewable {
    final type = (mimeType ?? '').toLowerCase();
    return isImage || isTextPreview || type == 'application/pdf';
  }

  factory WorkspaceFileItem.fromJson(Map<String, dynamic> json) {
    return WorkspaceFileItem(
      id: _asInt(json['id']),
      workspaceId: _asInt(json['workspaceId']),
      folderId: _asNullableInt(json['folderId']),
      displayName: json['displayName']?.toString() ?? '',
      mimeType: json['mimeType']?.toString(),
      fileSize: _asNullableInt(json['fileSize']),
      currentVersion: _asNullableInt(json['currentVersion']) ?? 1,
      sourceType: json['sourceType']?.toString() ?? 'USER',
      sourceBotName: json['sourceBotName']?.toString(),
      createdByName: json['createdByName']?.toString(),
      isLocked: json['isLocked'] == true,
      lockReason: json['lockReason']?.toString(),
      botAccessEnabled: json['botAccessEnabled'] == true,
      isDeleted: json['isDeleted'] == true,
      deletedAt: _asDate(json['deletedAt']),
      deletedByName: json['deletedByName']?.toString(),
      scanStatus: json['scanStatus']?.toString(),
      scanSummary: json['scanSummary']?.toString(),
      scannedAt: _asDate(json['scannedAt']),
      storageProvider: json['storageProvider']?.toString(),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt']),
    );
  }
}

/// F6: full text body of an editable workspace file. Mirrors
/// `WorkspaceDto.TextContent {fileId, displayName, mimeType, currentVersion, content}`.
class WorkspaceTextContent {
  const WorkspaceTextContent({
    required this.fileId,
    required this.displayName,
    required this.currentVersion,
    required this.content,
    this.mimeType,
  });

  final int fileId;
  final String displayName;
  final int currentVersion;
  final String content;
  final String? mimeType;

  factory WorkspaceTextContent.fromJson(Map<String, dynamic> json) {
    return WorkspaceTextContent(
      fileId: _asInt(json['fileId']),
      displayName: json['displayName']?.toString() ?? '',
      currentVersion: _asNullableInt(json['currentVersion']) ?? 1,
      content: json['content']?.toString() ?? '',
      mimeType: json['mimeType']?.toString(),
    );
  }
}

class WorkspaceVersion {
  const WorkspaceVersion({
    required this.id,
    required this.fileId,
    required this.versionNumber,
    required this.originalName,
    this.mimeType,
    this.fileSize,
    this.checksumSha256,
    this.versionNote,
    this.scanStatus,
    this.scanSummary,
    this.scannedAt,
    this.storageProvider,
    this.uploadedByName,
    this.uploadedByBotName,
    this.createdAt,
  });

  final int id;
  final int fileId;
  final int versionNumber;
  final String originalName;
  final String? mimeType;
  final int? fileSize;
  final String? checksumSha256;
  final String? versionNote;
  final String? scanStatus;
  final String? scanSummary;
  final DateTime? scannedAt;
  final String? storageProvider;
  final String? uploadedByName;
  final String? uploadedByBotName;
  final DateTime? createdAt;

  factory WorkspaceVersion.fromJson(Map<String, dynamic> json) {
    return WorkspaceVersion(
      id: _asInt(json['id']),
      fileId: _asInt(json['fileId']),
      versionNumber: _asInt(json['versionNumber']),
      originalName: json['originalName']?.toString() ?? '',
      mimeType: json['mimeType']?.toString(),
      fileSize: _asNullableInt(json['fileSize']),
      checksumSha256: json['checksumSha256']?.toString(),
      versionNote: json['versionNote']?.toString(),
      scanStatus: json['scanStatus']?.toString(),
      scanSummary: json['scanSummary']?.toString(),
      scannedAt: _asDate(json['scannedAt']),
      storageProvider: json['storageProvider']?.toString(),
      uploadedByName: json['uploadedByName']?.toString(),
      uploadedByBotName: json['uploadedByBotName']?.toString(),
      createdAt: _asDate(json['createdAt']),
    );
  }
}

class WorkspaceContents {
  const WorkspaceContents({
    required this.folders,
    required this.files,
  });

  final List<WorkspaceFolder> folders;
  final List<WorkspaceFileItem> files;

  factory WorkspaceContents.fromJson(Map<String, dynamic> json) {
    final rawFolders = json['folders'];
    final rawFiles = json['files'];
    return WorkspaceContents(
      folders: rawFolders is List
          ? rawFolders
              .whereType<Map<String, dynamic>>()
              .map(WorkspaceFolder.fromJson)
              .toList()
          : const [],
      files: rawFiles is List
          ? rawFiles
              .whereType<Map<String, dynamic>>()
              .map(WorkspaceFileItem.fromJson)
              .toList()
          : const [],
    );
  }
}

class WorkspaceTrash {
  const WorkspaceTrash({
    required this.folders,
    required this.files,
  });

  final List<WorkspaceFolder> folders;
  final List<WorkspaceFileItem> files;

  factory WorkspaceTrash.fromJson(Map<String, dynamic> json) {
    return WorkspaceTrash(
      folders: json['folders'] is List
          ? (json['folders'] as List)
              .whereType<Map<String, dynamic>>()
              .map(WorkspaceFolder.fromJson)
              .toList()
          : const [],
      files: json['files'] is List
          ? (json['files'] as List)
              .whereType<Map<String, dynamic>>()
              .map(WorkspaceFileItem.fromJson)
              .toList()
          : const [],
    );
  }
}

class WorkspaceMaintenanceResult {
  const WorkspaceMaintenanceResult({
    required this.orphanCount,
    required this.deletedCount,
    required this.bytes,
    required this.dryRun,
    required this.fileNames,
  });

  final int orphanCount;
  final int deletedCount;
  final int bytes;
  final bool dryRun;
  final List<String> fileNames;

  factory WorkspaceMaintenanceResult.fromJson(Map<String, dynamic> json) {
    return WorkspaceMaintenanceResult(
      orphanCount: _asInt(json['orphanCount']),
      deletedCount: _asInt(json['deletedCount']),
      bytes: _asInt(json['bytes']),
      dryRun: json['dryRun'] == true,
      fileNames: json['fileNames'] is List
          ? (json['fileNames'] as List).map((item) => item.toString()).toList()
          : const [],
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _asNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
