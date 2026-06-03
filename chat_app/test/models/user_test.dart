import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/models/user.dart';

void main() {
  group('User', () {
    test('fromJson creates user with all fields', () {
      final json = {
        'id': 1,
        'username': 'testuser',
        'email': 'test@example.com',
        'phone': '1234567890',
        'displayName': 'Test User',
        'avatarUrl': 'https://example.com/avatar.jpg',
        'title': '管理员',
        'titleColor': '#2F6BFF',
        'titleEffect': 'gradient',
        'bio': 'Hello world',
        'onlineStatus': 'ONLINE',
        'lastSeen': '2024-01-01T00:00:00.000Z',
        'isActive': true,
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-02T00:00:00.000Z',
        'roles': ['USER', 'ADMIN'],
      };

      final user = User.fromJson(json);

      expect(user.id, '1');
      expect(user.username, 'testuser');
      expect(user.email, 'test@example.com');
      expect(user.phone, '1234567890');
      expect(user.displayName, 'Test User');
      expect(user.avatarUrl, 'https://example.com/avatar.jpg');
      expect(user.title, '管理员');
      expect(user.titleColor, '#2F6BFF');
      expect(user.titleEffect, 'gradient');
      expect(user.bio, 'Hello world');
      expect(user.onlineStatus, OnlineStatus.online);
      expect(user.isActive, true);
      expect(user.roles, contains(UserRole.user));
      expect(user.roles, contains(UserRole.admin));
    });

    test('fromJson handles snake_case fields', () {
      final json = {
        'id': 2,
        'username': 'user2',
        'email': 'user2@example.com',
        'display_name': 'User Two',
        'title_color': '#18B98F',
        'title_effect': 'glow',
        'online_status': 'AWAY',
        'is_active': false,
        'created_at': '2024-06-01T00:00:00.000Z',
      };

      final user = User.fromJson(json);

      expect(user.displayName, 'User Two');
      expect(user.titleColor, '#18B98F');
      expect(user.titleEffect, 'glow');
      expect(user.onlineStatus, OnlineStatus.away);
      expect(user.isActive, false);
    });

    test('fromJson handles missing/null fields gracefully', () {
      final json = {
        'id': null,
        'username': null,
        'email': null,
        'createdAt': '2024-01-01T00:00:00.000Z',
      };

      final user = User.fromJson(json);

      expect(user.id, '');
      expect(user.username, '');
      expect(user.email, '');
      expect(user.displayName, '');
      expect(user.onlineStatus, OnlineStatus.offline);
      expect(user.isActive, true);
      expect(user.roles, isEmpty);
    });

    test('toJson produces correct output', () {
      final user = User(
        id: '1',
        username: 'testuser',
        email: 'test@example.com',
        displayName: 'Test User',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        onlineStatus: OnlineStatus.online,
      );

      final json = user.toJson();

      expect(json['id'], '1');
      expect(json['username'], 'testuser');
      expect(json['email'], 'test@example.com');
      expect(json['displayName'], 'Test User');
      expect(json['onlineStatus'], 'ONLINE');
    });

    test('toJson/fromJson roundtrip preserves data', () {
      final original = User(
        id: '42',
        username: 'roundtrip',
        email: 'rt@example.com',
        displayName: 'Round Trip',
        phone: '555-1234',
        bio: 'Testing roundtrip',
        onlineStatus: OnlineStatus.busy,
        isActive: true,
        createdAt: DateTime.parse('2024-03-15T10:30:00.000Z'),
        roles: [UserRole.user],
      );

      final json = original.toJson();
      final restored = User.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.username, original.username);
      expect(restored.email, original.email);
      expect(restored.displayName, original.displayName);
      expect(restored.phone, original.phone);
      expect(restored.bio, original.bio);
      expect(restored.onlineStatus, original.onlineStatus);
      expect(restored.isActive, original.isActive);
    });

    test('copyWith creates modified copy', () {
      final user = User(
        id: '1',
        username: 'original',
        email: 'original@example.com',
        displayName: 'Original',
        createdAt: DateTime.now(),
      );

      final modified = user.copyWith(
        displayName: 'Modified',
        bio: 'New bio',
        onlineStatus: OnlineStatus.online,
      );

      expect(modified.id, user.id);
      expect(modified.username, user.username);
      expect(modified.displayName, 'Modified');
      expect(modified.bio, 'New bio');
      expect(modified.onlineStatus, OnlineStatus.online);
    });

    test('equality based on id', () {
      final user1 = User(
        id: '1',
        username: 'user1',
        email: 'u1@example.com',
        displayName: 'User 1',
        createdAt: DateTime.now(),
      );

      final user2 = User(
        id: '1',
        username: 'different',
        email: 'different@example.com',
        displayName: 'Different',
        createdAt: DateTime.now(),
      );

      final user3 = User(
        id: '2',
        username: 'user1',
        email: 'u1@example.com',
        displayName: 'User 1',
        createdAt: DateTime.now(),
      );

      expect(user1, equals(user2));
      expect(user1, isNot(equals(user3)));
      expect(user1.hashCode, equals(user2.hashCode));
    });
  });

  group('OnlineStatus', () {
    test('has correct descriptions', () {
      expect(OnlineStatus.online.description, '在线');
      expect(OnlineStatus.away.description, '离开');
      expect(OnlineStatus.busy.description, '忙碌');
      expect(OnlineStatus.offline.description, '离线');
    });
  });
}
