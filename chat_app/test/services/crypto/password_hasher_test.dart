import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/services/crypto/password_hasher.dart';

void main() {
  test('hashWithSalt is deterministic for the same salt and params', () async {
    final hasher = PasswordHasher();
    const salt = 'AAAAAAAAAAAAAAAAAAAAAA';
    const params = 'm=32,t=1,p=1,v=19,hashLen=16';

    final first = await hasher.hashWithSalt(
      password: 'Correct Horse Battery Staple',
      salt: salt,
      argon2Params: params,
    );
    final second = await hasher.hashWithSalt(
      password: 'Correct Horse Battery Staple',
      salt: salt,
      argon2Params: params,
    );

    expect(first, second);
    expect(first, isNotEmpty);
    expect(first.contains('='), isFalse);
  });

  test('hashWithSalt changes when the password changes', () async {
    final hasher = PasswordHasher();
    const salt = 'AAAAAAAAAAAAAAAAAAAAAA';
    const params = 'm=32,t=1,p=1,v=19,hashLen=16';

    final first = await hasher.hashWithSalt(
      password: 'one-password',
      salt: salt,
      argon2Params: params,
    );
    final second = await hasher.hashWithSalt(
      password: 'another-password',
      salt: salt,
      argon2Params: params,
    );

    expect(first, isNot(second));
  });

  test('hashWithSalt changes when the salt changes', () async {
    final hasher = PasswordHasher();
    const params = 'm=32,t=1,p=1,v=19,hashLen=16';

    final first = await hasher.hashWithSalt(
      password: 'same-password',
      salt: 'AAAAAAAAAAAAAAAAAAAAAA',
      argon2Params: params,
    );
    final second = await hasher.hashWithSalt(
      password: 'same-password',
      salt: 'AQEBAQEBAQEBAQEBAQEBAQ',
      argon2Params: params,
    );

    expect(first, isNot(second));
  });

  // 标准答案由独立实现 argon2-cffi 用线上参数算出：换 Argon2 实现后
  // 输出必须逐字节不变，否则所有已有账号都登不上。
  test('production params match the reference Argon2id output', () async {
    final hasher = PasswordHasher();

    expect(
      await hasher.hashWithSalt(
        password: 'Correct Horse Battery Staple',
        salt: 'AAAAAAAAAAAAAAAAAAAAAA',
        argon2Params: PasswordHasher.defaultArgon2Params,
      ),
      'xMqKcF4a1H3kZsHIFe9HwMWnZzbMaGpjGpKIfBukOSI',
    );
    expect(
      await hasher.hashWithSalt(
        password: '中文密码🔑 with space',
        salt: 'AQEBAQEBAQEBAQEBAQEBAQ',
        argon2Params: PasswordHasher.defaultArgon2Params,
      ),
      'BLocYGrlZOA_FgEOjnATYNARDz9sutTrHfhNJpOFpgI',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('hashNewPassword produces a fresh base64url salt bundle', () async {
    final hasher = PasswordHasher();
    final bundle = await hasher.hashNewPassword('new-password');

    expect(bundle.clientHash, isNotEmpty);
    expect(bundle.clientHash.contains('='), isFalse);
    expect(bundle.clientSalt.length, greaterThanOrEqualTo(22));
    expect(bundle.clientSalt.contains('='), isFalse);
    expect(bundle.argon2Params, PasswordHasher.defaultArgon2Params);
  });

  test('client salt params recognizes client scheme only', () {
    expect(
      const ClientSaltParams(
        salt: 'salt',
        argon2Params: PasswordHasher.defaultArgon2Params,
        scheme: PasswordHasher.clientScheme,
      ).isClientArgon2,
      isTrue,
    );
    expect(
      const ClientSaltParams(
        salt: 'salt',
        argon2Params: PasswordHasher.defaultArgon2Params,
        scheme: PasswordHasher.legacyScheme,
      ).isClientArgon2,
      isFalse,
    );
  });
}
