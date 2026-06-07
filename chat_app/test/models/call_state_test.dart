import 'package:chat_app/models/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatCallState', () {
    test('self and others are derived from selfUserId', () {
      const state = ChatCallState(
        selfUserId: 2,
        participants: [
          CallParticipant(userId: 1, displayName: 'Alice'),
          CallParticipant(userId: 2, displayName: 'Me', localViewId: 'local'),
          CallParticipant(userId: 3, displayName: 'Carol'),
        ],
      );

      expect(state.self?.displayName, 'Me');
      expect(state.others.map((p) => p.userId), [1, 3]);
    });

    test('isFull is true at six participants', () {
      final state = ChatCallState(
        participants: [
          for (var id = 1; id <= 6; id++)
            CallParticipant(userId: id, displayName: 'U$id'),
        ],
      );

      expect(state.isFull, isTrue);
    });

    test('addParticipant replaces existing participant immutably', () {
      const state = ChatCallState(
        participants: [CallParticipant(userId: 2, displayName: 'Old')],
      );

      final next = state.addParticipant(
        const CallParticipant(
          userId: 2,
          displayName: 'New',
          state: PeerConnectionState.connected,
        ),
      );

      expect(state.participants.single.displayName, 'Old');
      expect(next.participants.single.displayName, 'New');
      expect(next.participants.single.state, PeerConnectionState.connected);
    });

    test('addParticipant keeps deterministic userId order', () {
      const state = ChatCallState(
        participants: [CallParticipant(userId: 5, displayName: 'Five')],
      );

      final next = state
          .addParticipant(const CallParticipant(userId: 9, displayName: 'Nine'))
          .addParticipant(const CallParticipant(userId: 1, displayName: 'One'));

      expect(next.participants.map((p) => p.userId), [1, 5, 9]);
    });

    test('removeParticipant returns a new state without the user', () {
      const state = ChatCallState(
        participants: [
          CallParticipant(userId: 1, displayName: 'Alice'),
          CallParticipant(userId: 2, displayName: 'Bob'),
        ],
      );

      final next = state.removeParticipant(1);

      expect(state.participants.length, 2);
      expect(next.participants.map((p) => p.userId), [2]);
    });

    test('updateParticipant transforms only the matching user', () {
      const state = ChatCallState(
        participants: [
          CallParticipant(userId: 1, displayName: 'Alice'),
          CallParticipant(userId: 2, displayName: 'Bob'),
        ],
      );

      final next = state.updateParticipant(
        2,
        (participant) => participant.copyWith(micMuted: true),
      );

      expect(next.participants.first.micMuted, isFalse);
      expect(next.participants.last.micMuted, isTrue);
    });

    test('updateParticipant returns identical instance when user is missing', () {
      const state = ChatCallState(
        participants: [CallParticipant(userId: 1, displayName: 'Alice')],
      );

      final next = state.updateParticipant(
        99,
        (participant) => participant.copyWith(micMuted: true),
      );

      expect(identical(state, next), isTrue);
    });

    test('hasRemoteMedia checks remote participant view ids', () {
      const state = ChatCallState(
        selfUserId: 1,
        participants: [
          CallParticipant(userId: 1, displayName: 'Self', localViewId: 'local'),
          CallParticipant(userId: 2, displayName: 'Peer', remoteViewId: 'r2'),
        ],
      );

      expect(state.hasRemoteMedia, isTrue);
    });

    test('new outgoing phases expose non-connected user-facing labels', () {
      expect(
        const ChatCallState(phase: CallPhase.outgoing).statusLabel,
        '正在呼叫',
      );
      expect(
        const ChatCallState(phase: CallPhase.ringing).statusLabel,
        '等待对方接听',
      );
      expect(
        const ChatCallState(phase: CallPhase.connecting).statusLabel,
        '正在连接',
      );
      expect(
        const ChatCallState(phase: CallPhase.timeout).statusLabel,
        '对方未应答',
      );
      expect(
        const ChatCallState(phase: CallPhase.declined).statusLabel,
        '对方已拒绝通话',
      );
    });
  });

  group('CallParticipant', () {
    test('copyWith can clear local and remote view ids', () {
      const participant = CallParticipant(
        userId: 1,
        displayName: 'Alice',
        localViewId: 'local',
        remoteViewId: 'remote',
      );

      final next = participant.copyWith(
        clearLocalView: true,
        clearRemoteView: true,
      );

      expect(next.localViewId, isNull);
      expect(next.remoteViewId, isNull);
    });
  });
}
