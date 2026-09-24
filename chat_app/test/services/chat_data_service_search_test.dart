import 'dart:convert';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

http.Response _json(Object body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _message(int id, int roomId) => {
      'id': id,
      'content': '关键词 $id',
      'chatRoomId': roomId,
      'senderName': '好友',
      'createdAt': '2024-01-01T10:00:00',
    };

void main() {
  test(
      'room search reads the paging metadata the backend now returns '
      '(page 2 is no longer reported as page 0)', () async {
    Uri? requested;
    final service = ChatDataService(
      authenticatedRequest: (method, url, {headers, body}) async {
        requested = Uri.parse(url);
        // Shape of ChatRoomMessageSearchController's response.
        return _json({
          'messages': [_message(21, 7)],
          'results': [],
          'keyword': '关键词',
          'limit': 20,
          'offset': 20,
          'currentPage': 1,
          'totalPages': 3,
          'totalElements': 45,
          'hasNext': true,
          'hasPrevious': true,
        });
      },
    );

    final page = await service.searchMessages('7', '关键词', page: 1);

    expect(requested?.path, '/api/v1/chat-rooms/7/messages/search');
    expect(requested?.queryParameters['offset'], '20');
    expect(requested?.queryParameters['limit'], '20');
    expect(page.currentPage, 1);
    expect(page.totalPages, 3);
    expect(page.hasPrevious, isTrue);
    expect(page.hasNext, isTrue);
  });

  test('global search hits the cross-room endpoint and keeps room ids',
      () async {
    Uri? requested;
    final service = ChatDataService(
      authenticatedRequest: (method, url, {headers, body}) async {
        expect(method, 'GET');
        requested = Uri.parse(url);
        return _json({
          'messages': [_message(5, 7), _message(6, 9)],
          'keyword': '关键词',
          'currentPage': 0,
          'totalPages': 1,
          'totalElements': 2,
          'hasNext': false,
          'hasPrevious': false,
        });
      },
    );

    final page = await service.searchAllMessages('关键词');

    expect(requested.toString(), startsWith(ApiConstants.searchAllMessages));
    expect(requested?.queryParameters['q'], '关键词');
    expect(requested?.queryParameters['page'], '0');
    expect(page.messages.map((m) => m.chatRoomId), ['7', '9']);
    expect(page.totalElements, 2);
  });
}
