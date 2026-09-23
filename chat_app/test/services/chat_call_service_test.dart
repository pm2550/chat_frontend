import 'dart:io';

import 'package:chat_app/models/call_state.dart';
import 'package:chat_app/services/chat_call_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatCallService', () {
    final webServiceSource = _ChatCallServiceWebSource();

    Map<String, dynamic> invite(String callId, {String media = 'AUDIO'}) => {
          'action': 'invite',
          'chatRoomId': 42,
          'callId': callId,
          'fromUserId': 7,
          'fromName': 'Alice',
          'mediaType': media,
        };

    test('caller hanging up before answer ends the incoming call', () async {
      final service = ChatCallService(webSocketService: WebSocketService());

      await service.handleSignal(invite('call-1'));
      expect(service.state.phase, CallPhase.incoming);
      expect(service.state.callId, 'call-1');
      expect(service.state.primaryPeerName, 'Alice');
      expect(service.state.participants.single.userId, 7);

      await service.handleSignal({
        'action': 'hangup',
        'chatRoomId': 42,
        'callId': 'call-1',
        'fromUserId': 7,
        'mediaType': 'AUDIO',
      });

      expect(service.state.phase, CallPhase.ended);
      expect(service.state.isActive, isFalse);
      expect(service.state.statusLabel, '对方已取消通话');
    });

    test('a missed call does not make the next call look busy', () async {
      final service = ChatCallService(webSocketService: WebSocketService());

      await service.handleSignal(invite('call-1'));
      await service.handleSignal({
        'action': 'hangup',
        'chatRoomId': 42,
        'callId': 'call-1',
        'fromUserId': 7,
      });
      // 以前这里状态卡在"来电中"，下一通会被当成占线自动拒掉。
      await service.handleSignal(invite('call-2'));

      expect(service.state.phase, CallPhase.incoming);
      expect(service.state.callId, 'call-2');
    });

    test('caller cancelling with reject declines the incoming call', () async {
      final service = ChatCallService(webSocketService: WebSocketService());

      await service.handleSignal(invite('call-3', media: 'VIDEO'));
      await service.handleSignal({
        'action': 'reject',
        'chatRoomId': 42,
        'callId': 'call-3',
        'fromUserId': 7,
        'mediaType': 'VIDEO',
      });

      expect(service.state.isActive, isFalse);
      expect(service.state.statusLabel, '对方已拒绝通话');
    });

    test('rejectIncoming clears the incoming call state', () async {
      final service = ChatCallService(webSocketService: WebSocketService());

      await service.handleSignal(invite('call-4'));
      service.rejectIncoming();

      expect(service.state.isIdle, isTrue);
      expect(service.state.participants, isEmpty);
    });

    test('acceptIncoming fails cleanly when media cannot start', () async {
      // 测试环境没有真实的麦克风/WebRTC 插件，接听应干净地失败而不是抛异常。
      final service = ChatCallService(webSocketService: WebSocketService());

      await service.handleSignal(invite('call-5', media: 'VIDEO'));
      await service.acceptIncoming();

      expect(service.state.phase, CallPhase.failed);
      expect(service.state.isActive, isFalse);
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
