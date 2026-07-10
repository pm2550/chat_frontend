class ContactGroup {
  const ContactGroup({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ContactGroup.fromJson(Map<String, dynamic> json) {
    return ContactGroup(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sortOrder: _parseInt(json['sortOrder'] ?? json['sort_order']),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sortOrder': sortOrder,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };
}

class ContactGroupAssignment {
  const ContactGroupAssignment({
    required this.groupId,
    required this.targetType,
    required this.targetId,
    this.updatedAt,
  });

  final String groupId;
  final ContactGroupTargetType targetType;
  final String targetId;
  final DateTime? updatedAt;

  String get targetKey => ContactGroupTargetKey.build(targetType, targetId);

  factory ContactGroupAssignment.fromJson(Map<String, dynamic> json) {
    return ContactGroupAssignment(
      groupId:
          json['groupId']?.toString() ?? json['group_id']?.toString() ?? '',
      targetType: _contactGroupTargetTypeFromWire(
        json['targetType']?.toString() ?? json['target_type']?.toString(),
      ),
      targetId:
          json['targetId']?.toString() ?? json['target_id']?.toString() ?? '',
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'targetType': targetType.wireName,
        'targetId': targetId,
        'updatedAt': updatedAt?.toIso8601String(),
      };
}

class ContactGroupBundle {
  const ContactGroupBundle({
    this.groups = const [],
    this.assignments = const [],
  });

  final List<ContactGroup> groups;
  final List<ContactGroupAssignment> assignments;

  factory ContactGroupBundle.fromJson(Map<String, dynamic> json) {
    return ContactGroupBundle(
      groups: _extractList(json, const ['groups', 'data'])
          .whereType<Map<String, dynamic>>()
          .map(ContactGroup.fromJson)
          .toList(),
      assignments: _extractList(json, const ['assignments', 'items'])
          .whereType<Map<String, dynamic>>()
          .map(ContactGroupAssignment.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'groups': groups.map((group) => group.toJson()).toList(),
        'assignments':
            assignments.map((assignment) => assignment.toJson()).toList(),
      };
}

enum ContactGroupTargetType {
  friend,
  room;

  String get wireName => switch (this) {
        ContactGroupTargetType.friend => 'FRIEND',
        ContactGroupTargetType.room => 'ROOM',
      };
}

ContactGroupTargetType _contactGroupTargetTypeFromWire(String? value) {
  return switch ((value ?? '').toUpperCase()) {
    'ROOM' => ContactGroupTargetType.room,
    _ => ContactGroupTargetType.friend,
  };
}

class ContactGroupTargetKey {
  static String build(ContactGroupTargetType type, String targetId) {
    return '${type.wireName}:$targetId';
  }
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

List<dynamic> _extractList(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is List<dynamic>) {
      return value;
    }
    if (value is Map<String, dynamic>) {
      final nested = _extractList(value, keys);
      if (nested.isNotEmpty) return nested;
    }
  }
  return const [];
}
