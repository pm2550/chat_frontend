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
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'].toString(),
      content: json['content'] ?? '',
      senderId: json['senderId'].toString(),
      senderName: json['senderName'] ?? 'Unknown',
      senderAvatar: json['senderAvatar'],
      chatRoomId: json['chatRoomId'].toString(),
      type: MessageType.values.firstWhere(
        (type) => type.name == (json['type'] ?? 'text').toLowerCase(),
        orElse: () => MessageType.text,
      ),
      status: MessageStatus.values.firstWhere(
        (status) => status.name == (json['status'] ?? 'sent').toLowerCase(),
        orElse: () => MessageStatus.sent,
      ),
      timestamp: DateTime.parse(json['timestamp']),
      editedAt: json['editedAt'] != null ? DateTime.parse(json['editedAt']) : null,
      replyToId: json['replyToId']?.toString(),
      replyToMessage: json['replyToMessage'] != null 
          ? Message.fromJson(json['replyToMessage']) 
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
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
    return 'Message(id: $id, senderId: $senderId, type: $type, content: ${content.length > 50 ? content.substring(0, 50) + '...' : content})';
  }
} 