import 'dart:convert';

import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/crypto/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用恢复码找回后换密码包装时，服务器要再确认一次当前密码：客户端给的"证明"
/// 就是登录时发的同一个 clientHash（明文密码不出设备）；旧式账号给不出。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  AuthService build(String scheme, List<String> loginHashes) =>
      AuthService.test(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/client-salt-params')) {
            return _json({
              'code': 200,
              'data': {
                'salt': 'AAAAAAAAAAAAAAAAAAAAAA',
                'argon2Params': 'm=32,t=1,p=1,v=19,hashLen=16',
                'scheme': scheme,
              },
            });
          }
          if (request.url.path.endsWith('/login')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['clientHash'] != null) {
              loginHashes.add(body['clientHash'] as String);
            }
            return _json({
              'code': 200,
              'data': {
                'accessToken': 'access-token',
                'refreshToken': 'refresh-token',
                'user': {
                  'id': 1,
                  'username': 'alice',
                  'email': 'alice@example.com',
                  'displayName': 'Alice',
                  'createdAt': '2026-06-05T00:00:00Z',
                  'roles': ['USER'],
                },
              },
            });
          }
          return http.Response('not found', 404);
        }),
      );

  test('the proof is the same client hash the login sends', () async {
    final loginHashes = <String>[];
    final service = build(PasswordHasher.clientScheme, loginHashes);
    expect(await service.login('alice', 'secret-pw'), isTrue);

    final proof = await service.currentPasswordProof('secret-pw');
    expect(proof, loginHashes.single);
    expect(proof, isNot(contains('secret-pw')));
    expect(await service.currentPasswordProof('other-pw'),
        isNot(loginHashes.single));
  });

  test('legacy accounts have no proof', () async {
    final service = build(PasswordHasher.legacyScheme, []);
    expect(await service.login('alice', 'legacy-pw'), isTrue);
    expect(await service.currentPasswordProof('legacy-pw'), isNull);
  });
}

http.Response _json(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
