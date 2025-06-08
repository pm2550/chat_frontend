class ChatHistory {
  final int id;
  final int? chatRoomId;
  final int senderId;
  final int? receiverId;
  final String content;
  final MessageType messageType;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final int? replyToId;
  final bool isRecalled;
  final DateTime? recalledAt;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime sentAt;
  final String senderName;
  final String? senderAvatar;

  const ChatHistory({
    required this.id,
    this.chatRoomId,
    required this.senderId,
    this.receiverId,
    required this.content,
    required this.messageType,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.replyToId,
    this.isRecalled = false,
    this.recalledAt,
    this.isDeleted = false,
    this.deletedAt,
    required this.sentAt,
    required this.senderName,
    this.senderAvatar,
  });

  factory ChatHistory.fromJson(Map<String, dynamic> json) {
    return ChatHistory(
      id: json['id'],
      chatRoomId: json['chatRoomId'],
      senderId: json['senderId'],
      receiverId: json['receiverId'],
      content: json['content'] ?? '',
      messageType: MessageType.values.firstWhere(
        (e) => e.name.toUpperCase() == (json['messageType'] ?? 'TEXT').toString().toUpperCase(),
        orElse: () => MessageType.text,
      ),
      fileUrl: json['fileUrl'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      replyToId: json['replyToId'],
      isRecalled: json['isRecalled'] ?? false,
      recalledAt: json['recalledAt'] != null
          ? DateTime.tryParse(json['recalledAt'].toString())
          : null,
      isDeleted: json['isDeleted'] ?? false,
      deletedAt: json['deletedAt'] != null
          ? DateTime.tryParse(json['deletedAt'].toString())
          : null,
      sentAt: DateTime.tryParse(json['sentAt'].toString()) ?? DateTime.now(),
      senderName: json['senderName'] ?? '',
      senderAvatar: json['senderAvatar'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatRoomId': chatRoomId,
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
      'messageType': messageType.name.toUpperCase(),
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'replyToId': replyToId,
      'isRecalled': isRecalled,
      'recalledAt': recalledAt?.toIso8601String(),
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'sentAt': sentAt.toIso8601String(),
      'senderName': senderName,
      'senderAvatar': senderAvatar,
    };
  }

  ChatHistory copyWith({
    int? id,
    int? chatRoomId,
    int? senderId,
    int? receiverId,
    String? content,
    MessageType? messageType,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    int? replyToId,
    bool? isRecalled,
    DateTime? recalledAt,
    bool? isDeleted,
    DateTime? deletedAt,
    DateTime? sentAt,
    String? senderName,
    String? senderAvatar,
  }) {
    return ChatHistory(
      id: id ?? this.id,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      replyToId: replyToId ?? this.replyToId,
      isRecalled: isRecalled ?? this.isRecalled,
      recalledAt: recalledAt ?? this.recalledAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      sentAt: sentAt ?? this.sentAt,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
    );
  }

  /// 是否是私聊消息
  bool get isPrivateChat => receiverId != null && chatRoomId == null;

  /// 是否是群聊消息
  bool get isGroupChat => chatRoomId != null && receiverId == null;

  /// 是否是文件消息
  bool get isFileMessage => fileUrl != null && fileUrl!.isNotEmpty;

  /// 是否是图片消息
  bool get isImageMessage => messageType == MessageType.image;

  /// 是否是系统消息
  bool get isSystemMessage => messageType == MessageType.system;

  /// 是否可以撤回（2分钟内）
  bool get canRecall {
    if (isRecalled || isDeleted) return false;
    final now = DateTime.now();
    final diff = now.difference(sentAt);
    return diff.inMinutes < 2;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatHistory && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ChatHistory(id: $id, senderId: $senderId, content: $content, messageType: $messageType)';
  }
}

/// 消息类型枚举
enum MessageType {
  text('文本'),
  image('图片'),
  file('文件'),
  audio('语音'),
  video('视频'),
  system('系统消息');

  const MessageType(this.description);
  final String description;
}

/// 聊天记录分页响应
class ChatHistoryResponse {
  final List<ChatHistory> data;
  final int totalElements;
  final int totalPages;
  final int currentPage;
  final int pageSize;

  const ChatHistoryResponse({
    required this.data,
    required this.totalElements,
    required this.totalPages,
    required this.currentPage,
    required this.pageSize,
  });

  factory ChatHistoryResponse.fromJson(Map<String, dynamic> json) {
    return ChatHistoryResponse(
      data: (json['data'] as List)
          .map((item) => ChatHistory.fromJson(item))
          .toList(),
      totalElements: json['totalElements'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      currentPage: json['currentPage'] ?? 0,
      pageSize: json['pageSize'] ?? 20,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.map((item) => item.toJson()).toList(),
      'totalElements': totalElements,
      'totalPages': totalPages,
      'currentPage': currentPage,
      'pageSize': pageSize,
    };
  }

  /// 是否有更多数据
  bool get hasMore => currentPage < totalPages - 1;

  /// 是否是第一页
  bool get isFirstPage => currentPage == 0;

  /// 是否是最后一页
  bool get isLastPage => currentPage >= totalPages - 1;
} 