enum MessageType {
  text('文本'),
  image('图片'),
  file('文件'),
  voice('语音'),
  video('视频'),
  location('位置'),
  sticker('贴纸'),
  poll('投票'),
  imageGeneration('AI图片生成'),
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

class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
  });

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? faviconUrl;

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    return LinkPreview(
      url: json['url']?.toString() ?? '',
      title: _stringOrNull(json['title']),
      description: _stringOrNull(json['description']),
      imageUrl: _stringOrNull(json['imageUrl'] ?? json['image_url']),
      siteName: _stringOrNull(json['siteName'] ?? json['site_name']),
      faviconUrl: _stringOrNull(json['faviconUrl'] ?? json['favicon_url']),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'siteName': siteName,
        'faviconUrl': faviconUrl,
      };

  static String? _stringOrNull(dynamic value) {
    final string = value?.toString().trim();
    return string == null || string.isEmpty ? null : string;
  }
}

class MessageReaction {
  const MessageReaction({
    required this.emoji,
    required this.count,
    this.userIds = const [],
    this.currentUserReacted = false,
  });

  final String emoji;
  final int count;
  final List<String> userIds;
  final bool currentUserReacted;

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    final rawUserIds = json['userIds'] ?? json['user_ids'];
    return MessageReaction(
      emoji: json['emoji']?.toString() ?? '',
      count: json['count'] is int
          ? json['count'] as int
          : int.tryParse(json['count']?.toString() ?? '') ?? 0,
      userIds: rawUserIds is List
          ? rawUserIds.map((item) => item.toString()).toList()
          : const [],
      currentUserReacted: json['currentUserReacted'] == true ||
          json['current_user_reacted'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'count': count,
        'userIds': userIds,
        'currentUserReacted': currentUserReacted,
      };
}

class Message {
  final String id;
  final String content;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String? botConfigId;
  final String? botSenderId;
  final String? botName;
  final String? botAvatar;
  final String chatRoomId;
  final MessageType type;
  final MessageStatus status;
  final DateTime timestamp;
  final DateTime? editedAt;
  final String? replyToId;
  final Message? replyToMessage;
  final List<String> mentionedUserIds;
  final Map<String, dynamic>? metadata;
  final String? replyToMessageId;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? fileType;
  final int? stickerId;
  final int? pollId;
  final String? imageGenPrompt;
  final String? imageGenStatus;
  final String? imageGenUrl;
  final String? imageGenProviderTaskId;
  final bool isDeleted;
  final bool isRecalled;
  final String? encryptedContent;
  final int? encryptionVersion;
  final bool isAnonymous;
  final String? anonymousIdentityId;
  final String? anonymousName;
  final String? anonymousAvatar;
  final LinkPreview? linkPreview;
  final List<MessageReaction> reactions;
  final int readCount;

  const Message({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    this.botConfigId,
    this.botSenderId,
    this.botName,
    this.botAvatar,
    required this.chatRoomId,
    this.type = MessageType.text,
    this.status = MessageStatus.sending,
    required this.timestamp,
    this.editedAt,
    this.replyToId,
    this.replyToMessage,
    this.mentionedUserIds = const [],
    this.metadata,
    this.replyToMessageId,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.fileType,
    this.stickerId,
    this.pollId,
    this.imageGenPrompt,
    this.imageGenStatus,
    this.imageGenUrl,
    this.imageGenProviderTaskId,
    this.isDeleted = false,
    this.isRecalled = false,
    this.encryptedContent,
    this.encryptionVersion,
    this.isAnonymous = false,
    this.anonymousIdentityId,
    this.anonymousName,
    this.anonymousAvatar,
    this.linkPreview,
    this.reactions = const [],
    this.readCount = 0,
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
    final linkPreviewJson = json['linkPreview'] ?? json['link_preview'];
    final botName = _stringOrNull(json['botName'] ?? json['bot_name']);
    final botAvatar = _stringOrNull(json['botAvatar'] ?? json['bot_avatar']);
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
      botConfigId: _stringOrNull(json['botConfigId'] ?? json['bot_config_id']),
      botSenderId: _stringOrNull(json['botSenderId'] ?? json['bot_sender_id']),
      botName: botName,
      botAvatar: botAvatar,
      chatRoomId: json['chatRoomId']?.toString() ??
          json['chat_room_id']?.toString() ??
          chatRoomJson?['id']?.toString() ??
          fallbackChatRoomId ??
          '',
      type: _parseMessageType(typeValue),
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
      mentionedUserIds: _parseStringList(
        json['mentionedUserIds'] ??
            json['mentioned_user_ids'] ??
            json['mentions'] ??
            json['mentionedUsers'],
      ),
      metadata: json['metadata'] as Map<String, dynamic>?,
      replyToMessageId: json['replyToMessageId']?.toString() ??
          json['reply_to_message_id']?.toString(),
      fileUrl: json['fileUrl'] ?? json['file_url'],
      fileName: json['fileName'] ?? json['file_name'],
      fileSize: _parseInt(json['fileSize'] ?? json['file_size']),
      fileType: json['fileType'] ?? json['file_type'],
      stickerId: _parseInt(json['stickerId'] ?? json['sticker_id']),
      pollId: _parseInt(json['pollId'] ?? json['poll_id']),
      imageGenPrompt: json['imageGenPrompt']?.toString() ??
          json['image_gen_prompt']?.toString(),
      imageGenStatus: json['imageGenStatus']?.toString() ??
          json['image_gen_status']?.toString(),
      imageGenUrl:
          json['imageGenUrl']?.toString() ?? json['image_gen_url']?.toString(),
      imageGenProviderTaskId: json['imageGenProviderTaskId']?.toString() ??
          json['image_gen_provider_task_id']?.toString(),
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
      linkPreview: linkPreviewJson is Map<String, dynamic>
          ? LinkPreview.fromJson(linkPreviewJson)
          : null,
      reactions: _parseReactions(json['reactions']),
      readCount: _parseInt(json['readCount'] ?? json['read_count']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'botConfigId': botConfigId,
      'botSenderId': botSenderId,
      'botName': botName,
      'botAvatar': botAvatar,
      'chatRoomId': chatRoomId,
      'type': _wireMessageType(type),
      'status': status.name.toUpperCase(),
      'timestamp': timestamp.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'replyToId': replyToId,
      'replyToMessage': replyToMessage?.toJson(),
      'mentionedUserIds': mentionedUserIds,
      'metadata': metadata,
      'replyToMessageId': replyToMessageId,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'fileType': fileType,
      'stickerId': stickerId,
      'pollId': pollId,
      'imageGenPrompt': imageGenPrompt,
      'imageGenStatus': imageGenStatus,
      'imageGenUrl': imageGenUrl,
      'imageGenProviderTaskId': imageGenProviderTaskId,
      'isDeleted': isDeleted,
      'isRecalled': isRecalled,
      'encryptedContent': encryptedContent,
      'encryptionVersion': encryptionVersion,
      'isAnonymous': isAnonymous,
      'anonymousIdentityId': anonymousIdentityId,
      'anonymousName': anonymousName,
      'anonymousAvatar': anonymousAvatar,
      'linkPreview': linkPreview?.toJson(),
      'reactions': reactions.map((item) => item.toJson()).toList(),
      'readCount': readCount,
    };
  }

  Message copyWith({
    String? id,
    String? content,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? botConfigId,
    String? botSenderId,
    String? botName,
    String? botAvatar,
    String? chatRoomId,
    MessageType? type,
    MessageStatus? status,
    DateTime? timestamp,
    DateTime? editedAt,
    String? replyToId,
    Message? replyToMessage,
    List<String>? mentionedUserIds,
    Map<String, dynamic>? metadata,
    String? replyToMessageId,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? fileType,
    int? stickerId,
    int? pollId,
    String? imageGenPrompt,
    String? imageGenStatus,
    String? imageGenUrl,
    String? imageGenProviderTaskId,
    bool? isDeleted,
    bool? isRecalled,
    String? encryptedContent,
    int? encryptionVersion,
    bool? isAnonymous,
    String? anonymousIdentityId,
    String? anonymousName,
    String? anonymousAvatar,
    LinkPreview? linkPreview,
    List<MessageReaction>? reactions,
    int? readCount,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      botConfigId: botConfigId ?? this.botConfigId,
      botSenderId: botSenderId ?? this.botSenderId,
      botName: botName ?? this.botName,
      botAvatar: botAvatar ?? this.botAvatar,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      type: type ?? this.type,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      editedAt: editedAt ?? this.editedAt,
      replyToId: replyToId ?? this.replyToId,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      mentionedUserIds: mentionedUserIds ?? this.mentionedUserIds,
      metadata: metadata ?? this.metadata,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      fileType: fileType ?? this.fileType,
      stickerId: stickerId ?? this.stickerId,
      pollId: pollId ?? this.pollId,
      imageGenPrompt: imageGenPrompt ?? this.imageGenPrompt,
      imageGenStatus: imageGenStatus ?? this.imageGenStatus,
      imageGenUrl: imageGenUrl ?? this.imageGenUrl,
      imageGenProviderTaskId:
          imageGenProviderTaskId ?? this.imageGenProviderTaskId,
      isDeleted: isDeleted ?? this.isDeleted,
      isRecalled: isRecalled ?? this.isRecalled,
      encryptedContent: encryptedContent ?? this.encryptedContent,
      encryptionVersion: encryptionVersion ?? this.encryptionVersion,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      anonymousIdentityId: anonymousIdentityId ?? this.anonymousIdentityId,
      anonymousName: anonymousName ?? this.anonymousName,
      anonymousAvatar: anonymousAvatar ?? this.anonymousAvatar,
      linkPreview: linkPreview ?? this.linkPreview,
      reactions: reactions ?? this.reactions,
      readCount: readCount ?? this.readCount,
    );
  }

  bool get isEdited => editedAt != null;
  bool get hasReply => replyToMessage != null;
  bool get isRemoved => isDeleted || isRecalled;
  bool get isBotMessage =>
      (botConfigId?.isNotEmpty ?? false) ||
      (botSenderId?.isNotEmpty ?? false) ||
      (botName?.trim().isNotEmpty ?? false);
  bool isFromCurrentUser(String? currentUserId) =>
      currentUserId != null && senderId == currentUserId && !isBotMessage;
  String get effectiveBotName {
    final explicit = botName?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return 'AI 助手';
  }

  String get displayContent {
    if (!isBotMessage) return content;
    final name = RegExp.escape(effectiveBotName);
    return content
        .replaceFirst(RegExp('^\\[$name\\]\\s*'), '')
        .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
  }

  bool mentionsUser(String? userId) =>
      userId != null && mentionedUserIds.contains(userId);
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
  bool get isStickerMessage => type == MessageType.sticker;
  bool get isPollMessage => type == MessageType.poll;
  bool get isImageGenerationMessage => type == MessageType.imageGeneration;
  bool get isImageGenerationDone =>
      isImageGenerationMessage && imageGenStatus?.toUpperCase() == 'DONE';
  bool get isImageGenerationFailed =>
      isImageGenerationMessage && imageGenStatus?.toUpperCase() == 'FAILED';
  bool get isFileMessage =>
      type == MessageType.file ||
      (fileUrl != null &&
          !isImageMessage &&
          !isImageGenerationMessage &&
          !isStickerMessage &&
          !isPollMessage &&
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
    if (isStickerMessage) {
      return fileName?.isNotEmpty == true ? '[贴纸] $fileName' : '[贴纸]';
    }
    if (isPollMessage) {
      return content.isNotEmpty ? content : '[投票]';
    }
    if (isImageGenerationMessage) {
      return isImageGenerationDone ? '[AI图片]' : '[AI图片生成中]';
    }
    if (isFileMessage) {
      return fileName?.isNotEmpty == true ? '[文件] $fileName' : '[文件]';
    }
    return content;
  }

  bool hasReactionFrom(String emoji, String? userId) {
    if (userId == null) return false;
    return reactions.any((reaction) =>
        reaction.emoji == emoji && reaction.userIds.contains(userId));
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

  static MessageType _parseMessageType(dynamic value) {
    final normalized =
        value.toString().replaceAll('_', '').replaceAll('-', '').toLowerCase();
    return MessageType.values.firstWhere(
      (type) => type.name.toLowerCase() == normalized,
      orElse: () => MessageType.text,
    );
  }

  static String _wireMessageType(MessageType type) {
    if (type == MessageType.imageGeneration) {
      return 'IMAGE_GENERATION';
    }
    return type.name.toUpperCase();
  }

  static String? _stringOrNull(dynamic value) {
    final string = value?.toString().trim();
    return string == null || string.isEmpty ? null : string;
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString().toLowerCase() == 'true';
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static List<MessageReaction> _parseReactions(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(MessageReaction.fromJson)
        .where((reaction) => reaction.emoji.isNotEmpty && reaction.count > 0)
        .toList();
  }
}
