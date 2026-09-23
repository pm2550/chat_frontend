import 'dart:convert';

import 'package:chat_app/services/notification_tap_router.dart';
import 'package:chat_app/services/pending_call_invite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a message notification opens its chat', () {
    final route = NotificationTapRouter.routeForPayload(
      jsonEncode({'type': 'message', 'chatRoomId': 42, 'messageId': 7}),
    );

    expect(route, '/chat/42');
    expect(PendingCallInvite.takeFor('42'), isNull);
  });

  test('a fresh call notification opens the chat and queues the invite', () {
    final now = DateTime(2026, 9, 24, 12);
    final route = NotificationTapRouter.routeForPayload(
      jsonEncode({
        'type': 'call',
        'action': 'invite',
        'chatRoomId': 42,
        'callId': 'call-1',
        'fromUserId': 9,
        'fromName': '小王',
        'mediaType': 'AUDIO',
        'receivedAt': now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
      }),
    );

    expect(route, '/chat/42');
    final invite = PendingCallInvite.takeFor('42', now: now);
    expect(invite?['callId'], 'call-1');
    expect(invite?['action'], 'invite');
    // 取一次就清空
    expect(PendingCallInvite.takeFor('42', now: now), isNull);
  });

  test('a stale call notification no longer rings', () {
    final now = DateTime(2026, 9, 24, 12);
    NotificationTapRouter.routeForPayload(
      jsonEncode({
        'type': 'call',
        'chatRoomId': 42,
        'callId': 'old-call',
        'receivedAt': now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
      }),
    );

    expect(PendingCallInvite.takeFor('42', now: now), isNull);
  });

  test('an invite for another chat is not handed to this one', () {
    PendingCallInvite.put({'chatRoomId': 1, 'callId': 'c'});

    expect(PendingCallInvite.takeFor('2'), isNull);
    expect(PendingCallInvite.takeFor('1')?['callId'], 'c');
  });

  test('garbage payloads are ignored', () {
    expect(NotificationTapRouter.routeForPayload(null), isNull);
    expect(NotificationTapRouter.routeForPayload('not json'), isNull);
    expect(NotificationTapRouter.routeForPayload('{"type":"message"}'), isNull);
  });
}
