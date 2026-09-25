import '../services/e2ee/e2ee_constants.dart';
import '../utils/date_time_utils.dart';

enum MessageType {
  text('文本'),
  image('图片'),
  file('文件'),
  voice('语音'),
  video('视频'),
  // 后端 AUDIO：音频文件（机器人发的 mp3/wav/ogg、按音频上传的附件），和语音一样用播放器展示。
  audio('音频'),
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

/// Rendering format of a message body. Only bot/agent/system messages ever carry
/// a non-plain value; defaults to plain for older servers/clients.
enum MessageContentFormat { plain, markdown, card }

class Message {
  final String id;
  final String content;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String? senderTitle;
  final String? senderTitleColor;
  final String senderTitleEffect;
  final String? botConfigId;
  final String? botSenderId;
  final String? botName;
  final String? botAvatar;
  final String chatRoomId;
  final MessageType type;
  final MessageContentFormat contentFormat;
  final MessageStatus status;
  final DateTime timestamp;
  final DateTime? editedAt;
  final String? replyToId;
  final Message? replyToMessage;
  final String? forwardedFromMessageId;
  final List<String> mentionedUserIds;
  final Map<String, dynamic>? metadata;
  final String? replyToMessageId;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? fileType;

  /// 图片的小预览图（长边约 400px）。聊天气泡、文件中心先加载它，点开再下载原图 [fileUrl]。
  /// 老消息、小图、动图没有；端到端加密的图片只有信封里带了它的密钥才保留（见 EncryptionService.reveal）。
  final String? thumbnailUrl;
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

  /// 发送端生成的临时 id：本地"发送中"气泡用它当 id，服务器推回（或拒绝）时原样带回，
  /// 据此把临时气泡换成正式消息或标成失败。只在本机有意义，服务器不存。
  final String? clientMessageId;
  /// 当前用户是否收藏了这条消息（后端按请求用户填充 `starredByMe`）。
  final bool starredByMe;

  /// 这条消息是不是"我"发的，后端按查看者计算。匿名消息对别人不带 senderId，
  /// 发送者只能靠它认出自己的匿名消息；老服务器/老缓存没有这个字段时为 null。
  final bool? sentByMe;

  const Message({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    this.senderTitle,
    this.senderTitleColor,
    this.senderTitleEffect = 'none',
    this.botConfigId,
    this.botSenderId,
    this.botName,
    this.botAvatar,
    required this.chatRoomId,
    this.type = MessageType.text,
    this.contentFormat = MessageContentFormat.plain,
    this.status = MessageStatus.sending,
    required this.timestamp,
    this.editedAt,
    this.replyToId,
    this.replyToMessage,
    this.forwardedFromMessageId,
    this.mentionedUserIds = const [],
    this.metadata,
    this.replyToMessageId,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.fileType,
    this.thumbnailUrl,
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
    this.clientMessageId,
    this.starredByMe = false,
    this.sentByMe,
  });

  /// 端到端加密：解析出来的加密消息交给它换成明文（EncryptionService.install 装上）。
  /// 历史、实时推送、回复引用、置顶、收藏、会话列表都经过 fromJson，一处解密处处可见。
  /// 没装时加密消息显示服务器写的占位文字。
  static Message Function(Message message)? contentRevealer;

  factory Message.fromJson(Map<String, dynamic> json,
      {String? fallbackChatRoomId}) {
    final message = Message._fromJson(json, fallbackChatRoomId: fallbackChatRoomId);
    final revealer = contentRevealer;
    return revealer != null && message.isEncrypted ? revealer(message) : message;
  }

  factory Message._fromJson(Map<String, dynamic> json,
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
      senderTitle: isAnonymous
          ? null
          : _stringOrNull(
              json['senderTitle'] ??
                  json['sender_title'] ??
                  senderJson?['title'],
            ),
      senderTitleColor: isAnonymous
          ? null
          : _stringOrNull(
              json['senderTitleColor'] ??
                  json['sender_title_color'] ??
                  senderJson?['titleColor'] ??
                  senderJson?['title_color'],
            ),
      senderTitleEffect: isAnonymous
          ? 'none'
          : (_stringOrNull(
                json['senderTitleEffect'] ??
                    json['sender_title_effect'] ??
                    senderJson?['titleEffect'] ??
                    senderJson?['title_effect'],
              ) ??
              'none'),
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
      contentFormat:
          _parseContentFormat(json['contentFormat'] ?? json['content_format']),
      status: MessageStatus.values.firstWhere(
        (e) => e.name.toUpperCase() == statusValue.toString().toUpperCase(),
        orElse: () => MessageStatus.sent,
      ),
      timestamp: parseServerDateTime(timestampValue) ?? DateTime.now(),
      editedAt: json['editedAt'] != null || json['edited_at'] != null
          ? parseServerDateTime(json['editedAt'] ?? json['edited_at'])
          : null,
      replyToId: json['replyToId']?.toString(),
      replyToMessage: json['replyToMessage'] != null
          ? Message.fromJson(
              json['replyToMessage'] as Map<String, dynamic>,
              fallbackChatRoomId: fallbackChatRoomId,
            )
          : null,
      forwardedFromMessageId:
          (json['forwardedFromMessageId'] ?? json['forwarded_from_message_id'])
              ?.toString(),
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
      thumbnailUrl: _stringOrNull(json['thumbnailUrl'] ?? json['thumbnail_url']),
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
      clientMessageId: _stringOrNull(json['clientMessageId']),
      starredByMe: _parseBool(json['starredByMe'] ?? json['starred_by_me']),
      sentByMe: _parseNullableBool(json['sentByMe'] ?? json['sent_by_me']),
    );
  }

  Map<String, dynamic> toJson() {
    // 加密消息按服务器原样写回（占位文字 + 密文），明文不落进本地缓存；
    // 读回来时再经 fromJson 解密。
    final encrypted = isEncrypted;
    final encryptedAttachment = encrypted && fileUrl != null;
    return {
      'id': id,
      'content': encrypted ? kE2eeServerPlaceholder : content,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'senderTitle': senderTitle,
      'senderTitleColor': senderTitleColor,
      'senderTitleEffect': senderTitleEffect,
      'botConfigId': botConfigId,
      'botSenderId': botSenderId,
      'botName': botName,
      'botAvatar': botAvatar,
      'chatRoomId': chatRoomId,
      'type': encryptedAttachment ? 'FILE' : _wireMessageType(type),
      'status': status.name.toUpperCase(),
      'timestamp': timestamp.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'replyToId': replyToId,
      'replyToMessage': replyToMessage?.toJson(),
      'forwardedFromMessageId': forwardedFromMessageId,
      'mentionedUserIds': mentionedUserIds,
      'metadata': metadata,
      'replyToMessageId': replyToMessageId,
      'fileUrl': fileUrl,
      'fileName': encryptedAttachment ? kE2eeServerAttachmentName : fileName,
      'fileSize': fileSize,
      'fileType': encryptedAttachment ? 'application/octet-stream' : fileType,
      'thumbnailUrl': thumbnailUrl,
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
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
      'starredByMe': starredByMe,
      if (sentByMe != null) 'sentByMe': sentByMe,
    };
  }

  Message copyWith({
    String? id,
    String? content,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? senderTitle,
    String? senderTitleColor,
    String? senderTitleEffect,
    String? botConfigId,
    String? botSenderId,
    String? botName,
    String? botAvatar,
    String? chatRoomId,
    MessageType? type,
    MessageContentFormat? contentFormat,
    MessageStatus? status,
    DateTime? timestamp,
    DateTime? editedAt,
    String? replyToId,
    Message? replyToMessage,
    String? forwardedFromMessageId,
    List<String>? mentionedUserIds,
    Map<String, dynamic>? metadata,
    String? replyToMessageId,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? fileType,
    String? thumbnailUrl,
    bool clearThumbnailUrl = false,
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
    String? clientMessageId,
    bool? starredByMe,
    bool? sentByMe,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      senderTitle: senderTitle ?? this.senderTitle,
      senderTitleColor: senderTitleColor ?? this.senderTitleColor,
      senderTitleEffect: senderTitleEffect ?? this.senderTitleEffect,
      botConfigId: botConfigId ?? this.botConfigId,
      botSenderId: botSenderId ?? this.botSenderId,
      botName: botName ?? this.botName,
      botAvatar: botAvatar ?? this.botAvatar,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      type: type ?? this.type,
      contentFormat: contentFormat ?? this.contentFormat,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      editedAt: editedAt ?? this.editedAt,
      replyToId: replyToId ?? this.replyToId,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      forwardedFromMessageId:
          forwardedFromMessageId ?? this.forwardedFromMessageId,
      mentionedUserIds: mentionedUserIds ?? this.mentionedUserIds,
      metadata: metadata ?? this.metadata,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      fileType: fileType ?? this.fileType,
      thumbnailUrl:
          clearThumbnailUrl ? null : (thumbnailUrl ?? this.thumbnailUrl),
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
      clientMessageId: clientMessageId ?? this.clientMessageId,
      starredByMe: starredByMe ?? this.starredByMe,
      sentByMe: sentByMe ?? this.sentByMe,
    );
  }

  bool get isEdited => editedAt != null;
  bool get hasReply => replyToMessage != null;
  bool get isRemoved => isDeleted || isRecalled;
  bool get isBotMessage =>
      (botConfigId?.isNotEmpty ?? false) ||
      (botSenderId?.isNotEmpty ?? false) ||
      (botName?.trim().isNotEmpty ?? false);
  /// "是不是我发的"的唯一判断：以服务器按查看者算好的 [sentByMe] 为准；
  /// 没有它时（老服务器）普通消息退回比较 senderId，匿名消息一律不是——
  /// 匿名消息不能靠 senderId 认人。
  bool isFromCurrentUser(String? currentUserId) {
    if (isBotMessage) return false;
    final mine = sentByMe;
    if (mine != null) return mine;
    if (isAnonymous) return false;
    return currentUserId != null && senderId == currentUserId;
  }
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
      type == MessageType.audio ||
      (fileType?.toLowerCase().startsWith('audio/') ?? false);
  bool get isVideoMessage =>
      type == MessageType.video ||
      (fileType?.toLowerCase().startsWith('video/') ?? false) ||
      _hasAnyLowercaseSuffix(fileName, _videoFileExtensions) ||
      _hasAnyLowercaseSuffix(fileUrl, _videoFileExtensions) ||
      _hasAnyLowercaseSuffix(content, _videoFileExtensions);
  bool get isLocationMessage => type == MessageType.location;
  bool get isStickerMessage => type == MessageType.sticker;
  bool get isPollMessage => type == MessageType.poll;
  bool get isImageGenerationMessage => type == MessageType.imageGeneration;
  bool get isImageGenerationDone =>
      isImageGenerationMessage && imageGenStatus?.toUpperCase() == 'DONE';
  bool get isImageGenerationFailed =>
      isImageGenerationMessage && imageGenStatus?.toUpperCase() == 'FAILED';
  String? get previewImageUrl {
    if (isImageMessage) {
      return fileUrl?.isNotEmpty == true ? fileUrl : null;
    }
    if (isImageGenerationDone) {
      if (fileUrl?.isNotEmpty == true) return fileUrl;
      if (imageGenUrl?.isNotEmpty == true) return imageGenUrl;
    }
    return null;
  }

  bool get hasPreviewImage => previewImageUrl != null;

  /// 聊天气泡里显示的图：有小预览图就用它（几十 KB），没有就退回原图。
  String? get bubbleImageUrl {
    if (previewImageUrl == null) return null;
    final thumbnail = thumbnailUrl;
    return thumbnail != null && thumbnail.isNotEmpty ? thumbnail : previewImageUrl;
  }

  bool get isFileMessage =>
      (type == MessageType.file && !isVoiceMessage && !isVideoMessage) ||
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
      final label = type == MessageType.audio ? '[音频]' : '[语音]';
      return fileName?.isNotEmpty == true ? '$label $fileName' : label;
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

  static MessageContentFormat _parseContentFormat(dynamic value) {
    if (value == null) return MessageContentFormat.plain;
    final normalized = value.toString().toLowerCase();
    return MessageContentFormat.values.firstWhere(
      (format) => format.name == normalized,
      orElse: () => MessageContentFormat.plain,
    );
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

  static bool? _parseNullableBool(dynamic value) {
    if (value == null) return null;
    return _parseBool(value);
  }

  static const Set<String> _videoFileExtensions = {
    '.mp4',
    '.m4v',
    '.mov',
    '.webm',
    '.mkv',
    '.avi',
    '.3gp',
    '.3gpp',
    '.mpeg',
    '.mpg',
  };

  static bool _hasAnyLowercaseSuffix(String? value, Set<String> suffixes) {
    if (value == null || value.trim().isEmpty) return false;
    final normalized = value.toLowerCase().split('?').first.split('#').first;
    return suffixes.any((suffix) => normalized.endsWith(suffix));
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
