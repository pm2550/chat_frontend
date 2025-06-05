import 'user.dart';

enum MessageType {
  text,
  image,
  file,
  voice,
  video,
  location,
  system,
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

class Message {
  final String id;
  final String chatId;
  final User sender;
  final String content;
  final MessageType type;
  final MessageStatus status;
  final DateTime timestamp;
  final DateTime? editedAt;
  final String? replyToId;
  final Map<String, dynamic>? metadata;
  final bool isDeleted;

  Message({
    required this.id,
    required this.chatId,
    required this.sender,
    required this.content,
    required this.type,
    required this.status,
    required this.timestamp,
    this.editedAt,
    this.replyToId,
    this.metadata,
    this.isDeleted = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      chatId: json['chatId'] as String,
      sender: User.fromJson(json['sender'] as Map<String, dynamic>),
      content: json['content'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => MessageType.text,
      ),
      status: MessageStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => MessageStatus.sent,
      ),
      timestamp: DateTime.parse(json['timestamp']),
      editedAt: json['editedAt'] != null ? DateTime.parse(json['editedAt']) : null,
      replyToId: json['replyToId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'sender': sender.toJson(),
      'content': content,
      'type': type.toString().split('.').last,
      'status': status.toString().split('.').last,
      'timestamp': timestamp.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'replyToId': replyToId,
      'metadata': metadata,
      'isDeleted': isDeleted,
    };
  }

  Message copyWith({
    String? id,
    String? chatId,
    User? sender,
    String? content,
    MessageType? type,
    MessageStatus? status,
    DateTime? timestamp,
    DateTime? editedAt,
    String? replyToId,
    Map<String, dynamic>? metadata,
    bool? isDeleted,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      sender: sender ?? this.sender,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      editedAt: editedAt ?? this.editedAt,
      replyToId: replyToId ?? this.replyToId,
      metadata: metadata ?? this.metadata,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Message(id: $id, sender: ${sender.name}, content: $content, type: $type)';
  }
} 