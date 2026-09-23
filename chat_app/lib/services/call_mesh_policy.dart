/// Returns whether this client should create the WebRTC offer for a pair.
///
/// Anti-glare rule: the smaller userId always sends the offer and the larger
/// userId waits for it. That makes simultaneous mesh joins deterministic.
bool shouldCreateMeshOffer({
  required int selfUserId,
  required int peerUserId,
}) {
  return selfUserId < peerUserId;
}

/// 服务器发给本人的确认（加入成功/出错）。老版本服务器在 join_accepted 里带的是本人 id。
const Set<String> kServerToSelfCallActions = {'join_accepted', 'error'};

/// 这条信令是不是自己发出的回声（应忽略）。
///
/// 以前把"发件人是自己"的一律丢掉，连服务器发给本人的 join_accepted 也丢了：
/// 被叫 id 比主叫小时本该由被叫发 offer，被叫却不知道主叫已在房间，双方互等，
/// 通话卡在"连接中"——两个人之间只有一个方向打得通。
bool isOwnCallSignalEcho({
  required String? action,
  required int? fromUserId,
  required int? selfUserId,
}) {
  if (selfUserId == null || fromUserId != selfUserId) return false;
  return !kServerToSelfCallActions.contains(action);
}

