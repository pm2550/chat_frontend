import 'package:chat_app/models/call_state.dart';
import 'package:chat_app/services/chat_call_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatCallService', () {
    test('incoming call moves to ended when caller hangs up before answer',
        () async {
      final service = ChatCallService(webSocketService: WebSocketService());

      await service.handleSignal({
        'action': 'invite',
        'chatRoomId': 42,
        'callId': 'call-1',
        'fromUserId': 7,
        'fromName': 'Alice',
        'mediaType': 'AUDIO',
      });

      expect(service.state.phase, CallPhase.incoming);
      expect(service.state.callId, 'call-1');
      expect(service.state.primaryPeerName, 'Alice');
      expect(service.state.participants.single.userId, 7);

      await service.handleSignal({
        'action': 'hangup',
        'chatRoomId': 42,
        'callId': 'call-1',
        'fromUserId': 7,
        'fromName': 'Alice',
        'mediaType': 'AUDIO',
      });

      expect(service.state.phase, CallPhase.ended);
      expect(service.state.statusLabel, '通话已结束');
    });

    test('incoming call moves to ended when caller rejects/cancels', () async {
      final service = ChatCallService(webSocketService: WebSocketService());

      await service.handleSignal({
        'action': 'invite',
        'chatRoomId': 42,
        'callId': 'call-2',
        'fromUserId': 7,
        'mediaType': 'VIDEO',
      });

      await service.handleSignal({
        'action': 'reject',
        'chatRoomId': 42,
        'callId': 'call-2',
        'fromUserId': 7,
        'mediaType': 'VIDEO',
      });

      expect(service.state.phase, CallPhase.ended);
      expect(service.state.statusLabel, '对方已拒绝通话');
    });

    test('rejectIncoming clears unsupported incoming call state', () async {
      final service = ChatCallService(webSocketService: WebSocketService());

      await service.handleSignal({
        'action': 'invite',
        'chatRoomId': 42,
        'callId': 'call-3',
        'fromUserId': 7,
        'fromName': 'Alice',
        'mediaType': 'AUDIO',
      });

      service.rejectIncoming();

      expect(service.state.isIdle, isTrue);
      expect(service.state.participants, isEmpty);
    });

    test('acceptIncoming fails cleanly on unsupported platforms', () async {
      final service = ChatCallService(webSocketService: WebSocketService());

      await service.handleSignal({
        'action': 'invite',
        'chatRoomId': 42,
        'callId': 'call-4',
        'fromUserId': 7,
        'mediaType': 'VIDEO',
      });

      await service.acceptIncoming();

      expect(service.state.phase, CallPhase.failed);
      expect(service.state.statusLabel, '当前平台暂不支持浏览器实时通话');
    });
  });
}
