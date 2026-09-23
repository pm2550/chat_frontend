/// 从"来电"通知点进来时暂存的邀请：聊天页打开后取出，按正常来电流程弹接听框。
class PendingCallInvite {
  PendingCallInvite._();

  /// 对方最多等 30 秒；超过这个时间再点通知，对方早已挂断，不再弹接听框。
  static const Duration maxAge = Duration(seconds: 45);

  static Map<String, dynamic>? _invite;
  static DateTime? _receivedAt;

  static void put(Map<String, dynamic> invite, {DateTime? receivedAt}) {
    _invite = Map<String, dynamic>.from(invite);
    _receivedAt = receivedAt ?? DateTime.now();
  }

  /// 取出属于这个聊天室、且还没过期的邀请（取一次就清空）。
  static Map<String, dynamic>? takeFor(String chatRoomId, {DateTime? now}) {
    final invite = _invite;
    final receivedAt = _receivedAt;
    if (invite == null || receivedAt == null) return null;
    if (invite['chatRoomId']?.toString() != chatRoomId) return null;
    _invite = null;
    _receivedAt = null;
    if ((now ?? DateTime.now()).difference(receivedAt) > maxAge) return null;
    return {...invite, 'action': 'invite'};
  }
}
