import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/user.dart';

void main() {
  group('Chat', () {
    test('fromJson creates chat with all fields', () {
      final json = {
        'id': 10,
        'name': 'Test Group',
        'description': 'A test group chat',
        'type': 'GROUP',
        'avatarUrl': 'https://example.com/group.jpg',
        'isActive': true,
        'isPrivate': false,
        'maxMembers': 200,
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-06-01T00:00:00.000Z',
        'unreadCount': 5,
        'isBlocked': true,
        'hiddenAt': '2024-06-01T01:00:00.000Z',
        'clearedBeforeMessageId': 88,
      };

      final chat = Chat.fromJson(json);

      expect(chat.id, '10');
      expect(chat.name, 'Test Group');
      expect(chat.description, 'A test group chat');
      expect(chat.type, ChatType.group);
      expect(chat.isActive, true);
      expect(chat.isPrivate, false);
      expect(chat.maxMembers, 200);
      expect(chat.unreadCount, 5);
      expect(chat.isBlocked, true);
      expect(chat.isHidden, true);
      expect(chat.clearedBeforeMessageId, '88');
    });

    test('fromJson handles snake_case and room_type', () {
      final json = {
        'id': 20,
        'name': 'Private Chat',
        'room_type': 'PRIVATE',
        'is_active': true,
        'is_private': true,
        'max_members': 2,
        'created_at': '2024-01-01T00:00:00.000Z',
        'unread_count': 3,
      };

      final chat = Chat.fromJson(json);

      expect(chat.type, ChatType.private);
      expect(chat.isPrivate, true);
      expect(chat.maxMembers, 2);
      expect(chat.unreadCount, 3);
    });

    test('fromJson handles missing fields with defaults', () {
      final json = {
        'id': 30,
        'name': 'Minimal',
        'createdAt': '2024-01-01T00:00:00.000Z',
      };

      final chat = Chat.fromJson(json);

      expect(chat.id, '30');
      expect(chat.name, 'Minimal');
      expect(chat.type, ChatType.private);
      expect(chat.isActive, true);
      expect(chat.maxMembers, 500);
      expect(chat.unreadCount, 0);
      expect(chat.participants, isEmpty);
    });

    test('toJson produces correct output', () {
      final chat = Chat(
        id: '1',
        name: 'Test Chat',
        type: ChatType.group,
        isPrivate: false,
        maxMembers: 100,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        unreadCount: 7,
      );

      final json = chat.toJson();

      expect(json['id'], '1');
      expect(json['name'], 'Test Chat');
      expect(json['type'], 'GROUP');
      expect(json['isPrivate'], false);
      expect(json['maxMembers'], 100);
      expect(json['unreadCount'], 7);
      expect(json['isBlocked'], false);
    });

    test('copyWith creates modified copy', () {
      final chat = Chat(
        id: '1',
        name: 'Original',
        type: ChatType.group,
        createdAt: DateTime.now(),
        unreadCount: 5,
        isPinned: false,
        isMuted: false,
      );

      final modified = chat.copyWith(
        name: 'Modified',
        unreadCount: 0,
        isPinned: true,
        isMuted: true,
        isBlocked: true,
        clearedBeforeMessageId: '99',
      );

      expect(modified.id, chat.id);
      expect(modified.name, 'Modified');
      expect(modified.unreadCount, 0);
      expect(modified.isPinned, true);
      expect(modified.isMuted, true);
      expect(modified.isBlocked, true);
      expect(modified.clearedBeforeMessageId, '99');
      expect(modified.type, chat.type);
    });

    test('equality based on id', () {
      final chat1 = Chat(
        id: '1',
        name: 'Chat One',
        createdAt: DateTime.now(),
      );
      final chat2 = Chat(
        id: '1',
        name: 'Different Name',
        createdAt: DateTime.now(),
      );
      final chat3 = Chat(
        id: '2',
        name: 'Chat One',
        createdAt: DateTime.now(),
      );

      expect(chat1, equals(chat2));
      expect(chat1, isNot(equals(chat3)));
      expect(chat1.hashCode, equals(chat2.hashCode));
    });

    test('hasUnreadMessages returns correct value', () {
      final noUnread = Chat(
        id: '1',
        name: 'No Unread',
        createdAt: DateTime.now(),
        unreadCount: 0,
      );
      final hasUnread = Chat(
        id: '2',
        name: 'Has Unread',
        createdAt: DateTime.now(),
        unreadCount: 3,
      );

      expect(noUnread.hasUnreadMessages, false);
      expect(hasUnread.hasUnreadMessages, true);
    });

    test('getDisplayName returns group name for group chat', () {
      final chat = Chat(
        id: '1',
        name: 'My Group',
        type: ChatType.group,
        createdAt: DateTime.now(),
      );

      expect(chat.getDisplayName('user1'), 'My Group');
    });

    test('getDisplayName returns other user name for private chat', () {
      final currentUser = User(
        id: 'user1',
        username: 'current',
        email: 'current@example.com',
        displayName: 'Current User',
        createdAt: DateTime.now(),
      );
      final otherUser = User(
        id: 'user2',
        username: 'other',
        email: 'other@example.com',
        displayName: 'Other User',
        createdAt: DateTime.now(),
      );

      final chat = Chat(
        id: '1',
        name: 'Private',
        type: ChatType.private,
        participants: [currentUser, otherUser],
        createdAt: DateTime.now(),
      );

      expect(chat.getDisplayName('user1'), 'Other User');
    });
  });

  group('ChatType', () {
    test('has correct descriptions', () {
      expect(ChatType.private.description, '私聊');
      expect(ChatType.group.description, '群聊');
      expect(ChatType.channel.description, '频道');
    });
  });
}
