import 'package:chat_app/models/chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = Chat(
    id: '9',
    name: '旧群名',
    type: ChatType.group,
    createdAt: DateTime(2026, 9, 1),
    avatarUrl: '/api/files/avatar/old.png',
    customBackgroundUrl: '/api/files/bg/old.png',
    announcement: '旧公告',
    memberCount: 5,
    unreadCount: 3,
    isPinned: true,
    isMuted: true,
  );

  test('room_updated snapshot clears fields the server no longer has', () {
    final updated = base.withRoomUpdate({
      'id': 9,
      'name': '新群名',
      'roomType': 'GROUP',
      'anonymousEnabled': true,
      'memberCount': 4,
    });

    expect(updated.name, '新群名');
    expect(updated.customBackgroundUrl, isNull);
    expect(updated.avatarUrl, isNull);
    expect(updated.announcement, isNull);
    expect(updated.anonymousEnabled, isTrue);
    expect(updated.memberCount, 4);
  });

  test('room_updated keeps my own per-room state', () {
    final updated = base.withRoomUpdate({'id': 9, 'name': '新群名'});

    expect(updated.unreadCount, 3);
    expect(updated.isPinned, isTrue);
    expect(updated.isMuted, isTrue);
    expect(updated.type, ChatType.group);
    expect(updated.memberCount, 5);
  });
}
