class PollOption {
  const PollOption({
    required this.index,
    required this.text,
    required this.votes,
    this.voterIds = const [],
  });

  final int index;
  final String text;
  final int votes;
  final List<String> voterIds;

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
        index: _intValue(json['index']),
        text: json['text']?.toString() ?? '',
        votes: _intValue(json['votes']),
        voterIds: json['voterIds'] is List
            ? (json['voterIds'] as List).map((item) => item.toString()).toList()
            : const [],
      );
}

class PollInfo {
  const PollInfo({
    required this.id,
    required this.messageId,
    required this.question,
    this.options = const [],
    this.multiSelect = false,
    this.anonymous = false,
    this.totalVotes = 0,
    this.expiresAt,
  });

  final int id;
  final int messageId;
  final String question;
  final List<PollOption> options;
  final bool multiSelect;
  final bool anonymous;
  final int totalVotes;
  final DateTime? expiresAt;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory PollInfo.fromJson(Map<String, dynamic> json) => PollInfo(
        id: _intValue(json['id']),
        messageId: _intValue(json['messageId']),
        question: json['question']?.toString() ?? '',
        options: json['options'] is List
            ? (json['options'] as List)
                .whereType<Map<String, dynamic>>()
                .map(PollOption.fromJson)
                .toList()
            : const [],
        multiSelect: json['multiSelect'] == true,
        anonymous: json['anonymous'] == true,
        totalVotes: _intValue(json['totalVotes']),
        expiresAt: _dateOrNull(json['expiresAt']),
      );
}

int _intValue(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _dateOrNull(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
