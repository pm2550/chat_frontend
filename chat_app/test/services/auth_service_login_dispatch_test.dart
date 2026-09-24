import 'dart:convert';

import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/crypto/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CLIENT_ARGON2_BCRYPT login posts clientHash and never password',
      () async {
    final seenBodies = <Map<String, dynamic>>[];
    final service = AuthService.test(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/client-salt-params')) {
          return _json({
            'code': 200,
            'data': {
              'salt': 'AAAAAAAAAAAAAAAAAAAAAA',
              'argon2Params': 'm=32,t=1,p=1,v=19,hashLen=16',
              'scheme': PasswordHasher.clientScheme,
            },
          });
        }
        if (request.url.path.endsWith('/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          seenBodies.add(body);
          expect(body, contains('clientHash'));
          expect(body, isNot(contains('password')));
          return _loginOk();
        }
        return http.Response('not found', 404);
      }),
    );

    expect(await service.login('alice', 'secret-pw'), isTrue);
    expect(seenBodies, hasLength(1));
    expect(service.passwordUpgradePending, isFalse);
  });

  test('BCRYPT_LEGACY login posts password and marks upgrade pending',
      () async {
    final seenBodies = <Map<String, dynamic>>[];
    final service = AuthService.test(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/client-salt-params')) {
          return _json({
            'code': 200,
            'data': {
              'salt': 'LEGACYFAKESALT000000',
              'argon2Params': PasswordHasher.defaultArgon2Params,
              'scheme': PasswordHasher.legacyScheme,
            },
          });
        }
        if (request.url.path.endsWith('/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          seenBodies.add(body);
          expect(body['password'], 'legacy-pw');
          expect(body, isNot(contains('clientHash')));
          return _loginOk();
        }
        return http.Response('not found', 404);
      }),
    );

    expect(await service.login('legacy', 'legacy-pw'), isTrue);
    expect(seenBodies, hasLength(1));
    expect(service.passwordUpgradePending, isTrue);
  });

  test('409 PASSWORD_UPGRADE_REQUIRED retries with plaintext fallback',
      () async {
    final seenBodies = <Map<String, dynamic>>[];
    final service = AuthService.test(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/client-salt-params')) {
          return _json({
            'code': 200,
            'data': {
              'salt': 'AAAAAAAAAAAAAAAAAAAAAA',
              'argon2Params': 'm=32,t=1,p=1,v=19,hashLen=16',
              'scheme': PasswordHasher.clientScheme,
            },
          });
        }
        if (request.url.path.endsWith('/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          seenBodies.add(body);
          if (seenBodies.length == 1) {
            expect(body, contains('clientHash'));
            expect(body, isNot(contains('password')));
            return _json({'code': 409, 'message': 'PASSWORD_UPGRADE_REQUIRED'},
                statusCode: 409);
          }
          expect(body['password'], 'plain-after-race');
          expect(body, isNot(contains('clientHash')));
          return _loginOk();
        }
        return http.Response('not found', 404);
      }),
    );

    expect(await service.login('race-user', 'plain-after-race'), isTrue);
    expect(seenBodies, hasLength(2));
    expect(service.passwordUpgradePending, isTrue);
  });

  test('changePassword sends new credential fields expected by profile API',
      () async {
    final seenChangeBodies = <Map<String, dynamic>>[];
    final service = AuthService.test(
      passwordHasher: _FakePasswordHasher(),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/client-salt-params')) {
          return _json({
            'code': 200,
            'data': {
              'salt': 'legacy-fake-salt',
              'argon2Params': PasswordHasher.defaultArgon2Params,
              'scheme': PasswordHasher.legacyScheme,
            },
          });
        }
        if (request.url.path.endsWith('/login')) {
          return _loginOk();
        }
        if (request.url.path.endsWith('/profile/password')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          seenChangeBodies.add(body);
          expect(body['oldPassword'], 'old-pw');
          expect(body['newClientHash'], 'new-client-hash');
          expect(body['newClientSalt'], 'new-client-salt');
          expect(body['newArgon2Params'], 'm=32,t=1,p=1,v=19,hashLen=16');
          expect(body, isNot(contains('clientHash')));
          expect(body, isNot(contains('clientSalt')));
          expect(body, isNot(contains('argon2Params')));
          return _json({'success': true, 'message': '密码修改成功'});
        }
        return http.Response('not found', 404);
      }),
    );

    expect(await service.login('alice', 'login-pw'), isTrue);
    expect(service.passwordUpgradePending, isTrue);
    await service.changePassword(oldPassword: 'old-pw', newPassword: 'new-pw');

    expect(seenChangeBodies, hasLength(1));
    expect(service.passwordUpgradePending, isFalse);
  });

  test('changePassword sends oldClientHash for client-hash accounts', () async {
    final seenChangeBodies = <Map<String, dynamic>>[];
    final service = AuthService.test(
      passwordHasher: _FakePasswordHasher(),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/client-salt-params')) {
          return _json({
            'code': 200,
            'data': {
              'salt': 'existing-client-salt',
              'argon2Params': 'm=32,t=1,p=1,v=19,hashLen=16',
              'scheme': PasswordHasher.clientScheme,
            },
          });
        }
        if (request.url.path.endsWith('/login')) {
          return _loginOk();
        }
        if (request.url.path.endsWith('/profile/password')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          seenChangeBodies.add(body);
          expect(body['oldClientHash'], 'old-client-hash');
          expect(body, isNot(contains('oldPassword')));
          expect(body['newClientHash'], 'new-client-hash');
          return _json({'success': true, 'message': '密码修改成功'});
        }
        return http.Response('not found', 404);
      }),
    );

    expect(await service.login('alice', 'login-pw'), isTrue);
    await service.changePassword(oldPassword: 'old-pw', newPassword: 'new-pw');

    expect(seenChangeBodies, hasLength(1));
  });

  test('login hands the verified password to the E2EE unlock hook', () async {
    final unlockedWith = <String>[];
    final service = AuthService.test(
      passwordHasher: _FakePasswordHasher(),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/client-salt-params')) {
          return _json({
            'code': 200,
            'data': {
              'salt': 'existing-client-salt',
              'argon2Params': 'm=32,t=1,p=1,v=19,hashLen=16',
              'scheme': PasswordHasher.clientScheme,
            },
          });
        }
        if (request.url.path.endsWith('/login')) return _loginOk();
        return http.Response('not found', 404);
      }),
    )..onPasswordVerified = (password) async => unlockedWith.add(password);

    expect(await service.login('alice', 'login-pw'), isTrue);
    expect(unlockedWith, ['login-pw']);
  });

  test('changePassword carries the re-wrapped E2EE keys, or aborts when they cannot be re-wrapped',
      () async {
    final seenChangeBodies = <Map<String, dynamic>>[];
    AuthService build() => AuthService.test(
          passwordHasher: _FakePasswordHasher(),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/client-salt-params')) {
              return _json({
                'code': 200,
                'data': {
                  'salt': 'existing-client-salt',
                  'argon2Params': 'm=32,t=1,p=1,v=19,hashLen=16',
                  'scheme': PasswordHasher.clientScheme,
                },
              });
            }
            if (request.url.path.endsWith('/login')) return _loginOk();
            if (request.url.path.endsWith('/profile/password')) {
              seenChangeBodies
                  .add(jsonDecode(request.body) as Map<String, dynamic>);
              return _json({'success': true, 'message': '密码修改成功'});
            }
            return http.Response('not found', 404);
          }),
        );

    final service = build()
      ..passwordChangeExtras = (oldPassword, newPassword) async {
        expect(oldPassword, 'old-pw');
        expect(newPassword, 'new-pw');
        return {
          'e2eeKeyWraps': [
            {'version': 1, 'wrappedPrivateKey': 'w', 'wrapSalt': 's', 'wrapParams': 'p'},
          ],
        };
      };
    expect(await service.login('alice', 'login-pw'), isTrue);
    await service.changePassword(oldPassword: 'old-pw', newPassword: 'new-pw');
    expect(seenChangeBodies.single['e2eeKeyWraps'], hasLength(1));

    final failing = build()
      ..passwordChangeExtras =
          (_, __) async => throw Exception('无法解开当前的端到端加密密钥');
    expect(await failing.login('alice', 'login-pw'), isTrue);
    await expectLater(
      failing.changePassword(oldPassword: 'old-pw', newPassword: 'new-pw'),
      throwsA(isA<Exception>()),
    );
    expect(seenChangeBodies, hasLength(1), reason: '密钥换不了包装就不能改密码');
  });
}

class _FakePasswordHasher extends PasswordHasher {
  @override
  Future<ClientPasswordHash> hashNewPassword(String password) async {
    expect(password, 'new-pw');
    return const ClientPasswordHash(
      clientHash: 'new-client-hash',
      clientSalt: 'new-client-salt',
      argon2Params: 'm=32,t=1,p=1,v=19,hashLen=16',
    );
  }

  @override
  Future<String> hashWithSalt({
    required String password,
    required String salt,
    required String argon2Params,
  }) async {
    if (password == 'login-pw') {
      return 'login-client-hash';
    }
    expect(password, 'old-pw');
    expect(salt, 'existing-client-salt');
    expect(argon2Params, 'm=32,t=1,p=1,v=19,hashLen=16');
    return 'old-client-hash';
  }
}

http.Response _loginOk() {
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

http.Response _json(Map<String, dynamic> body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}
