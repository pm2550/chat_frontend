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
