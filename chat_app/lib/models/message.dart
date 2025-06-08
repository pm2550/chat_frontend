import 'user.dart';

enum MessageType {
  text('文本'),
  image('图片'),
  file('文件'),
  voice('语音'),
  video('视频'),
  location('位置'),
  system('系统消息');

  const MessageType(this.description);
  final String description;
}

enum MessageStatus {
  sending('发送中'),
  sent('已发送'),
  delivered('已送达'),
  read('已读'),
  failed('发送失败');

  const MessageStatus(this.description);
  final String description;
}

class Message {
  final String id;
  final String content;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String chatRoomId;
  final MessageType type;
  final MessageStatus status;
  final DateTime timestamp;
  final DateTime? editedAt;
  final String? replyToId;
  final Message? replyToMessage;
  final Map<String, dynamic>? metadata;
  final String? replyToMessageId;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? fileType;

  const Message({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.chatRoomId,
    this.type = MessageType.text,
    this.status = MessageStatus.sending,
    required this.timestamp,
    this.editedAt,
    this.replyToId,
    this.replyToMessage,
    this.metadata,
    this.replyToMessageId,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.fileType,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? '',
      content: json['content'] ?? '',
      senderId: json['senderId']?.toString() ?? json['sender_id']?.toString() ?? '',
      senderName: json['senderName'] ?? json['sender_name'] ?? '',
      senderAvatar: json['senderAvatar'] ?? json['sender_avatar'],
      chatRoomId: json['chatRoomId']?.toString() ?? json['chat_room_id']?.toString() ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.name.toUpperCase() == (json['type'] ?? json['message_type'] ?? 'TEXT').toString().toUpperCase(),
        orElse: () => MessageType.text,
      ),
      status: MessageStatus.values.firstWhere(
        (e) => e.name.toUpperCase() == (json['status'] ?? json['message_status'] ?? 'SENT').toString().toUpperCase(),
        orElse: () => MessageStatus.sent,
      ),
      timestamp: DateTime.tryParse((json['timestamp'] ?? json['created_at']).toString()) ?? DateTime.now(),
      editedAt: json['editedAt'] != null ? DateTime.parse(json['editedAt']) : null,
      replyToId: json['replyToId']?.toString(),
      replyToMessage: json['replyToMessage'] != null 
          ? Message.fromJson(json['replyToMessage']) 
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
      replyToMessageId: json['replyToMessageId']?.toString() ?? json['reply_to_message_id']?.toString(),
      fileUrl: json['fileUrl'] ?? json['file_url'],
      fileName: json['fileName'] ?? json['file_name'],
      fileSize: json['fileSize'] ?? json['file_size'],
      fileType: json['fileType'] ?? json['file_type'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'chatRoomId': chatRoomId,
      'type': type.name.toUpperCase(),
      'status': status.name.toUpperCase(),
      'timestamp': timestamp.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'replyToId': replyToId,
      'replyToMessage': replyToMessage?.toJson(),
      'metadata': metadata,
      'replyToMessageId': replyToMessageId,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'fileType': fileType,
    };
  }

  Message copyWith({
    String? id,
    String? content,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? chatRoomId,
    MessageType? type,
    MessageStatus? status,
    DateTime? timestamp,
    DateTime? editedAt,
    String? replyToId,
    Message? replyToMessage,
    Map<String, dynamic>? metadata,
    String? replyToMessageId,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? fileType,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      editedAt: editedAt ?? this.editedAt,
      replyToId: replyToId ?? this.replyToId,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      metadata: metadata ?? this.metadata,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      fileType: fileType ?? this.fileType,
    );
  }

  bool get isEdited => editedAt != null;
  bool get hasReply => replyToMessage != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Message(id: $id, senderId: $senderId, content: $content)';
  }
} 