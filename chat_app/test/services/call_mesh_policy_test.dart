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
}
