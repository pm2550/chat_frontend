/// Visibility of a room memory entry. ROOM entries are shared with every member
/// and injected into bot context; PRIVATE entries are visible only to their author.
enum MemoryVisibility { room, private }

/// Who created the memory entry.
enum MemorySourceType { bot, user, service }

/// Mirrors the backend `MemoryDto` returned by /api/v1/rooms/{roomId}/memories.
class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.chatRoomId,
    required this.title,
    required this.content,
    this.keywords,
    required this.sourceType,
    required this.visibility,
    this.pinned = false,
    this.archived = false,
    this.authorUserId,
    this.authorBotConfigId,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int chatRoomId;
  final String title;
  final String content;
  final String? keywords;
  final MemorySourceType sourceType;
  final MemoryVisibility visibility;
  final bool pinned;
  final bool archived;
  final int? authorUserId;
  final int? authorBotConfigId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPrivate => visibility == MemoryVisibility.private;
  bool get isRoom => visibility == MemoryVisibility.room;

  /// Wire string for the `visibility` request field.
  String get visibilityWire =>
      visibility == MemoryVisibility.private ? 'PRIVATE' : 'ROOM';

  static MemoryVisibility visibilityFromString(String? value) =>
      (value ?? '').toUpperCase() == 'PRIVATE'
          ? MemoryVisibility.private
          : MemoryVisibility.room;

  static MemorySourceType sourceFromString(String? value) {
    switch ((value ?? '').toUpperCase()) {
      case 'BOT':
        return MemorySourceType.bot;
      case 'SERVICE':
        return MemorySourceType.service;
      default:
        return MemorySourceType.user;
    }
  }

  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) =>
        v == null ? null : (v is int ? v : int.tryParse(v.toString()));
    DateTime? asDate(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return MemoryEntry(
      id: asInt(json['id']) ?? 0,
      chatRoomId: asInt(json['chatRoomId'] ?? json['chat_room_id']) ?? 0,
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      keywords: json['keywords']?.toString(),
      sourceType: sourceFromString(
          json['sourceType']?.toString() ?? json['source_type']?.toString()),
      visibility: visibilityFromString(json['visibility']?.toString()),
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
      authorUserId: asInt(json['authorUserId'] ?? json['author_user_id']),
      authorBotConfigId:
          asInt(json['authorBotConfigId'] ?? json['author_bot_config_id']),
      createdAt: asDate(json['createdAt'] ?? json['created_at']),
      updatedAt: asDate(json['updatedAt'] ?? json['updated_at']),
    );
  }
}
