import 'dart:convert';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/web_push_platform.dart';
import 'package:chat_app/services/web_push_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('getStatus reflects browser support and server VAPID configuration',
      () async {
    final auth = AuthService.test(
      httpClient: MockClient((request) async {
        expect(request.url.toString(), ApiConstants.webPushVapidPublicKey);
        return _json({
          'code': 200,
          'data': {'publicKey': 'public-key', 'configured': true},
        });
      }),
    );
    final service = WebPushService(
      authService: auth,
      platformBackend: _FakeWebPushPlatform(
        supported: true,
        standalone: true,
        permissionValue: 'default',
      ),
    );

    final status = await service.getStatus();

    expect(status.supported, isTrue);
    expect(status.standalone, isTrue);
    expect(status.configured, isTrue);
    expect(status.canRequest, isTrue);
  });

  test('enable subscribes with VAPID key and posts endpoint keys to backend',
      () async {
    Map<String, dynamic>? postedBody;
    final auth = AuthService.test(
      httpClient: MockClient((request) async {
        if (request.url.toString() == ApiConstants.webPushVapidPublicKey) {
          return _json({
            'code': 200,
            'data': {'publicKey': 'public-key', 'configured': true},
          });
        }
        if (request.url.toString() == ApiConstants.webPushSubscribe) {
          postedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'code': 200, 'data': null});
        }
        return http.Response('not found', 404);
      }),
    );
    final platform = _FakeWebPushPlatform(
      supported: true,
      standalone: true,
      permissionValue: 'default',
    );
    final service = WebPushService(
      authService: auth,
      platformBackend: platform,
    );

    final result = await service.enable();

    expect(result.success, isTrue);
    expect(platform.seenVapidKey, 'public-key');
    expect(postedBody?['endpoint'], 'https://push.example/sub');
    expect(postedBody?['keys']['p256dh'], 'p256dh-key');
    expect(postedBody?['keys']['auth'], 'auth-secret');
  });
}

http.Response _json(Map<String, dynamic> body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _FakeWebPushPlatform implements WebPushPlatform {
  _FakeWebPushPlatform({
    required this.supported,
    required this.standalone,
    required String permissionValue,
  }) : _permission = permissionValue;

  final bool supported;
  final bool standalone;
  String _permission;
  String? seenVapidKey;

  @override
  bool get isSupported => supported;

  @override
  bool get isStandalone => standalone;

  @override
  String get permission => _permission;

  @override
  Future<Map<String, dynamic>> subscribe(String vapidPublicKey) async {
    seenVapidKey = vapidPublicKey;
    _permission = 'granted';
    return {
      'ok': true,
      'endpoint': 'https://push.example/sub',
      'keys': {
        'p256dh': 'p256dh-key',
        'auth': 'auth-secret',
      },
      'userAgent': 'unit-test',
    };
  }

  @override
  Future<Map<String, dynamic>> unsubscribe() async {
    _permission = 'default';
    return {
      'ok': true,
      'endpoint': 'https://push.example/sub',
    };
  }
}
