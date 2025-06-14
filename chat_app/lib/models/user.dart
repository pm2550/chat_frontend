class User {
  final String id;
  final String username;
  final String email;
  final String? phone;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final OnlineStatus onlineStatus;
  final DateTime? lastSeen;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<UserRole> roles;

  const User({
    required this.id,
    required this.username,
    required this.email,
    this.phone,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.onlineStatus = OnlineStatus.offline,
    this.lastSeen,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
    this.roles = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      displayName: json['displayName'] ?? json['display_name'] ?? '',
      avatarUrl: json['avatarUrl'] ?? json['avatar_url'],
      bio: json['bio'],
      onlineStatus: OnlineStatus.values.firstWhere(
        (e) => e.name.toUpperCase() == (json['onlineStatus'] ?? json['online_status'] ?? 'OFFLINE').toString().toUpperCase(),
        orElse: () => OnlineStatus.offline,
      ),
      lastSeen: json['lastSeen'] != null || json['last_seen'] != null
          ? DateTime.tryParse((json['lastSeen'] ?? json['last_seen']).toString())
          : null,
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      createdAt: DateTime.tryParse((json['createdAt'] ?? json['created_at']).toString()) ?? DateTime.now(),
      updatedAt: json['updatedAt'] != null || json['updated_at'] != null
          ? DateTime.tryParse((json['updatedAt'] ?? json['updated_at']).toString())
          : null,
      roles: (json['roles'] as List<dynamic>?)
              ?.map((role) => UserRole.values.firstWhere(
                    (e) => e.name.toUpperCase() == role.toString().toUpperCase(),
                    orElse: () => UserRole.user,
                  ))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'phone': phone,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'onlineStatus': onlineStatus.name.toUpperCase(),
      'lastSeen': lastSeen?.toIso8601String(),
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'roles': roles.map((role) => role.name.toUpperCase()).toList(),
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? email,
    String? phone,
    String? displayName,
    String? avatarUrl,
    String? bio,
    OnlineStatus? onlineStatus,
    DateTime? lastSeen,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<UserRole>? roles,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      onlineStatus: onlineStatus ?? this.onlineStatus,
      lastSeen: lastSeen ?? this.lastSeen,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      roles: roles ?? this.roles,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'User(id: $id, username: $username, displayName: $displayName)';
  }
}

enum OnlineStatus {
  online('在线'),
  away('离开'),
  busy('忙碌'),
  offline('离线');

  const OnlineStatus(this.description);
  final String description;
}

enum UserRole {
  user('普通用户'),
  admin('管理员'),
  moderator('版主');

  const UserRole(this.description);
  final String description;
} 