import 'user.dart';
import 'message.dart';

enum ChatType {
  private,
  group,
  channel,
}

class Chat {
  final String id;
  final String name;
  final String? description;
  final String? avatar;
  final ChatType type;
  final List<User> participants;
  final Message? lastMessage;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  Chat({
    required this.id,
    required this.name,
    this.description,
    this.avatar,
    required this.type,
    required this.participants,
    this.lastMessage,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      avatar: json['avatar'] as String?,
      type: ChatType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => ChatType.private,
      ),
      participants: (json['participants'] as List)
          .map((p) => User.fromJson(p as Map<String, dynamic>))
          .toList(),
      lastMessage: json['lastMessage'] != null
          ? Message.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      isPinned: json['isPinned'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      createdBy: json['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'avatar': avatar,
      'type': type.toString().split('.').last,
      'participants': participants.map((p) => p.toJson()).toList(),
      'lastMessage': lastMessage?.toJson(),
      'unreadCount': unreadCount,
      'isPinned': isPinned,
      'isMuted': isMuted,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'createdBy': createdBy,
    };
  }

  Chat copyWith({
    String? id,
    String? name,
    String? description,
    String? avatar,
    ChatType? type,
    List<User>? participants,
    Message? lastMessage,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return Chat(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatar: avatar ?? this.avatar,
      type: type ?? this.type,
      participants: participants ?? this.participants,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  String get displayName {
    if (type == ChatType.private && participants.length == 2) {
      // 对于私聊，显示对方的名字
      return participants.firstWhere((u) => u.id != createdBy).name;
    }
    return name;
  }

  String? get displayAvatar {
    if (type == ChatType.private && participants.length == 2) {
      // 对于私聊，显示对方的头像
      return participants.firstWhere((u) => u.id != createdBy).avatar;
    }
    return avatar;
  }

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