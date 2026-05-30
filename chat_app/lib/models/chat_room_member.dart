import 'user.dart';

class ChatRoomMember {
  const ChatRoomMember({
    required this.id,
    required this.userId,
    required this.user,
    required this.role,
    this.roleDescription,
    this.nickname,
    this.memberTitle,
    this.isMuted = false,
    this.isPinned = false,
    this.isAdmin = false,
    this.joinedAt,
    this.lastReadMessageId,
    this.unreadCount = 0,
  });

  final String id;
  final String userId;
  final User user;
  final String role;
  final String? roleDescription;
  final String? nickname;
  final String? memberTitle;
  final bool isMuted;
  final bool isPinned;
  final bool isAdmin;
  final DateTime? joinedAt;
  final String? lastReadMessageId;
  final int unreadCount;

  factory ChatRoomMember.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    final parsedUser = userJson is Map<String, dynamic>
        ? User.fromJson(userJson)
        : User(
            id: (json['userId'] ?? json['user_id'] ?? '').toString(),
            username: json['username']?.toString() ?? '',
            email: json['email']?.toString() ?? '',
            displayName: json['displayName']?.toString() ??
                json['display_name']?.toString() ??
                json['username']?.toString() ??
                '',
            avatarUrl:
                json['avatarUrl']?.toString() ?? json['avatar_url']?.toString(),
            createdAt: DateTime.tryParse(
                  (json['createdAt'] ?? json['created_at']).toString(),
                ) ??
                DateTime.now(),
          );

    final roleValue =
        json['role'] ?? json['memberRole'] ?? json['member_role'] ?? 'MEMBER';
    final roleText = roleValue.toString().toUpperCase();
    final unreadValue = json['unreadCount'] ?? json['unread_count'] ?? 0;

    return ChatRoomMember(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'] ?? parsedUser.id).toString(),
      user: parsedUser,
      role: roleValue.toString(),
      roleDescription: json['roleDescription']?.toString() ??
          json['role_description']?.toString(),
      nickname: json['nickname']?.toString(),
      memberTitle: json['memberTitle']?.toString() ??
          json['member_title']?.toString() ??
          json['title']?.toString(),
      isMuted: json['isMuted'] ?? json['is_muted'] ?? false,
      isPinned: json['isPinned'] ?? json['is_pinned'] ?? false,
      isAdmin: json['isAdmin'] ??
          json['is_admin'] ??
          (roleText == 'ADMIN' || roleText == 'OWNER'),
      joinedAt: json['joinedAt'] != null || json['joined_at'] != null
          ? DateTime.tryParse(
              (json['joinedAt'] ?? json['joined_at']).toString(),
            )
          : null,
      lastReadMessageId:
          (json['lastReadMessageId'] ?? json['last_read_message_id'])
              ?.toString(),
      unreadCount: unreadValue is int
          ? unreadValue
          : int.tryParse(unreadValue.toString()) ?? 0,
    );
  }

  String get displayName =>
      nickname?.isNotEmpty == true ? nickname! : user.displayName;

  String get displayTitle =>
      memberTitle?.isNotEmpty == true ? memberTitle! : roleDescription ?? role;

  bool get canBeManaged => role.toUpperCase() != 'OWNER';
}
