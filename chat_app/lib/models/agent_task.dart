import 'message.dart';

enum AgentTaskStatus { pending, running, succeeded, failed }

class AgentTask {
  const AgentTask({
    required this.id,
    required this.chatRoomId,
    required this.requestedById,
    required this.prompt,
    required this.status,
    this.botId,
    this.result,
    this.errorMessage,
    this.artifactWorkspaceId,
    this.artifactFolderId,
    this.artifactFileId,
    this.artifactFileName,
    this.resultMessage,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String chatRoomId;
  final String requestedById;
  final String? botId;
  final String prompt;
  final String? result;
  final String? errorMessage;
  final String? artifactWorkspaceId;
  final String? artifactFolderId;
  final String? artifactFileId;
  final String? artifactFileName;
  final AgentTaskStatus status;
  final Message? resultMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  factory AgentTask.fromJson(Map<String, dynamic> json) {
    final statusValue = json['status']?.toString().toLowerCase() ?? 'pending';
    return AgentTask(
      id: json['id']?.toString() ?? '',
      chatRoomId: json['chatRoomId']?.toString() ??
          json['chat_room_id']?.toString() ??
          '',
      requestedById: json['requestedById']?.toString() ??
          json['requested_by_id']?.toString() ??
          '',
      botId: json['botId']?.toString() ?? json['bot_id']?.toString(),
      prompt: json['prompt']?.toString() ?? '',
      result: json['result']?.toString(),
      errorMessage:
          json['errorMessage']?.toString() ?? json['error_message']?.toString(),
      artifactWorkspaceId: json['artifactWorkspaceId']?.toString() ??
          json['artifact_workspace_id']?.toString(),
      artifactFolderId: json['artifactFolderId']?.toString() ??
          json['artifact_folder_id']?.toString(),
      artifactFileId: json['artifactFileId']?.toString() ??
          json['artifact_file_id']?.toString(),
      artifactFileName: json['artifactFileName']?.toString() ??
          json['artifact_file_name']?.toString(),
      status: AgentTaskStatus.values.firstWhere(
        (status) => status.name == statusValue,
        orElse: () => AgentTaskStatus.pending,
      ),
      resultMessage: json['resultMessage'] is Map<String, dynamic>
          ? Message.fromJson(json['resultMessage'] as Map<String, dynamic>)
          : null,
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
      completedAt: _parseDate(json['completedAt'] ?? json['completed_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
