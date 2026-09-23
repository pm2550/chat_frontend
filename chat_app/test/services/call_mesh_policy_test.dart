import 'package:chat_app/services/call_mesh_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldCreateMeshOffer', () {
    test('smaller self user id creates offer', () {
      expect(shouldCreateMeshOffer(selfUserId: 5, peerUserId: 10), isTrue);
    });

    test('larger self user id waits for offer', () {
      expect(shouldCreateMeshOffer(selfUserId: 10, peerUserId: 5), isFalse);
    });

    test('adjacent ids are deterministic', () {
      expect(shouldCreateMeshOffer(selfUserId: 8, peerUserId: 9), isTrue);
      expect(shouldCreateMeshOffer(selfUserId: 9, peerUserId: 8), isFalse);
    });
  });

  group('isOwnCallSignalEcho', () {
    test('ignores signalling that the user sent', () {
      expect(
        isOwnCallSignalEcho(action: 'offer', fromUserId: 5, selfUserId: 5),
        isTrue,
      );
      expect(
        isOwnCallSignalEcho(action: 'hangup', fromUserId: 5, selfUserId: 5),
        isTrue,
      );
    });

    test('keeps server confirmations addressed to the user', () {
      // 老服务器的 join_accepted 带的是本人 id；丢掉它，被叫 id 更小时通话会卡死。
      expect(
        isOwnCallSignalEcho(
            action: 'join_accepted', fromUserId: 5, selfUserId: 5),
        isFalse,
      );
      expect(
        isOwnCallSignalEcho(action: 'error', fromUserId: 5, selfUserId: 5),
        isFalse,
      );
    });

    test('keeps signalling from other people', () {
      expect(
        isOwnCallSignalEcho(action: 'offer', fromUserId: 7, selfUserId: 5),
        isFalse,
      );
      expect(
        isOwnCallSignalEcho(action: 'offer', fromUserId: 7, selfUserId: null),
        isFalse,
      );
    });
  });
}
