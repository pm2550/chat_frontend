import 'dart:convert';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/services/contact_data_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('ContactDataService', () {
    test('getFriends reads backend friends response', () async {
      final service = ContactDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'GET');
          expect(Uri.parse(url).path, '/api/v1/friends');
          return jsonResponse({
            'friends': [
              {
                'id': 2,
                'username': 'alice',
                'email': 'alice@example.com',
                'displayName': 'Alice',
                'onlineStatus': 'ONLINE',
                'createdAt': '2024-01-01T10:00:00',
              },
            ],
          });
        },
      );

      final friends = await service.getFriends();

      expect(friends, hasLength(1));
      expect(friends.first.id, '2');
      expect(friends.first.displayName, 'Alice');
      expect(friends.first.onlineStatus.name, 'online');
    });

    test('getReceivedFriendRequests parses friendship summaries', () async {
      final service = ContactDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(Uri.parse(url).path, '/api/v1/friends/requests/received');
          return jsonResponse({
            'requests': [
              {
                'id': 10,
                'status': 'PENDING',
                'user': {
                  'id': 3,
                  'username': 'requester',
                  'email': 'requester@example.com',
                  'displayName': 'Requester',
                  'createdAt': '2024-01-01T10:00:00',
                },
                'friend': {
                  'id': 4,
                  'username': 'me',
                  'email': 'me@example.com',
                  'displayName': 'Me',
                  'createdAt': '2024-01-01T10:00:00',
                },
              },
            ],
          });
        },
      );

      final requests = await service.getReceivedFriendRequests();

      expect(requests, hasLength(1));
      expect(requests.first.id, '10');
      expect(requests.first.user.displayName, 'Requester');
      expect(requests.first.friend.id, '4');
    });

    test('searchUsers calls profile search and reads data list', () async {
      final service = ContactDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          final uri = Uri.parse(url);
          expect(method, 'GET');
          expect(uri.path, '/api/profile/search');
          expect(uri.queryParameters['keyword'], 'ali');
          expect(uri.queryParameters['limit'], '5');
          return jsonResponse({
            'success': true,
            'data': [
              {
                'id': 5,
                'username': 'alice',
                'email': 'alice@example.com',
                'displayName': 'Alice',
                'createdAt': '2024-01-01T10:00:00',
              },
            ],
          });
        },
      );

      final users = await service.searchUsers(' ali ', limit: 5);

      expect(users, hasLength(1));
      expect(users.first.username, 'alice');
    });

    test('send accept and decline use backend friends endpoints', () async {
      final calls = <String>[];
      final service = ContactDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          calls.add('$method ${Uri.parse(url).path}');
          if (url.contains('/decline/')) {
            return jsonResponse({'message': '已拒绝好友请求'});
          }
          return jsonResponse({
            'friendship': {
              'id': 11,
              'status': url.contains('/accept/') ? 'ACCEPTED' : 'PENDING',
              'user': {
                'id': 3,
                'username': 'alice',
                'email': 'alice@example.com',
                'displayName': 'Alice',
                'createdAt': '2024-01-01T10:00:00',
              },
              'friend': {
                'id': 4,
                'username': 'bob',
                'email': 'bob@example.com',
                'displayName': 'Bob',
                'createdAt': '2024-01-01T10:00:00',
              },
            },
          });
        },
      );

      final sent = await service.sendFriendRequest('4');
      final accepted = await service.acceptFriendRequest('3');
      await service.declineFriendRequest('3');

      expect(sent.status, 'PENDING');
      expect(accepted.status, 'ACCEPTED');
      expect(calls, [
        'POST /api/v1/friends/request/4',
        'POST /api/v1/friends/accept/3',
        'POST /api/v1/friends/decline/3',
      ]);
    });

    test('createPrivateChat parses chatRoom response', () async {
      final service = ContactDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(method, 'POST');
          expect(Uri.parse(url).path, '/api/v1/chat-rooms/private/7');
          return jsonResponse({
            'message': '私聊创建成功',
            'chatRoom': {
              'id': 42,
              'name': 'Alice & Bob',
              'roomType': 'PRIVATE',
              'isPrivate': true,
              'createdAt': '2024-01-01T10:00:00',
            },
          });
        },
      );

      final chat = await service.createPrivateChat('7');

      expect(chat.id, '42');
      expect(chat.name, 'Alice & Bob');
      expect(chat.type, ChatType.private);
    });

    test('throws ContactDataException for backend failure', () async {
      final service = ContactDataService(
        authenticatedRequest: (method, url, {headers, body}) async {
          return jsonResponse({'error': '不能添加自己为好友'}, statusCode: 400);
        },
      );

      expect(
        () => service.sendFriendRequest('1'),
        throwsA(isA<ContactDataException>()),
      );
    });
  });
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
