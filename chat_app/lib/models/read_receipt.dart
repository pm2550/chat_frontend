class ReadReceipt {
  const ReadReceipt({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.readAt,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final DateTime? readAt;

  factory ReadReceipt.fromJson(Map<String, dynamic> json) => ReadReceipt(
        userId: json['userId']?.toString() ?? '',
        displayName: json['displayName']?.toString().isNotEmpty == true
            ? json['displayName'].toString()
            : json['username']?.toString() ?? '',
        avatarUrl: json['avatarUrl']?.toString(),
        readAt: DateTime.tryParse(json['readAt']?.toString() ?? ''),
      );
}
