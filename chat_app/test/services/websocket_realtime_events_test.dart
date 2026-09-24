import 'dart:async';
import 'dart:convert';

import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WebSocketService service;

  setUp(() {
    service = WebSocketService.forTesting(authService: _OfflineAuthService());
  });

  Future<List<T>> collect<T>(Stream<T> stream, void Function() emit) async {
    final events = <T>[];
    final sub = stream.listen(events.add);
    emit();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return events;
  }

  test('pin message_action is exposed with the fresh pin list', () async {
    final events = await collect(service.onMessageAction, () {
      service.handleMessageForTest(jsonEncode({
        'type': 'message_action',
        'chatRoomId': 7,
        'action': 'pin_added',
        'data': {
          'messageId': 55,
          'pins': [
            {
              'id': 55,
              'content': '置顶内容',
              'senderId': 2,
              'senderName': 'Bob',
              'chatRoomId': 7,
              'createdAt': '2026-09-24T10:00:00',
            },
          ],
        },
      }));
    });

    expect(events, hasLength(1));
    expect(events.single.isPinChange, isTrue);
    expect(events.single.chatRoomId, '7');
    expect(events.single.messageId, '55');
    expect(events.single.pins!.single.content, '置顶内容');
    expect(service.pinnedMessagesFor('7')!.single.id, '55');
  });

  test('star message_action reaches listeners as a star change', () async {
    final events = await collect(service.onMessageAction, () {
      service.handleMessageForTest(jsonEncode({
        'type': 'message_action',
        'chatRoomId': 7,
        'action': 'star_removed',
        'data': {'messageId': 55, 'userId': 1},
      }));
    });

    expect(events.single.isStarChange, isTrue);
    expect(events.single.pins, isNull);
    expect(service.pinnedMessagesFor('7'), isNull);
  });

  test('room sync events are forwarded to status listeners', () async {
    final events = await collect(service.onStatusChange, () {
      for (final type in [
        'room_display_state_changed',
        'room_membership_added',
        'room_membership_removed',
      ]) {
        service.handleMessageForTest(jsonEncode({
          'type': type,
          'chatRoomId': 7,
        }));
      }
    });

    expect(events.map((event) => event['type']), [
      'room_display_state_changed',
      'room_membership_added',
      'room_membership_removed',
    ]);
  });

  test('legacy duplicate typing frame is ignored', () async {
    final snapshot = {
      'chatRoomId': 7,
      'userIds': [2],
      'userNames': ['Bob'],
    };
    final events = await collect(service.onTyping, () {
      service.handleMessageForTest(
          jsonEncode({'type': 'typing_aggregated', ...snapshot}));
      service.handleMessageForTest(jsonEncode({'type': 'typing', ...snapshot}));
    });

    expect(events, hasLength(1));
    expect(events.single['type'], 'typing_aggregated');
  });
}

class _OfflineAuthService extends AuthService {
  _OfflineAuthService() : super.test();

  @override
  String? get accessToken => null;

  @override
  Future<bool> ensureAuthenticated() async => false;
}
