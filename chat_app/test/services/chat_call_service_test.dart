import 'dart:io';

import 'package:chat_app/models/call_state.dart';
import 'package:chat_app/services/chat_call_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatCallService', () {
    final webServiceSource = _ChatCallServiceWebSource();

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

    test('outgoing call source keeps outgoing until remote media connects', () {
      final startBody = webServiceSource.methodBody('startOutgoingCall');

      expect(startBody, contains('phase: CallPhase.outgoing'));
      expect(startBody, contains("_sendSignal({"));
      expect(startBody, contains("'action': 'invite'"));
      expect(startBody, contains('_startOutgoingTimeout(callId)'));
      expect(
        startBody,
        isNot(contains('phase: CallPhase.connected')),
        reason:
            'Regression guard: local media readiness must not mark the call connected.',
      );
    });

    test('outgoing call timeout source waits 30 seconds before timeout', () {
      final timeoutBody = webServiceSource.methodBody('_startOutgoingTimeout');
      final timeoutActionBody =
          webServiceSource.methodBody('_timeoutOutgoingCall');

      expect(timeoutBody, contains('Timer(const Duration(seconds: 30)'));
      expect(timeoutBody, contains('_state.phase == CallPhase.outgoing'));
      expect(timeoutBody, contains('_state.phase == CallPhase.ringing'));
      expect(
          timeoutBody, isNot(contains('_state.phase == CallPhase.connecting')));
      expect(timeoutBody, contains('_timeoutOutgoingCall()'));
      expect(timeoutActionBody, contains('phase: CallPhase.timeout'));
      expect(timeoutActionBody, contains("errorMessage: '对方未应答'"));
    });

    test('outgoing call timeout source excludes connecting and connected', () {
      final timeoutBody = webServiceSource.methodBody('_startOutgoingTimeout');

      expect(timeoutBody, contains('_state.phase == CallPhase.outgoing'));
      expect(timeoutBody, contains('_state.phase == CallPhase.ringing'));
      expect(
        timeoutBody,
        isNot(contains('_state.phase == CallPhase.connecting')),
        reason:
            'Once the callee accepted, the 30s no-answer timer must stop applying.',
      );
      expect(
          timeoutBody, isNot(contains('_state.phase == CallPhase.connected')));
    });

    test('outgoing call declined source moves to declined phase', () {
      final handleSignalBody = webServiceSource.methodBody('handleSignal');

      expect(handleSignalBody, contains("case 'reject':"));
      expect(handleSignalBody, contains('phase: CallPhase.declined'));
      expect(handleSignalBody, contains('对方已拒绝通话'));
    });
  });
}

class _ChatCallServiceWebSource {
  _ChatCallServiceWebSource()
      : source =
            File('lib/services/chat_call_service_web.dart').readAsStringSync();

  final String source;

  String methodBody(String methodName) {
    final bounds = switch (methodName) {
      'startOutgoingCall' => (
          'Future<void> startOutgoingCall',
          'Future<void> joinExistingCall',
        ),
      'handleSignal' => (
          'Future<void> handleSignal',
          'Future<void> acceptIncoming',
        ),
      '_startOutgoingTimeout' => (
          'void _startOutgoingTimeout',
          'void _timeoutOutgoingCall',
        ),
      '_timeoutOutgoingCall' => (
          'void _timeoutOutgoingCall',
          'void _markPeerState',
        ),
      _ => (methodName, null),
    };
    final start = source.indexOf(bounds.$1);
    if (start < 0) {
      throw StateError('Missing method $methodName');
    }
    final end = bounds.$2 == null ? -1 : source.indexOf(bounds.$2!, start);
    if (end < 0) {
      return source.substring(start);
    }
    return source.substring(start, end);
  }
}
