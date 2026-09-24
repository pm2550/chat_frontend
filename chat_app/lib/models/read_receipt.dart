import '../utils/date_time_utils.dart';

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
        // 整房间已读的读者没有逐条时间，readAt 为空。
        readAt: parseServerDateTime(json['readAt']),
      );
}
