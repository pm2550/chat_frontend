import 'dart:convert';

import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/points_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('PointsService error surfacing', () {
    test('invalid redeem code surfaces the server error message', () async {
      final service = PointsService(
        authService: _StubAuthService(
          http.Response.bytes(
            utf8.encode(jsonEncode({'error': '兑换码无效或已被使用'})),
            400,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

      await expectLater(
        service.redeem('BAD-CODE'),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('兑换码无效或已被使用'),
          ),
        ),
      );
    });

    test('prefers the "message" field when the server sends one', () async {
      final service = PointsService(
        authService: _StubAuthService(
          http.Response.bytes(
            utf8.encode(jsonEncode({'message': '积分不足'})),
            402,
          ),
        ),
      );

      await expectLater(
        service.previewCost('image_generation'),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('积分不足'),
          ),
        ),
      );
    });

    test('falls back to the status code when the body is not JSON', () async {
      final service = PointsService(
        authService: _StubAuthService(http.Response('<html>502</html>', 502)),
      );

      await expectLater(
        service.fetchBalance(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('请求失败 (502)'),
          ),
        ),
      );
    });
  });
}

class _StubAuthService extends AuthService {
  _StubAuthService(this._response) : super.test();

  final http.Response _response;

  @override
  Future<http.Response> authenticatedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return _response;
  }
}
