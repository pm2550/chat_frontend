import 'dart:async';
import 'dart:convert';

import 'package:chat_app/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = {
  'id': 1,
  'username': 'alice',
  'email': 'alice@example.com',
  'displayName': 'Alice',
  'createdAt': '2026-06-05T00:00:00Z',
  'roles': ['USER'],
};

Future<AuthService> _signedInService(
  Future<http.Response> Function(http.Request request) handler,
) async {
  SharedPreferences.setMockInitialValues({
    'access_token': 'expired-access',
    'refresh_token': 'old-refresh',
    'user_data': jsonEncode(_user),
  });
  final service = AuthService.test(httpClient: MockClient(handler));
  await service.initialize(validateInBackground: false);
  return service;
}

http.Response _json(Map<String, dynamic> body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  test('stores the rotated refresh token so the session keeps sliding',
      () async {
    final service = await _signedInService((request) async {
      return _json({
        'code': 200,
        'data': {
          'accessToken': 'new-access',
          'refreshToken': 'new-refresh',
          'user': _user,
        },
      });
    });

    expect(await service.refreshAccessToken(), isTrue);
    expect(service.accessToken, 'new-access');
    expect(service.refreshToken, 'new-refresh');
    expect(service.refreshTokenRejected, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('refresh_token'), 'new-refresh');
  });

  test('a refresh token the server rejects counts as a real logout', () async {
    final service = await _signedInService((request) async {
      return _json({'code': 400, 'message': '无效的令牌'}, statusCode: 400);
    });

    expect(await service.refreshAccessToken(), isFalse);
    expect(service.refreshTokenRejected, isTrue);
  });

  test('a backend restart (502) does not count as a logout', () async {
    final service = await _signedInService((request) async {
      return http.Response('<html>502 Bad Gateway</html>', 502);
    });

    expect(await service.refreshAccessToken(), isFalse);
    expect(service.refreshTokenRejected, isFalse);
    expect(service.refreshToken, 'old-refresh');
  });

  test('a network failure does not count as a logout', () async {
    final service = await _signedInService((request) async {
      throw http.ClientException('connection reset');
    });

    expect(await service.refreshAccessToken(), isFalse);
    expect(service.refreshTokenRejected, isFalse);
  });

  test('concurrent 401s share a single refresh request', () async {
    var calls = 0;
    final gate = Completer<void>();
    final service = await _signedInService((request) async {
      calls++;
      await gate.future;
      return _json({
        'code': 200,
        'data': {
          'accessToken': 'new-access',
          'refreshToken': 'new-refresh',
          'user': _user,
        },
      });
    });

    final results = [
      service.refreshAccessToken(),
      service.refreshAccessToken(),
      service.refreshAccessToken(),
    ];
    gate.complete();

    expect(await Future.wait(results), [true, true, true]);
    expect(calls, 1);
  });
}
