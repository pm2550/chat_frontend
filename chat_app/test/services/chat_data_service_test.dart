import 'dart:convert';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('ChatDataService', () {
    test('getChatRooms reads backend chatRooms response', () async {
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          return jsonResponse({
            'chatRooms': [
              {
                'id': 10,
                'name': 'Backend Room',
                'roomType': 'GROUP',
                'isPrivate': false,
                'createdAt': '2024-01-01T10:00:00',
                'updatedAt': '2024-01-01T10:02:00',
              },
            ],
          });
        },
      );

      final rooms = await service.getChatRooms(includeDetails: false);

      expect(rooms, hasLength(1));
      expect(rooms.first.id, '10');
      expect(rooms.first.name, 'Backend Room');
      expect(rooms.first.type, ChatType.group);
    });

    test('getChatRoom reads backend chatRoom detail response', () async {
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          expect(url, contains('/chat-rooms/42'));
          return jsonResponse({
            'chatRoom': {
              'id': 42,
              'name': 'Direct Room',
              'roomType': 'GROUP',
              'isPrivate': false,
              'createdAt': '2024-01-01T10:00:00',
            },
          });
        },
      );

      final room = await service.getChatRoom('42', includeDetails: false);

      expect(room.id, '42');
      expect(room.name, 'Direct Room');
      expect(room.type, ChatType.group);
    });

    test('room background preset endpoint maps returned chat room', () async {
      Object? sentBody;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'PUT');
          expect(url, ApiConstants.chatRoomBackgroundPreset(42));
          sentBody = body;
          return jsonResponse({
            'chatRoom': {
              'id': 42,
              'name': 'Room',
              'roomType': 'GROUP',
              'isPrivate': false,
              'customBackgroundPreset': 'aurora',
              'createdAt': '2024-01-01T10:00:00',
            },
          });
        },
      );

      final room = await service.updateRoomBackgroundPreset('42', 'aurora');

      expect(sentBody, {'preset': 'aurora'});
      expect(room.customBackgroundPreset, 'aurora');
    });

    test('room background upload uses multipart file request', () async {
      PickedChatFile? uploaded;
      final service = ChatDataService(
        multipartRequest: (url, {required fields, required file}) async {
          expect(url, ApiConstants.chatRoomBackgroundUpload(42));
          expect(fields, isEmpty);
          uploaded = file;
          return jsonResponse({
            'chatRoom': {
              'id': 42,
              'name': 'Room',
              'roomType': 'GROUP',
              'isPrivate': false,
              'customBackgroundUrl': '/api/files/background/room.png',
              'createdAt': '2024-01-01T10:00:00',
            },
          });
        },
      );

      final room = await service.uploadRoomBackground(
        '42',
        const PickedChatFile(name: 'room.png', size: 3, bytes: [1, 2, 3]),
      );

      expect(uploaded?.name, 'room.png');
      expect(room.customBackgroundUrl, '/api/files/background/room.png');
    });

    test('room avatar upload uses multipart file request', () async {
      PickedChatFile? uploaded;
      final service = ChatDataService(
        multipartRequest: (url, {required fields, required file}) async {
          expect(url, ApiConstants.chatRoomAvatar(42));
          expect(fields, isEmpty);
          uploaded = file;
          return jsonResponse({
            'chatRoom': {
              'id': 42,
              'name': 'Room',
              'roomType': 'GROUP',
              'isPrivate': false,
              'avatarUrl': '/api/files/avatar/room.png',
              'createdAt': '2024-01-01T10:00:00',
            },
          });
        },
      );

      final room = await service.uploadRoomAvatar(
        '42',
        const PickedChatFile(name: 'room.png', size: 3, bytes: [1, 2, 3]),
      );

      expect(uploaded?.name, 'room.png');
      expect(room.avatarUrl, '/api/files/avatar/room.png');
    });

    test('clear room background calls delete endpoint', () async {
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'DELETE');
          expect(url, ApiConstants.chatRoomBackground(42));
          return jsonResponse({
            'chatRoom': {
              'id': 42,
              'name': 'Room',
              'roomType': 'GROUP',
              'isPrivate': false,
              'createdAt': '2024-01-01T10:00:00',
            },
          });
        },
      );

      final room = await service.clearRoomBackground('42');

      expect(room.customBackgroundPreset, isNull);
      expect(room.customBackgroundUrl, isNull);
    });

    test('getMessages maps backend REST messages and sorts ascending',
        () async {
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          return jsonResponse({
            'messages': [
              {
                'id': 2,
                'content': 'new',
                'messageType': 'TEXT',
                'messageStatus': 'SENT',
                'createdAt': '2024-01-01T10:02:00',
                'sender': {
                  'id': 5,
                  'displayName': 'Alice',
                  'avatarUrl': 'https://example.com/a.png',
                },
              },
              {
                'id': 1,
                'content': 'old',
                'messageType': 'TEXT',
                'messageStatus': 'READ',
                'createdAt': '2024-01-01T10:01:00',
                'sender': {'id': 6, 'username': 'bob'},
              },
            ],
          });
        },
      );

      final messages = await service.getMessages('42');

      expect(messages.map((m) => m.content), ['old', 'new']);
      expect(messages.first.chatRoomId, '42');
      expect(messages.first.senderName, 'bob');
      expect(messages.last.senderId, '5');
      expect(messages.last.senderAvatar, 'https://example.com/a.png');
      expect(messages.last.type, MessageType.text);
      expect(messages.first.status, MessageStatus.read);
    });

    test('getMessagePage preserves backend pagination metadata', () async {
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          expect(url, contains('page=1'));
          return jsonResponse({
            'messages': [
              {
                'id': 3,
                'content': 'older',
                'messageType': 'TEXT',
                'messageStatus': 'SENT',
                'createdAt': '2024-01-01T09:59:00',
                'senderId': 5,
                'senderName': 'Alice',
                'chatRoomId': 42,
              },
            ],
            'currentPage': 1,
            'totalPages': 3,
            'totalElements': 51,
            'hasNext': true,
            'hasPrevious': true,
          });
        },
      );

      final page = await service.getMessagePage('42', page: 1, size: 25);

      expect(page.messages.single.content, 'older');
      expect(page.currentPage, 1);
      expect(page.totalPages, 3);
      expect(page.totalElements, 51);
      expect(page.hasNext, isTrue);
      expect(page.hasPrevious, isTrue);
    });

    test('getMentionedMessages calls @me endpoint and parses mention ids',
        () async {
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          expect(url, contains('/chat-rooms/42/mentions/me'));
          expect(url, contains('page=0'));
          return jsonResponse({
            'messages': [
              {
                'id': 8,
                'content': '@Me 需要看这里',
                'messageType': 'TEXT',
                'messageStatus': 'SENT',
                'createdAt': '2024-01-01T10:04:00',
                'senderId': 7,
                'senderName': 'Sender',
                'mentionedUserIds': [5],
              },
            ],
            'currentPage': 0,
            'totalPages': 1,
            'totalElements': 1,
          });
        },
      );

      final page = await service.getMentionedMessages('42');

      expect(page.messages.single.mentionedUserIds, ['5']);
      expect(page.messages.single.mentionsUser('5'), isTrue);
    });

    test('sendTextMessage posts expected body and reads data message',
        () async {
      Object? capturedBody;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          capturedBody = body;
          return jsonResponse({
            'message': '消息发送成功',
            'data': {
              'id': 99,
              'content': 'hello',
              'messageType': 'TEXT',
              'messageStatus': 'SENT',
              'createdAt': '2024-01-01T10:03:00',
              'sender': {'id': 7, 'displayName': 'Sender'},
            },
          });
        },
      );

      final message =
          await service.sendTextMessage('42', 'hello', replyToId: '88');

      expect(capturedBody, {
        'chatRoomId': 42,
        'content': 'hello',
        'replyToId': 88,
      });
      expect(message.id, '99');
      expect(message.chatRoomId, '42');
      expect(message.senderName, 'Sender');
    });

    test('sendTextMessage can request anonymous delivery', () async {
      Object? capturedBody;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          capturedBody = body;
          return jsonResponse({
            'message': '消息发送成功',
            'data': {
              'id': 100,
              'content': 'masked',
              'messageType': 'TEXT',
              'messageStatus': 'SENT',
              'createdAt': '2024-01-01T10:03:00',
              'senderId': 7,
              'senderName': '神秘海豚',
              'isAnonymous': true,
              'anonymousIdentityId': 3,
              'anonymousName': '神秘海豚',
              'anonymousAvatar': '#FF6B6B',
            },
          });
        },
      );

      final message =
          await service.sendTextMessage('42', 'masked', isAnonymous: true);

      expect(capturedBody, {
        'chatRoomId': 42,
        'content': 'masked',
        'isAnonymous': true,
      });
      expect(message.isAnonymous, isTrue);
      expect(message.senderName, '神秘海豚');
      expect(message.anonymousIdentityId, '3');
    });

    test('sendStickerMessage posts sticker body and maps response', () async {
      Object? capturedBody;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          capturedBody = body;
          return jsonResponse({
            'message': '消息发送成功',
            'data': {
              'id': 102,
              'content': '[贴纸]',
              'messageType': 'STICKER',
              'messageStatus': 'SENT',
              'createdAt': '2024-01-01T10:03:00',
              'senderId': 7,
              'senderName': 'Sender',
              'stickerId': 9,
              'fileName': '😀',
            },
          });
        },
      );

      final message =
          await service.sendStickerMessage('42', 9, isAnonymous: true);

      expect(capturedBody, {
        'chatRoomId': 42,
        'messageType': 'STICKER',
        'stickerId': 9,
        'isAnonymous': true,
      });
      expect(message.type, MessageType.sticker);
      expect(message.stickerId, 9);
    });

    test('addReaction posts emoji and maps aggregate', () async {
      Object? capturedBody;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          expect(url, contains('/api/v1/messages/102/reactions'));
          capturedBody = body;
          return jsonResponse({
            'data': [
              {
                'emoji': '👍',
                'count': 1,
                'userIds': [7],
              }
            ],
          });
        },
      );

      final reactions = await service.addReaction('102', '👍');

      expect(capturedBody, {'emoji': '👍'});
      expect(reactions.single.emoji, '👍');
      expect(reactions.single.userIds, ['7']);
    });

    test('createPoll posts poll request and maps response', () async {
      Object? capturedBody;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          expect(url, contains('/api/v1/polls'));
          capturedBody = body;
          return jsonResponse({
            'data': {
              'id': 3,
              'messageId': 303,
              'question': '午饭吃什么',
              'options': [
                {'index': 0, 'text': '面', 'votes': 0, 'voterIds': []},
                {'index': 1, 'text': '饭', 'votes': 0, 'voterIds': []},
              ],
              'totalVotes': 0,
            },
          });
        },
      );

      final poll = await service.createPoll(
        '42',
        question: '午饭吃什么',
        options: ['面', '饭'],
      );

      expect(capturedBody, {
        'chatRoomId': 42,
        'question': '午饭吃什么',
        'options': ['面', '饭'],
        'multiSelect': false,
        'anonymous': false,
      });
      expect(poll.id, 3);
      expect(poll.options.length, 2);
    });

    test('sendEncryptedTextMessage posts encrypted envelope fields', () async {
      Object? capturedBody;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          capturedBody = body;
          return jsonResponse({
            'data': {
              'id': 100,
              'content': '[加密消息]',
              'messageType': 'TEXT',
              'messageStatus': 'SENT',
              'encryptedContent': 'ZW5j',
              'encryptionVersion': 1,
              'createdAt': '2024-01-01T10:03:00',
              'senderId': 7,
              'senderName': 'Sender',
              'chatRoomId': 42,
            },
          });
        },
      );

      final message = await service.sendEncryptedTextMessage(
        '42',
        encryptedContent: 'ZW5j',
      );

      expect(capturedBody, {
        'chatRoomId': 42,
        'content': '[加密消息]',
        'messageType': 'TEXT',
        'encryptedContent': 'ZW5j',
        'encryptionVersion': 1,
      });
      expect(message.isEncrypted, isTrue);
      expect(message.encryptionVersion, 1);
    });

    test('sendFileMessage posts multipart fields and reads data message',
        () async {
      Map<String, String>? capturedFields;
      PickedChatFile? capturedFile;
      final service = ChatDataService(
        authenticatedRequest: unusedRequest,
        multipartRequest: (url, {required fields, required file}) async {
          capturedFields = fields;
          capturedFile = file;
          return jsonResponse({
            'message': '文件消息发送成功',
            'data': {
              'id': 101,
              'content': 'photo.png',
              'messageType': 'IMAGE',
              'messageStatus': 'SENT',
              'fileUrl': '/api/files/chat/uuid.png',
              'fileName': 'photo.png',
              'fileSize': 3,
              'fileType': 'image/png',
              'createdAt': '2024-01-01T10:03:00',
              'sender': {'id': 7, 'displayName': 'Sender'},
            },
          });
        },
      );

      const file = PickedChatFile(
        name: 'photo.png',
        size: 3,
        mimeType: 'image/png',
        bytes: [1, 2, 3],
      );
      final message = await service.sendFileMessage(
        '42',
        file,
        encryptedContent: 'a2V5LWVudmVsb3Bl',
        encryptionVersion: 1,
      );

      expect(capturedFields, {
        'chatRoomId': '42',
        'encryptedContent': 'a2V5LWVudmVsb3Bl',
        'encryptionVersion': '1',
      });
      expect(capturedFile, same(file));
      expect(message.id, '101');
      expect(message.type, MessageType.image);
      expect(message.fileUrl, '/api/files/chat/uuid.png');
      expect(message.resolvedFileLabel, '[图片] photo.png');
    });

    test('searchMessages calls search endpoint and maps results', () async {
      String? capturedUrl;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          capturedUrl = url;
          return jsonResponse({
            'messages': [
              {
                'id': 201,
                'content': 'needle result',
                'messageType': 'TEXT',
                'messageStatus': 'SENT',
                'createdAt': '2024-01-01T10:05:00',
                'senderId': 7,
                'senderName': 'Sender',
                'chatRoomId': 42,
              },
            ],
            'currentPage': 0,
            'totalPages': 1,
            'totalElements': 1,
          });
        },
      );

      final page = await service.searchMessages('42', 'needle');

      expect(capturedUrl, contains('/api/v1/chat-rooms/42/messages/search'));
      expect(capturedUrl, contains('q=needle'));
      expect(capturedUrl, contains('limit=20'));
      expect(page.messages.single.content, 'needle result');
      expect(page.totalElements, 1);
    });

    test('fetchUrlPreview posts url and maps response data', () async {
      Object? capturedBody;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          expect(url, contains('/api/v1/url-preview'));
          capturedBody = body;
          return jsonResponse({
            'message': '链接预览生成成功',
            'data': {
              'url': 'https://example.com/post',
              'title': 'Example title',
              'description': 'Example description',
              'imageUrl': 'https://example.com/cover.png',
              'siteName': 'example.com',
              'faviconUrl': 'https://example.com/favicon.ico',
            },
          });
        },
      );

      final preview = await service.fetchUrlPreview('https://example.com/post');

      expect(capturedBody, {'url': 'https://example.com/post'});
      expect(preview.url, 'https://example.com/post');
      expect(preview.title, 'Example title');
      expect(preview.description, 'Example description');
      expect(preview.imageUrl, 'https://example.com/cover.png');
      expect(preview.siteName, 'example.com');
      expect(preview.faviconUrl, 'https://example.com/favicon.ico');
    });

    test('getFileMessages calls room files endpoint with optional type',
        () async {
      String? capturedUrl;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          capturedUrl = url;
          return jsonResponse({
            'messages': [
              {
                'id': 301,
                'content': 'photo.png',
                'messageType': 'IMAGE',
                'messageStatus': 'SENT',
                'fileUrl': '/api/files/chat/photo.png',
                'fileName': 'photo.png',
                'fileSize': 3,
                'fileType': 'image/png',
                'createdAt': '2024-01-01T10:07:00',
                'senderId': 7,
                'senderName': 'Sender',
                'chatRoomId': 42,
              },
            ],
            'currentPage': 0,
            'totalPages': 1,
            'totalElements': 1,
          });
        },
      );

      final page = await service.getFileMessages(
        '42',
        type: MessageType.image,
      );

      expect(capturedUrl, contains('/api/v1/messages/chat-room/42/files'));
      expect(capturedUrl, contains('messageType=IMAGE'));
      expect(page.messages.single.fileName, 'photo.png');
      expect(page.messages.single.type, MessageType.image);
    });

    test('recallMessage and deleteMessage read returned message data',
        () async {
      final calls = <String>[];
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          calls.add('$method $url');
          return jsonResponse({
            'message': method == 'POST' ? '消息已撤回' : '消息已删除',
            'data': {
              'id': 55,
              'content': method == 'POST' ? '[消息已撤回]' : '[消息已删除]',
              'messageType': 'TEXT',
              'messageStatus': 'SENT',
              'isDeleted': true,
              'createdAt': '2024-01-01T10:06:00',
              'senderId': 7,
              'senderName': 'Sender',
              'chatRoomId': 42,
            },
          });
        },
      );

      final recalled = await service.recallMessage('55');
      final deleted = await service.deleteMessage('55');

      expect(calls[0], startsWith('POST '));
      expect(calls[0], contains('/api/v1/messages/55/recall'));
      expect(calls[1], startsWith('DELETE '));
      expect(calls[1], contains('/api/v1/messages/55'));
      expect(recalled.isRecalled, isTrue);
      expect(deleted.isDeleted, isTrue);
    });

    test('phase5 message quick win endpoints use expected methods and payloads',
        () async {
      final calls = <String>[];
      final bodies = <Object?>[];
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          calls.add('$method $url');
          bodies.add(body);
          final data = {
            'id': 55,
            'content': method == 'PUT' ? 'edited' : 'hello',
            'messageType': 'TEXT',
            'messageStatus': 'SENT',
            'createdAt': '2024-01-01T10:06:00',
            'senderId': 7,
            'senderName': 'Sender',
            'chatRoomId': 42,
            if (method == 'PUT') 'editedAt': '2024-01-01T10:07:00',
            if (url.contains('/forward')) 'forwardedFromMessageId': 55,
          };
          if (url.contains('/rooms/42/pin/55')) {
            return jsonResponse({'data': [data]});
          }
          return jsonResponse({'data': data});
        },
      );

      final edited = await service.editMessage('55', 'edited');
      final forwarded = await service.forwardMessage('55', '42');
      final pins = await service.pinMessage('42', '55');
      final starred = await service.starMessage('55');

      expect(calls[0], contains('PUT '));
      expect(calls[0], contains('/api/v1/messages/55'));
      expect(bodies[0], {'content': 'edited'});
      expect(calls[1], contains('POST '));
      expect(calls[1], contains('/api/v1/messages/55/forward'));
      expect(bodies[1], {'targetChatRoomId': 42});
      expect(calls[2], contains('POST '));
      expect(calls[2], contains('/api/v1/rooms/42/pin/55'));
      expect(calls[3], contains('POST '));
      expect(calls[3], contains('/api/v1/messages/55/star'));
      expect(edited.isEdited, isTrue);
      expect(forwarded.forwardedFromMessageId, '55');
      expect(pins.single.id, '55');
      expect(starred.id, '55');
    });

    test('throws ChatDataException for failed backend response', () async {
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          return jsonResponse({'error': '不能发送'}, statusCode: 400);
        },
      );

      expect(
        () => service.sendTextMessage('42', 'hello'),
        throwsA(isA<ChatDataException>()),
      );
    });

    test('throws ChatDataException for failed file send', () async {
      final service = ChatDataService(
        authenticatedRequest: unusedRequest,
        multipartRequest: (url, {required fields, required file}) async {
          return jsonResponse({'error': '文件太大'}, statusCode: 400);
        },
      );

      expect(
        () => service.sendFileMessage(
          '42',
          const PickedChatFile(name: 'big.zip', size: 99, bytes: [1]),
        ),
        throwsA(isA<ChatDataException>()),
      );
    });

    test('downloadFile uses authenticated request and returns bytes', () async {
      String? capturedUrl;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          capturedUrl = url;
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'application/pdf'},
          );
        },
      );

      final downloaded = await service.downloadFile(Message(
        id: '1',
        content: 'doc.pdf',
        senderId: '7',
        senderName: 'Sender',
        chatRoomId: '42',
        type: MessageType.file,
        status: MessageStatus.sent,
        timestamp: DateTime.parse('2024-01-01T10:03:00'),
        fileUrl: '/api/files/chat/doc.pdf',
        fileName: 'doc.pdf',
      ));

      expect(
        capturedUrl,
        'https://gateway.chat.pm2550.com/api/files/chat/doc.pdf',
      );
      expect(downloaded.name, 'doc.pdf');
      expect(downloaded.mimeType, 'application/pdf');
      expect(downloaded.bytes, [1, 2, 3]);
    });

    test('notification settings endpoints read and update room preference',
        () async {
      final calls = <String>[];
      final bodies = <Object?>[];
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          calls.add('$method $url');
          bodies.add(body);
          return jsonResponse({
            'roomId': 42,
            'userId': 7,
            'muted': method == 'PUT',
            'notificationLevel': method == 'PUT' ? 'MUTE' : 'ALL',
          });
        },
      );

      final current = await service.getNotificationSettings('42');
      final updated =
          await service.updateNotificationSettings('42', muted: true);

      expect(calls[0], startsWith('GET '));
      expect(calls[0], contains('/api/v1/chat-rooms/42/notification-settings'));
      expect(calls[1], startsWith('PUT '));
      expect(bodies[1], {'muted': true});
      expect(current['muted'], isFalse);
      expect(updated['muted'], isTrue);
    });

    test('getChatRoomMembers parses backend member summaries', () async {
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          expect(url, contains('/api/v1/chat-rooms/42/members'));
          return jsonResponse({
            'members': [
              {
                'id': 1,
                'userId': 7,
                'role': 'ADMIN',
                'roleDescription': '管理员',
                'isAdmin': true,
                'isMuted': false,
                'user': {
                  'id': 7,
                  'username': 'alice',
                  'displayName': 'Alice',
                  'email': 'alice@test.com',
                },
              },
            ],
            'count': 1,
          });
        },
      );

      final members = await service.getChatRoomMembers('42');

      expect(members, hasLength(1));
      expect(members.first.userId, '7');
      expect(members.first.displayName, 'Alice');
      expect(members.first.isAdmin, isTrue);
    });

    test(
        'generateImageMessage posts request and parses nested message response',
        () async {
      Object? sentBody;
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          expect(url, ApiConstants.generateImage);
          sentBody = body;
          return jsonResponse({
            'code': 200,
            'data': {
              'messageId': 88,
              'pointsCharged': 10,
              'status': 'QUEUED',
              'message': {
                'id': 88,
                'content': '画蓝色机器人',
                'senderId': 7,
                'senderName': 'Alice',
                'chatRoomId': 42,
                'messageType': 'IMAGE_GENERATION',
                'messageStatus': 'SENDING',
                'imageGenPrompt': '画蓝色机器人',
                'imageGenStatus': 'QUEUED',
                'createdAt': '2026-06-01T09:00:00',
              },
            },
          });
        },
      );

      final message = await service.generateImageMessage(
        '42',
        prompt: '画蓝色机器人',
      );

      expect(sentBody, {
        'roomId': 42,
        'prompt': '画蓝色机器人',
        'n': 1,
        'size': '1024*1024',
      });
      expect(message.id, '88');
      expect(message.type, MessageType.imageGeneration);
      expect(message.imageGenStatus, 'QUEUED');
    });

    test('group member management calls backend endpoints', () async {
      final calls = <String>[];
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          calls.add('$method $url');
          return jsonResponse({
            'members': [
              {
                'id': 2,
                'userId': 9,
                'role': 'MEMBER',
                'isAdmin': false,
                'user': {
                  'id': 9,
                  'username': 'bob',
                  'displayName': 'Bob',
                  'email': 'bob@test.com',
                },
              },
            ],
          });
        },
      );

      final members = await service.addChatRoomMember('42', '9');
      await service.toggleChatRoomAdmin('42', '9');
      await service.toggleChatRoomMute('42', '9');
      await service.kickChatRoomMember('42', '9');
      await service.leaveChatRoom('42');

      expect(members.first.userId, '9');
      expect(calls[0], contains('/api/v1/chat-rooms/42/members/9'));
      expect(
          calls[1], contains('/api/v1/chat-rooms/42/members/9/toggle-admin'));
      expect(calls[2], contains('/api/v1/chat-rooms/42/members/9/toggle-mute'));
      expect(calls[3], contains('/api/v1/chat-rooms/42/members/9/kick'));
      expect(calls[4], contains('/api/v1/chat-rooms/42/leave'));
    });

    test('Message.fromJson parses raw WebSocket message payload', () {
      final message = Message.fromJson({
        'id': 100,
        'content': 'from ws',
        'chatRoomId': 42,
        'senderId': 7,
        'senderName': 'WebSocket Sender',
        'type': 'TEXT',
        'status': 'SENT',
        'timestamp': '2024-01-01T10:04:00',
      });

      expect(message.chatRoomId, '42');
      expect(message.senderId, '7');
      expect(message.senderName, 'WebSocket Sender');
      expect(message.content, 'from ws');
    });

    test('agent task endpoints create and list tasks', () async {
      final calls = <String>[];
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          calls.add('$method $url');
          if (method == 'POST') {
            expect(body, {'chatRoomId': 42, 'prompt': 'summarize'});
            return jsonResponse({
              'data': {
                'id': 5,
                'chatRoomId': 42,
                'requestedById': 7,
                'prompt': 'summarize',
                'result': 'done',
                'status': 'SUCCEEDED',
              },
            });
          }
          return jsonResponse({
            'data': {
              'tasks': [
                {
                  'id': 5,
                  'chatRoomId': 42,
                  'requestedById': 7,
                  'prompt': 'summarize',
                  'status': 'SUCCEEDED',
                }
              ],
            },
          });
        },
      );

      final created = await service.createAgentTask('42', 'summarize');
      final tasks = await service.getAgentTasks('42');

      expect(created.status.name, 'succeeded');
      expect(tasks.single.id, '5');
      expect(calls[0], contains('/api/v1/agent-tasks'));
      expect(calls[1], contains('chatRoomId=42'));
    });

    test('createAgentTask can request workspace artifact output', () async {
      final service = ChatDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          expect(body, {
            'chatRoomId': 42,
            'prompt': 'summarize',
            'artifactWorkspaceId': 7,
            'artifactFolderId': 8,
            'artifactFileName': 'summary.txt',
          });
          return jsonResponse({
            'data': {
              'id': 5,
              'chatRoomId': 42,
              'requestedById': 7,
              'prompt': 'summarize',
              'result': 'done',
              'artifactWorkspaceId': 7,
              'artifactFolderId': 8,
              'artifactFileId': 9,
              'artifactFileName': 'summary.txt',
              'status': 'SUCCEEDED',
            },
          });
        },
      );

      final created = await service.createAgentTask(
        '42',
        'summarize',
        artifactWorkspaceId: '7',
        artifactFolderId: '8',
        artifactFileName: ' summary.txt ',
      );

      expect(created.result, 'done');
      expect(created.artifactWorkspaceId, '7');
      expect(created.artifactFolderId, '8');
      expect(created.artifactFileId, '9');
      expect(created.artifactFileName, 'summary.txt');
    });
  });
}

Future<dynamic> unusedRequest(
  String method,
  String url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  throw UnimplementedError();
}

http.Response jsonResponse(
  Object body, {
  int statusCode = 200,
}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
