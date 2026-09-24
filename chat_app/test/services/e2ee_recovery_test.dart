import 'dart:convert';

import 'package:chat_app/services/e2ee/e2ee_crypto.dart';
import 'package:chat_app/services/e2ee/e2ee_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

/// 恢复码：生成格式、输入宽松、校验位能抓住手误、HKDF 包装往返、mailto 链接。
void main() {
  const data = '7K3MQX2F0ABCDEFGHJKMNPQRST';

  group('recovery code format', () {
    test('generated codes are 7 groups of 4 Crockford chars with a checksum',
        () {
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        final code = E2eeRecoveryCode.generate();
        expect(
            code.formatted,
            matches(
                RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){6}[0-9A-HJKMNP-TV-Z]{4}$')));
        expect(code.data, hasLength(26), reason: '26 x 5 bits = 130 bits');
        expect(code.lastGroup, hasLength(4));
        // 自己解析自己：校验位一致。
        expect(E2eeRecoveryCode.parse(code.formatted).data, code.data);
        seen.add(code.data);
      }
      expect(seen, hasLength(50), reason: 'CSPRNG: no repeats');
    });

    test('input is forgiving: case, spaces, dashes, O/0 and I/L/1', () {
      final code = E2eeRecoveryCode.fromData(data);
      final sloppy = code.formatted
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll('0', 'o')
          .replaceAll('1', 'l');
      expect(E2eeRecoveryCode.parse('  $sloppy \n').data, code.data);
      expect(E2eeRecoveryCode.parse(code.compact).data, code.data);
      expect(code.matchesLastGroup(code.lastGroup.toLowerCase()), isTrue);
      expect(code.matchesLastGroup('ZZZZ'), code.lastGroup == 'ZZZZ');
    });

    test('checksum catches single-character typos and swapped neighbours', () {
      final code = E2eeRecoveryCode.fromData(data);
      final chars = code.compact.split('');
      var substitutions = 0;
      var undetectedSubstitutions = 0;
      for (var i = 0; i < chars.length; i++) {
        for (final replacement in kCrockfordAlphabet.split('')) {
          if (replacement == chars[i]) continue;
          final typo = [...chars]..[i] = replacement;
          substitutions++;
          try {
            E2eeRecoveryCode.parse(typo.join());
            undetectedSubstitutions++;
          } on E2eeRecoveryCodeFormatException {
            // 抓住了。
          }
        }
      }
      // 868 个单字符错误，10 位校验漏检的期望约 0.85 个。
      expect(substitutions, 28 * 31);
      expect(undetectedSubstitutions, lessThanOrEqualTo(3));

      var swaps = 0;
      var undetectedSwaps = 0;
      for (var i = 0; i + 1 < chars.length; i++) {
        if (chars[i] == chars[i + 1]) continue;
        final swapped = [...chars]
          ..[i] = chars[i + 1]
          ..[i + 1] = chars[i];
        swaps++;
        try {
          E2eeRecoveryCode.parse(swapped.join());
          undetectedSwaps++;
        } on E2eeRecoveryCodeFormatException {
          // 抓住了。
        }
      }
      expect(swaps, greaterThan(20));
      expect(undetectedSwaps, 0);

      expect(() => E2eeRecoveryCode.parse(code.compact.substring(1)),
          throwsA(isA<E2eeRecoveryCodeFormatException>()));
      expect(() => E2eeRecoveryCode.parse('${code.compact}U'),
          throwsA(isA<E2eeRecoveryCodeFormatException>()));
      expect(() => E2eeRecoveryCode.parse(''),
          throwsA(isA<E2eeRecoveryCodeFormatException>()));
    });

    test('toString never prints the code', () {
      final code = E2eeRecoveryCode.fromData(data);
      expect('$code', isNot(contains(code.data.substring(0, 6))));
    });
  });

  group('recovery wrap', () {
    test('round trip: the code opens the wrap, a different code does not',
        () async {
      final pair = await E2eeCrypto.generateKeyPair(3);
      final code = E2eeRecoveryCode.generate();
      final salt = e2eeRandomBytes(16);
      final wrapped = E2eeRecovery.wrap(
        wrapKey:
            E2eeRecovery.deriveWrapKey(code: code, salt: salt, userId: '7'),
        salt: salt,
        userId: '7',
        keyPair: pair,
      );
      expect(wrapped.wrapParams, kE2eeRecoveryWrapParams);
      expect(base64Decode(wrapped.wrappedPrivateKey), hasLength(12 + 32 + 16));
      expect(wrapped.toWrapJson().toString(), isNot(contains(code.data)));

      final opened = await E2eeRecovery.unwrap(
        code: E2eeRecoveryCode.parse(code.formatted.toLowerCase()),
        userId: '7',
        wrapped: wrapped,
      );
      expect(opened.privateKey, pair.privateKey);
      expect(opened.publicKey, pair.publicKey);
      expect(opened.version, 3);

      await expectLater(
        E2eeRecovery.unwrap(
            code: E2eeRecoveryCode.generate(), userId: '7', wrapped: wrapped),
        throwsA(isA<E2eeWrongRecoveryCodeException>()),
      );
      // 挪给别的用户、别的版本都解不开（AAD 绑定）。
      await expectLater(
        E2eeRecovery.unwrap(code: code, userId: '8', wrapped: wrapped),
        throwsA(isA<E2eeWrongRecoveryCodeException>()),
      );
      await expectLater(
        E2eeRecovery.unwrap(
          code: code,
          userId: '7',
          wrapped: E2eeWrappedKey(
            version: 4,
            publicKey: wrapped.publicKey,
            wrappedPrivateKey: wrapped.wrappedPrivateKey,
            wrapSalt: wrapped.wrapSalt,
            wrapParams: wrapped.wrapParams,
          ),
        ),
        throwsA(isA<E2eeWrongRecoveryCodeException>()),
      );
    });

    test('a recovery wrap cannot be opened as a password wrap', () async {
      final pair = await E2eeCrypto.generateKeyPair(1);
      final code = E2eeRecoveryCode.generate();
      final salt = e2eeRandomBytes(16);
      final wrapped = E2eeRecovery.wrap(
        wrapKey:
            E2eeRecovery.deriveWrapKey(code: code, salt: salt, userId: '7'),
        salt: salt,
        userId: '7',
        keyPair: pair,
      );
      await expectLater(
        E2eeCrypto.unwrapPrivateKey(
          password: code.formatted,
          userId: '7',
          wrapped: E2eeWrappedKey(
            version: 1,
            publicKey: wrapped.publicKey,
            wrappedPrivateKey: wrapped.wrappedPrivateKey,
            wrapSalt: wrapped.wrapSalt,
            wrapParams: 'm=1024,t=1,p=1,v=19,hashLen=32',
          ),
        ),
        throwsA(isA<E2eeWrongPasswordException>()),
      );
    });
  });

  group('mailto', () {
    test('To is the own address; Chinese subject and body are UTF-8 encoded',
        () {
      final code = E2eeRecoveryCode.fromData(data);
      final uri = E2eeRecoveryMail.buildUri(
          to: ' alice.w+chat@example.com ', code: code);
      final raw = uri.toString();

      expect(uri.scheme, 'mailto');
      expect(uri.path, 'alice.w+chat@example.com');
      expect(
        raw,
        startsWith('mailto:alice.w+chat@example.com?subject='
            '${Uri.encodeComponent('PM chat 端到端加密恢复码')}&body='),
      );
      // RFC 6068：空格是 %20（不能是 +，邮件应用会原样显示 +），换行是 %0D%0A。
      expect(raw, contains('PM%20chat%20%E7%AB%AF'));
      expect(raw, contains('%0D%0A'));
      expect(raw.split('?').last, isNot(contains('+')));
      expect(raw, isNot(contains(' ')));

      final subject = Uri.decodeComponent(
          RegExp(r'subject=([^&]*)').firstMatch(raw)!.group(1)!);
      final body = Uri.decodeComponent(
          RegExp(r'body=([^&]*)').firstMatch(raw)!.group(1)!);
      expect(subject, 'PM chat 端到端加密恢复码');
      expect(body, contains(code.formatted));
      expect(body, contains('任何能读取这个邮箱的人'));
      expect(body, contains('登录密码和恢复码都丢了'));
    });

    test('addresses that would change the link are rejected', () {
      final code = E2eeRecoveryCode.fromData(data);
      for (final bad in [
        '',
        'not-an-email',
        'a@b.com?bcc=evil@x.com',
        'a@b.com&body=x',
        'a#b@c.com',
      ]) {
        expect(() => E2eeRecoveryMail.buildUri(to: bad, code: code),
            throwsFormatException,
            reason: bad);
      }
    });
  });
}
