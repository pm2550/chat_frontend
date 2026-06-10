import 'user.dart';
import 'message.dart';

class Chat {
  final String id;
  final String name;
  final String? description;
  final String? announcement;
  final DateTime? announcementUpdatedAt;
  final String? announcementUpdatedBy;
  final ChatType type;
  final String? avatarUrl;
  final List<User> participants;
  final Message? lastMessage;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final DateTime? hiddenAt;
  final bool isBlocked;
  final String? clearedBeforeMessageId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? metadata;
  final String? createdBy;
  final bool isActive;
  final bool isPrivate;
  final int maxMembers;
  final bool anonymousEnabled;
  final String anonymousTheme;
  final String? customBackgroundPreset;
  final String? customBackgroundUrl;

  const Chat({
    required this.id,
    required this.name,
    this.description,
    this.announcement,
    this.announcementUpdatedAt,
    this.announcementUpdatedBy,
    this.type = ChatType.private,
    this.avatarUrl,
    this.participants = const [],
    this.lastMessage,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.hiddenAt,
    this.isBlocked = false,
    this.clearedBeforeMessageId,
    required this.createdAt,
    this.updatedAt,
    this.metadata,
    this.createdBy,
    this.isActive = true,
    this.isPrivate = true,
    this.maxMembers = 500,
    this.anonymousEnabled = false,
    this.anonymousTheme = 'default',
    this.customBackgroundPreset,
    this.customBackgroundUrl,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    final typeValue =
        json['type'] ?? json['roomType'] ?? json['room_type'] ?? 'PRIVATE';
    return Chat(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      announcement: json['announcement']?.toString(),
      announcementUpdatedAt: json['announcementUpdatedAt'] != null ||
              json['announcement_updated_at'] != null
          ? DateTime.tryParse(
              (json['announcementUpdatedAt'] ?? json['announcement_updated_at'])
                  .toString())
          : null,
      announcementUpdatedBy: json['announcementUpdatedBy']?.toString() ??
          json['announcement_updated_by']?.toString(),
      type: ChatType.values.firstWhere(
        (e) => e.name.toUpperCase() == typeValue.toString().toUpperCase(),
        orElse: () => ChatType.private,
      ),
      avatarUrl: json['avatarUrl'] ?? json['avatar_url'],
      participants: (json['participants'] as List<dynamic>?)
              ?.map(
                  (userJson) => User.fromJson(userJson as Map<String, dynamic>))
              .toList() ??
          [],
      createdBy:
          json['createdBy']?.toString() ?? json['created_by']?.toString(),
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      isPrivate: json['isPrivate'] ??
          json['is_private'] ??
          typeValue.toString().toUpperCase() == 'PRIVATE',
      maxMembers: json['maxMembers'] ?? json['max_members'] ?? 500,
      anonymousEnabled:
          json['anonymousEnabled'] ?? json['anonymous_enabled'] ?? false,
      anonymousTheme:
          json['anonymousTheme'] ?? json['anonymous_theme'] ?? 'default',
      customBackgroundPreset:
          json['customBackgroundPreset'] ?? json['custom_background_preset'],
      customBackgroundUrl:
          json['customBackgroundUrl'] ?? json['custom_background_url'],
      createdAt: DateTime.tryParse(
              (json['createdAt'] ?? json['created_at']).toString()) ??
          DateTime.now(),
      updatedAt: json['updatedAt'] != null || json['updated_at'] != null
          ? DateTime.tryParse(
              (json['updatedAt'] ?? json['updated_at']).toString())
          : null,
      lastMessage: json['lastMessage'] != null
          ? Message.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      unreadCount: json['unreadCount'] ?? json['unread_count'] ?? 0,
      isPinned: json['isPinned'] ?? json['is_pinned'] ?? false,
      isMuted: json['isMuted'] ?? json['muted'] ?? json['is_muted'] ?? false,
      hiddenAt: json['hiddenAt'] != null || json['hidden_at'] != null
          ? DateTime.tryParse(
              (json['hiddenAt'] ?? json['hidden_at']).toString())
          : null,
      isBlocked:
          json['isBlocked'] ?? json['blocked'] ?? json['is_blocked'] ?? false,
      clearedBeforeMessageId:
          (json['clearedBeforeMessageId'] ?? json['cleared_before_message_id'])
              ?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'announcement': announcement,
      'announcementUpdatedAt': announcementUpdatedAt?.toIso8601String(),
      'announcementUpdatedBy': announcementUpdatedBy,
      'type': type.name.toUpperCase(),
      'avatarUrl': avatarUrl,
      'participants': participants.map((user) => user.toJson()).toList(),
      'createdBy': createdBy,
      'isActive': isActive,
      'isPrivate': isPrivate,
      'maxMembers': maxMembers,
      'anonymousEnabled': anonymousEnabled,
      'anonymousTheme': anonymousTheme,
      'customBackgroundPreset': customBackgroundPreset,
      'customBackgroundUrl': customBackgroundUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'lastMessage': lastMessage?.toJson(),
      'unreadCount': unreadCount,
      'isPinned': isPinned,
      'isMuted': isMuted,
      'hiddenAt': hiddenAt?.toIso8601String(),
      'isBlocked': isBlocked,
      'clearedBeforeMessageId': clearedBeforeMessageId,
    };
  }

  Chat copyWith({
    String? id,
    String? name,
    String? description,
    String? announcement,
    DateTime? announcementUpdatedAt,
    String? announcementUpdatedBy,
    ChatType? type,
    String? avatarUrl,
    List<User>? participants,
    String? createdBy,
    bool? isActive,
    bool? isPrivate,
    int? maxMembers,
    bool? anonymousEnabled,
    String? anonymousTheme,
    String? customBackgroundPreset,
    String? customBackgroundUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    Message? lastMessage,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    DateTime? hiddenAt,
    bool? isBlocked,
    String? clearedBeforeMessageId,
  }) {
    return Chat(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      announcement: announcement ?? this.announcement,
      announcementUpdatedAt:
          announcementUpdatedAt ?? this.announcementUpdatedAt,
      announcementUpdatedBy:
          announcementUpdatedBy ?? this.announcementUpdatedBy,
      type: type ?? this.type,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      participants: participants ?? this.participants,
      createdBy: createdBy ?? this.createdBy,
      isActive: isActive ?? this.isActive,
      isPrivate: isPrivate ?? this.isPrivate,
      maxMembers: maxMembers ?? this.maxMembers,
      anonymousEnabled: anonymousEnabled ?? this.anonymousEnabled,
      anonymousTheme: anonymousTheme ?? this.anonymousTheme,
      customBackgroundPreset:
          customBackgroundPreset ?? this.customBackgroundPreset,
      customBackgroundUrl: customBackgroundUrl ?? this.customBackgroundUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      hiddenAt: hiddenAt ?? this.hiddenAt,
      isBlocked: isBlocked ?? this.isBlocked,
      clearedBeforeMessageId:
          clearedBeforeMessageId ?? this.clearedBeforeMessageId,
    );
  }

  // 获取聊天显示名称
  String getDisplayName(String currentUserId) {
    if (type == ChatType.group || type == ChatType.channel) {
      return name;
    }

    // 私聊显示对方用户名
    final otherUser = participants.firstWhere(
      (user) => user.id != currentUserId,
      orElse: () => participants.isNotEmpty
          ? participants.first
          : User(
              id: '',
              username: 'Unknown',
              email: '',
              displayName: 'Unknown User',
              createdAt: DateTime.now(),
            ),
    );
    return otherUser.displayName;
  }

  // 获取聊天头像
  String? getDisplayAvatar(String currentUserId) {
    if (avatarUrl != null) return avatarUrl;

    if (type == ChatType.private) {
      final otherUser = participants.firstWhere(
        (user) => user.id != currentUserId,
        orElse: () => participants.isNotEmpty
            ? participants.first
            : User(
                id: '',
                username: 'Unknown',
                email: '',
                displayName: 'Unknown User',
                createdAt: DateTime.now(),
              ),
      );
      return otherUser.avatarUrl;
    }

    return null;
  }

  // 获取在线参与者数量
  int get onlineParticipantCount {
    return participants
        .where((user) => user.onlineStatus == OnlineStatus.online)
        .length;
  }

  // 是否有未读消息
  bool get hasUnreadMessages => unreadCount > 0;

  bool get isHidden => hiddenAt != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Chat && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Chat(id: $id, name: $name, type: $type, participants: ${participants.length})';
  }
}

enum ChatType {
  private('私聊'),
  group('群聊'),
  channel('频道');

  const ChatType(this.description);
  final String description;
}
