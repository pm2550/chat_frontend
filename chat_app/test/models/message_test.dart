import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/models/message.dart';

void main() {
  group('Message', () {
    test('fromJson creates message with all fields', () {
      final json = {
        'id': 100,
        'content': 'Hello World',
        'senderId': 1,
        'senderName': 'TestUser',
        'senderAvatar': 'https://example.com/avatar.jpg',
        'chatRoomId': 10,
        'type': 'TEXT',
        'status': 'SENT',
        'timestamp': '2024-01-01T12:00:00.000Z',
        'replyToMessageId': 99,
        'fileUrl': null,
      };

      final message = Message.fromJson(json);

      expect(message.id, '100');
      expect(message.content, 'Hello World');
      expect(message.senderId, '1');
      expect(message.senderName, 'TestUser');
      expect(message.chatRoomId, '10');
      expect(message.type, MessageType.text);
      expect(message.status, MessageStatus.sent);
      expect(message.replyToMessageId, '99');
    });

    test('fromJson handles snake_case fields', () {
      final json = {
        'id': 200,
        'content': 'Snake case test',
        'sender_id': 5,
        'sender_name': 'SnakeUser',
        'chat_room_id': 20,
        'message_type': 'IMAGE',
        'message_status': 'DELIVERED',
        'created_at': '2024-06-15T08:30:00.000Z',
        'reply_to_message_id': 199,
        'file_url': 'https://example.com/image.jpg',
        'file_name': 'photo.jpg',
        'file_size': 1024,
        'file_type': 'image/jpeg',
      };

      final message = Message.fromJson(json);

      expect(message.senderId, '5');
      expect(message.senderName, 'SnakeUser');
      expect(message.chatRoomId, '20');
      expect(message.type, MessageType.image);
      expect(message.status, MessageStatus.delivered);
      expect(message.fileUrl, 'https://example.com/image.jpg');
      expect(message.fileName, 'photo.jpg');
      expect(message.fileSize, 1024);
      expect(message.fileType, 'image/jpeg');
    });

    test('fromJson maps anonymous display metadata over real sender name', () {
      final json = {
        'id': 201,
        'content': '匿名消息',
        'senderId': 5,
        'senderName': 'RealUser',
        'chatRoomId': 20,
        'messageType': 'TEXT',
        'messageStatus': 'SENT',
        'createdAt': '2024-06-15T08:30:00.000Z',
        'isAnonymous': true,
        'anonymousIdentityId': 9,
        'anonymousName': '神秘海豚',
        'anonymousAvatar': '#FF6B6B',
      };

      final message = Message.fromJson(json);

      expect(message.isAnonymous, isTrue);
      expect(message.senderName, '神秘海豚');
      expect(message.senderAvatar, '#FF6B6B');
      expect(message.anonymousIdentityId, '9');
      expect(message.anonymousName, '神秘海豚');
    });

    test('fromJson maps bot identity and excludes bot messages from self side',
        () {
      final message = Message.fromJson({
        'id': 202,
        'content': '[HelperBot] bot answer',
        'senderId': 5,
        'senderName': 'RealUser',
        'chatRoomId': 20,
        'messageType': 'TEXT',
        'messageStatus': 'SENT',
        'createdAt': '2024-06-15T08:30:00.000Z',
        'botConfigId': 9,
        'botSenderId': 9,
        'botName': 'HelperBot',
        'botAvatar': '/api/files/avatar/helper.png',
      });

      expect(message.isBotMessage, isTrue);
      expect(message.botConfigId, '9');
      expect(message.botSenderId, '9');
      expect(message.botName, 'HelperBot');
      expect(message.botAvatar, '/api/files/avatar/helper.png');
      expect(message.isFromCurrentUser('5'), isFalse);
      expect(message.displayContent, 'bot answer');
    });

    test('fromJson maps sticker messages', () {
      final message = Message.fromJson({
        'id': 301,
        'content': '[贴纸]',
        'senderId': 5,
        'senderName': 'Sender',
        'chatRoomId': 20,
        'messageType': 'STICKER',
        'messageStatus': 'SENT',
        'createdAt': '2024-06-15T08:30:00.000Z',
        'stickerId': 12,
        'fileUrl': '/api/files/chat/sticker.png',
        'fileName': '😀',
      });

      expect(message.type, MessageType.sticker);
      expect(message.stickerId, 12);
      expect(message.isStickerMessage, isTrue);
      expect(message.resolvedFileLabel, '[贴纸] 😀');
    });

    test('fromJson maps reactions', () {
      final message = Message.fromJson({
        'id': 302,
        'content': 'react',
        'senderId': 5,
        'senderName': 'Sender',
        'chatRoomId': 20,
        'messageType': 'TEXT',
        'messageStatus': 'SENT',
        'createdAt': '2024-06-15T08:30:00.000Z',
        'reactions': [
          {
            'emoji': '👍',
            'count': 2,
            'userIds': [1, 2],
          }
        ],
      });

      expect(message.reactions.single.emoji, '👍');
      expect(message.reactions.single.count, 2);
      expect(message.hasReactionFrom('👍', '1'), isTrue);
    });

    test('fromJson maps poll messages', () {
      final message = Message.fromJson({
        'id': 303,
        'content': '[投票] 午饭吃什么',
        'senderId': 5,
        'senderName': 'Sender',
        'chatRoomId': 20,
        'messageType': 'POLL',
        'messageStatus': 'SENT',
        'createdAt': '2024-06-15T08:30:00.000Z',
        'pollId': 3,
      });

      expect(message.type, MessageType.poll);
      expect(message.pollId, 3);
      expect(message.isPollMessage, isTrue);
    });

    test('fromJson handles missing fields gracefully', () {
      final json = {
        'id': null,
        'content': null,
        'created_at': '2024-01-01T00:00:00.000Z',
      };

      final message = Message.fromJson(json);

      expect(message.id, '');
      expect(message.content, '');
      expect(message.senderId, '');
      expect(message.type, MessageType.text);
      expect(message.status, MessageStatus.sent);
    });

    test('fromJson handles nested replyToMessage', () {
      final json = {
        'id': 300,
        'content': 'Reply message',
        'senderId': 1,
        'senderName': 'User1',
        'chatRoomId': 10,
        'timestamp': '2024-01-01T12:01:00.000Z',
        'replyToMessage': {
          'id': 299,
          'content': 'Original message',
          'senderId': 2,
          'senderName': 'User2',
          'chatRoomId': 10,
          'timestamp': '2024-01-01T12:00:00.000Z',
        },
      };

      final message = Message.fromJson(json);

      expect(message.hasReply, true);
      expect(message.replyToMessage!.id, '299');
      expect(message.replyToMessage!.content, 'Original message');
    });

    test('fromJson parses link preview metadata', () {
      final message = Message.fromJson({
        'id': 301,
        'content': '看看 https://example.com/post',
        'senderId': 1,
        'senderName': 'User1',
        'chatRoomId': 10,
        'timestamp': '2024-01-01T12:01:00.000Z',
        'linkPreview': {
          'url': 'https://example.com/post',
          'title': 'Example title',
          'description': 'Example description',
          'imageUrl': 'https://example.com/cover.png',
          'siteName': 'example.com',
          'faviconUrl': 'https://example.com/favicon.ico',
        },
      });

      expect(message.linkPreview, isNotNull);
      expect(message.linkPreview!.url, 'https://example.com/post');
      expect(message.linkPreview!.title, 'Example title');
      expect(message.linkPreview!.description, 'Example description');
      expect(message.linkPreview!.imageUrl, 'https://example.com/cover.png');
      expect(message.linkPreview!.siteName, 'example.com');
      expect(
          message.linkPreview!.faviconUrl, 'https://example.com/favicon.ico');
    });

    test('toJson produces correct output', () {
      final message = Message(
        id: '1',
        content: 'Test',
        senderId: '10',
        senderName: 'TestUser',
        chatRoomId: '100',
        type: MessageType.file,
        status: MessageStatus.sent,
        timestamp: DateTime.parse('2024-01-01T00:00:00.000Z'),
        fileUrl: 'https://example.com/file.pdf',
        fileName: 'doc.pdf',
        fileSize: 2048,
        fileType: 'application/pdf',
      );

      final json = message.toJson();

      expect(json['id'], '1');
      expect(json['content'], 'Test');
      expect(json['senderId'], '10');
      expect(json['type'], 'FILE');
      expect(json['status'], 'SENT');
      expect(json['fileUrl'], 'https://example.com/file.pdf');
      expect(json['fileName'], 'doc.pdf');
      expect(json['fileSize'], 2048);
    });

    test('toJson/fromJson roundtrip preserves data', () {
      final original = Message(
        id: '42',
        content: 'Roundtrip test',
        senderId: '5',
        senderName: 'RoundTripper',
        chatRoomId: '99',
        type: MessageType.voice,
        status: MessageStatus.delivered,
        timestamp: DateTime.parse('2024-03-15T10:30:00.000Z'),
      );

      final json = original.toJson();
      final restored = Message.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.content, original.content);
      expect(restored.senderId, original.senderId);
      expect(restored.senderName, original.senderName);
      expect(restored.chatRoomId, original.chatRoomId);
      expect(restored.type, original.type);
      expect(restored.status, original.status);
    });

    test('copyWith creates modified copy', () {
      final message = Message(
        id: '1',
        content: 'Original',
        senderId: '10',
        senderName: 'Sender',
        chatRoomId: '100',
        timestamp: DateTime.now(),
      );

      final modified = message.copyWith(
        content: 'Modified',
        status: MessageStatus.read,
      );

      expect(modified.id, message.id);
      expect(modified.content, 'Modified');
      expect(modified.status, MessageStatus.read);
      expect(modified.senderId, message.senderId);
    });

    test('equality based on id', () {
      final msg1 = Message(
        id: '1',
        content: 'First',
        senderId: '10',
        senderName: 'User',
        chatRoomId: '100',
        timestamp: DateTime.now(),
      );

      final msg2 = Message(
        id: '1',
        content: 'Different content',
        senderId: '20',
        senderName: 'Other',
        chatRoomId: '200',
        timestamp: DateTime.now(),
      );

      expect(msg1, equals(msg2));
      expect(msg1.hashCode, equals(msg2.hashCode));
    });

    test('isEdited returns correct value', () {
      final notEdited = Message(
        id: '1',
        content: 'Not edited',
        senderId: '10',
        senderName: 'User',
        chatRoomId: '100',
        timestamp: DateTime.now(),
      );

      final edited = Message(
        id: '2',
        content: 'Edited',
        senderId: '10',
        senderName: 'User',
        chatRoomId: '100',
        timestamp: DateTime.now(),
        editedAt: DateTime.now(),
      );

      expect(notEdited.isEdited, false);
      expect(edited.isEdited, true);
    });
  });

  group('MessageType', () {
    test('has correct descriptions', () {
      expect(MessageType.text.description, '文本');
      expect(MessageType.image.description, '图片');
      expect(MessageType.file.description, '文件');
      expect(MessageType.voice.description, '语音');
      expect(MessageType.video.description, '视频');
      expect(MessageType.system.description, '系统消息');
    });
  });
}
