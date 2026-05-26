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
  final bool isDeleted;
  final bool isRecalled;
  final String? encryptedContent;
  final int? encryptionVersion;
  final bool isAnonymous;
  final String? anonymousIdentityId;
  final String? anonymousName;
  final String? anonymousAvatar;

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
    this.isDeleted = false,
    this.isRecalled = false,
    this.encryptedContent,
    this.encryptionVersion,
    this.isAnonymous = false,
    this.anonymousIdentityId,
    this.anonymousName,
    this.anonymousAvatar,
  });

  factory Message.fromJson(Map<String, dynamic> json,
      {String? fallbackChatRoomId}) {
    final senderJson = json['sender'] is Map<String, dynamic>
        ? json['sender'] as Map<String, dynamic>
        : null;
    final chatRoomJson = json['chatRoom'] is Map<String, dynamic>
        ? json['chatRoom'] as Map<String, dynamic>
        : null;
    final typeValue =
        json['type'] ?? json['messageType'] ?? json['message_type'] ?? 'TEXT';
    final statusValue = json['status'] ??
        json['messageStatus'] ??
        json['message_status'] ??
        'SENT';
    final timestampValue =
        json['timestamp'] ?? json['createdAt'] ?? json['created_at'];
    final isAnonymous = _parseBool(json['isAnonymous'] ?? json['is_anonymous']);
    final anonymousName = json['anonymousName'] ?? json['anonymous_name'];
    final anonymousAvatar = json['anonymousAvatar'] ?? json['anonymous_avatar'];
    final regularSenderName = json['senderName'] ??
        json['sender_name'] ??
        senderJson?['displayName'] ??
        senderJson?['display_name'] ??
        senderJson?['username'] ??
        '';

    return Message(
      id: json['id']?.toString() ?? '',
      content: json['content'] ?? '',
      senderId: json['senderId']?.toString() ??
          json['sender_id']?.toString() ??
          senderJson?['id']?.toString() ??
          '',
      senderName: isAnonymous
          ? (anonymousName?.toString().isNotEmpty == true
              ? anonymousName.toString()
              : regularSenderName)
          : regularSenderName,
      senderAvatar: isAnonymous && anonymousAvatar != null
          ? anonymousAvatar.toString()
          : json['senderAvatar'] ??
              json['sender_avatar'] ??
              senderJson?['avatarUrl'] ??
              senderJson?['avatar_url'],
      chatRoomId: json['chatRoomId']?.toString() ??
          json['chat_room_id']?.toString() ??
          chatRoomJson?['id']?.toString() ??
          fallbackChatRoomId ??
          '',
      type: MessageType.values.firstWhere(
        (e) => e.name.toUpperCase() == typeValue.toString().toUpperCase(),
        orElse: () => MessageType.text,
      ),
      status: MessageStatus.values.firstWhere(
        (e) => e.name.toUpperCase() == statusValue.toString().toUpperCase(),
        orElse: () => MessageStatus.sent,
      ),
      timestamp:
          DateTime.tryParse(timestampValue?.toString() ?? '') ?? DateTime.now(),
      editedAt: json['editedAt'] != null || json['edited_at'] != null
          ? DateTime.tryParse(
              (json['editedAt'] ?? json['edited_at']).toString())
          : null,
      replyToId: json['replyToId']?.toString(),
      replyToMessage: json['replyToMessage'] != null
          ? Message.fromJson(
              json['replyToMessage'] as Map<String, dynamic>,
              fallbackChatRoomId: fallbackChatRoomId,
            )
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
      replyToMessageId: json['replyToMessageId']?.toString() ??
          json['reply_to_message_id']?.toString(),
      fileUrl: json['fileUrl'] ?? json['file_url'],
      fileName: json['fileName'] ?? json['file_name'],
      fileSize: _parseInt(json['fileSize'] ?? json['file_size']),
      fileType: json['fileType'] ?? json['file_type'],
      isDeleted: _parseBool(json['isDeleted'] ?? json['is_deleted']),
      isRecalled: _parseBool(json['isRecalled'] ?? json['is_recalled']) ||
          (json['content']?.toString() == '[消息已撤回]'),
      encryptedContent: json['encryptedContent'] ?? json['encrypted_content'],
      encryptionVersion:
          _parseInt(json['encryptionVersion'] ?? json['encryption_version']),
      isAnonymous: isAnonymous,
      anonymousIdentityId: json['anonymousIdentityId']?.toString() ??
          json['anonymous_identity_id']?.toString(),
      anonymousName: anonymousName?.toString(),
      anonymousAvatar: anonymousAvatar?.toString(),
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
      'isDeleted': isDeleted,
      'isRecalled': isRecalled,
      'encryptedContent': encryptedContent,
      'encryptionVersion': encryptionVersion,
      'isAnonymous': isAnonymous,
      'anonymousIdentityId': anonymousIdentityId,
      'anonymousName': anonymousName,
      'anonymousAvatar': anonymousAvatar,
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
    bool? isDeleted,
    bool? isRecalled,
    String? encryptedContent,
    int? encryptionVersion,
    bool? isAnonymous,
    String? anonymousIdentityId,
    String? anonymousName,
    String? anonymousAvatar,
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
      isDeleted: isDeleted ?? this.isDeleted,
      isRecalled: isRecalled ?? this.isRecalled,
      encryptedContent: encryptedContent ?? this.encryptedContent,
      encryptionVersion: encryptionVersion ?? this.encryptionVersion,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      anonymousIdentityId: anonymousIdentityId ?? this.anonymousIdentityId,
      anonymousName: anonymousName ?? this.anonymousName,
      anonymousAvatar: anonymousAvatar ?? this.anonymousAvatar,
    );
  }

  bool get isEdited => editedAt != null;
  bool get hasReply => replyToMessage != null;
  bool get isRemoved => isDeleted || isRecalled;
  bool get isEncrypted =>
      encryptedContent != null && encryptedContent!.isNotEmpty;
  bool get isImageMessage => type == MessageType.image;
  bool get isVoiceMessage =>
      type == MessageType.voice ||
      (fileType?.toLowerCase().startsWith('audio/') ?? false);
  bool get isVideoMessage =>
      type == MessageType.video ||
      (fileType?.toLowerCase().startsWith('video/') ?? false);
  bool get isLocationMessage => type == MessageType.location;
  bool get isFileMessage =>
      type == MessageType.file ||
      (fileUrl != null &&
          !isImageMessage &&
          !isVoiceMessage &&
          !isVideoMessage);
  String get resolvedFileLabel {
    if (isImageMessage) {
      return fileName?.isNotEmpty == true ? '[图片] $fileName' : '[图片]';
    }
    if (isVoiceMessage) {
      return fileName?.isNotEmpty == true ? '[语音] $fileName' : '[语音]';
    }
    if (isVideoMessage) {
      return fileName?.isNotEmpty == true ? '[视频] $fileName' : '[视频]';
    }
    if (isFileMessage) {
      return fileName?.isNotEmpty == true ? '[文件] $fileName' : '[文件]';
    }
    return content;
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
    return 'Message(id: $id, senderId: $senderId, content: $content)';
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }
}
