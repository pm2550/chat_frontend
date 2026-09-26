import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/services/chat_room_directory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../screens/chat_list_page_test.dart'
    show FakeChatListService, FakeRealtimeService;

void main() {
  final created = DateTime.parse('2024-01-01T10:00:00');

  Message message(String id, String roomId, {String senderId = 'alice'}) =>
      Message(
        id: id,
        content: 'msg $id',
        senderId: senderId,
        senderName: senderId,
        chatRoomId: roomId,
        timestamp: created.add(const Duration(minutes: 5)),
      );

  Future<(ChatRoomDirectory, FakeRealtimeService, FakeChatListService)>
      loaded(List<Chat> chats) async {
    final realtime = FakeRealtimeService();
    final service = FakeChatListService(chats: chats);
    final directory = ChatRoomDirectory(
      chatService: service,
      realtimeService: realtime,
      currentUserId: () => 'me',
    );
    await directory.conversations.load();
    await directory.privateChats.load();
    return (directory, realtime, service);
  }

  test('splits rooms: groups and channels vs. private chats', () async {
    final (directory, _, _) = await loaded([
      Chat(id: 'g', name: 'G', type: ChatType.group, createdAt: created),
      Chat(id: 'c', name: 'C', type: ChatType.channel, createdAt: created),
      Chat(id: 'p', name: 'P', type: ChatType.private, createdAt: created),
    ]);

    expect(directory.conversations.rooms.map((c) => c.id),
        unorderedEquals(['g', 'c']));
    expect(directory.privateChats.rooms.map((c) => c.id), ['p']);
  });

  test('hiding or blocking a private chat keeps it, blocked unread is 0',
      () async {
    final (directory, realtime, _) = await loaded([
      Chat(
          id: 'p',
          name: 'P',
          type: ChatType.private,
          createdAt: created,
          unreadCount: 4),
    ]);
    expect(directory.privateUnread, 4);

    realtime.emitStatus({
      'type': 'room_display_state_changed',
      'chatRoomId': 'p',
      'state': {
        'isHidden': true,
        'hiddenAt': '2024-01-01T11:00:00',
        'unreadCount': 0,
      },
    });
    await pumpEventQueue();
    expect(directory.privateChats.roomById('p')?.isHidden, isTrue);

    realtime.emitStatus({
      'type': 'room_display_state_changed',
      'chatRoomId': 'p',
      'state': {'isBlocked': true, 'hiddenAt': '2024-01-01T11:00:00'},
    });
    await pumpEventQueue();
    expect(directory.privateChats.roomById('p')?.isBlocked, isTrue);

    final activities = <ChatRoomMessageActivity>[];
    directory.messageActivity.listen(activities.add);
    realtime.emitMessage(message('m1', 'p'));
    await pumpEventQueue();

    // 屏蔽的会话来了消息：预览更新，但不计未读，页面据 previous.isBlocked 不提醒。
    expect(directory.privateChats.roomById('p')?.lastMessage?.id, 'm1');
    expect(directory.privateUnread, 0);
    expect(activities.single.previous.isBlocked, isTrue);
    expect(activities.single.scope, ChatRoomScope.privateChats);
  });

  test('messages for unknown rooms refresh the message tab list only',
      () async {
    final (directory, realtime, service) = await loaded([
      Chat(id: 'g', name: 'G', type: ChatType.group, createdAt: created),
      Chat(id: 'p', name: 'P', type: ChatType.private, createdAt: created),
    ]);
    expect(service.forceRefreshRequests, [false]);

    realtime.emitMessage(message('m1', 'p'));
    await pumpEventQueue();
    expect(service.forceRefreshRequests, [false]);
    expect(directory.privateUnread, 1);

    // 新群：消息页那一份强制刷新。
    service.chats = [
      ...service.chats,
      Chat(id: 'g2', name: 'G2', type: ChatType.group, createdAt: created),
    ];
    realtime.emitMessage(message('m2', 'g2'));
    await pumpEventQueue();
    expect(service.forceRefreshRequests, [false, true]);
    expect(directory.conversations.contains('g2'), isTrue);
  });

  test('concurrent loads are merged into one follow-up request', () async {
    final (directory, _, service) = await loaded([
      Chat(id: 'g', name: 'G', type: ChatType.group, createdAt: created),
    ]);
    service.forceRefreshRequests.clear();

    await Future.wait([
      directory.conversations.load(),
      directory.conversations.load(forceRefresh: true),
      directory.conversations.load(),
    ]);

    expect(service.forceRefreshRequests, [false, true]);
  });
}
