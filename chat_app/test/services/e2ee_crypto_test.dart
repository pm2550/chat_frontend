import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_app/services/e2ee/e2ee_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试里用轻量 Argon2 参数，免得每次包装都跑 64MB。
const _fastArgon2 = 'm=1024,t=1,p=1,v=19,hashLen=32';

Uint8List _hex(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

void main() {
  late E2eeKeyPair alice;
  late E2eeKeyPair bob;
  late E2eeKeyPair mallory;

  setUpAll(() async {
    alice = await E2eeCrypto.generateKeyPair(1);
    bob = await E2eeCrypto.generateKeyPair(3);
    mallory = await E2eeCrypto.generateKeyPair(1);
  });

  String sealFromAlice(String text, {String roomId = '42'}) => E2eeCrypto.seal(
        roomId: roomId,
        senderId: '1',
        mine: alice,
        recipientId: '2',
        recipientKeyVersion: bob.version,
        peerPublicKey: bob.publicKey,
        payload: E2eePayload(kind: 'text', text: text),
      );

  test('HKDF-SHA256 matches RFC 5869 test case 1', () {
    final okm = E2eeCrypto.hkdfSha256(
      ikm: _hex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'),
      salt: _hex('000102030405060708090a0b0c'),
      info: _hex('f0f1f2f3f4f5f6f7f8f9'),
      length: 42,
    );
    expect(
      okm,
      _hex('3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
          '34007208d5b887185865'),
    );
  });

  test('X25519 agrees with RFC 7748 section 6.1', () async {
    final a = await E2eeCrypto.keyPairFromPrivate(
      1,
      _hex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'),
    );
    expect(
      a.publicKey,
      _hex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a'),
    );
    final shared = E2eeCrypto.sharedSecret(
      a,
      _hex('de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f'),
    );
    expect(
      shared,
      _hex('4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742'),
    );
  });

  test('both parties decrypt; the ciphertext carries no plaintext', () {
    const text = '明天 9 点老地方见 🔐';
    final sealed = sealFromAlice(text);
    expect(utf8.decode(base64Decode(sealed)), isNot(contains('老地方')));

    final envelope = E2eeEnvelope.tryParse(sealed)!;
    expect(envelope.senderId, '1');
    expect(envelope.senderKeyVersion, 1);
    expect(envelope.recipientKeyVersion, 3);

    // 接收方：自己的 rk 私钥 + 发送方 sk 公钥。
    expect(
      E2eeCrypto.open(
              envelope: envelope, mine: bob, peerPublicKey: alice.publicKey)
          .text,
      text,
    );
    // 发送方自己的其他设备：sk 私钥 + 接收方 rk 公钥。
    expect(
      E2eeCrypto.open(
              envelope: envelope, mine: alice, peerPublicKey: bob.publicKey)
          .text,
      text,
    );
  });

  test('same text encrypts differently every time', () {
    expect(sealFromAlice('hi'), isNot(sealFromAlice('hi')));
  });

  test('tampering with ciphertext or any header field is detected', () {
    final envelope = E2eeEnvelope.tryParse(sealFromAlice('transfer 100'))!;

    E2eeEnvelope copy({
      String? roomId,
      String? senderId,
      String? recipientId,
      Uint8List? ciphertext,
    }) =>
        E2eeEnvelope(
          roomId: roomId ?? envelope.roomId,
          senderId: senderId ?? envelope.senderId,
          senderKeyVersion: envelope.senderKeyVersion,
          recipientId: recipientId ?? envelope.recipientId,
          recipientKeyVersion: envelope.recipientKeyVersion,
          salt: envelope.salt,
          nonce: envelope.nonce,
          ciphertext: ciphertext ?? envelope.ciphertext,
        );

    final flipped = Uint8List.fromList(envelope.ciphertext);
    flipped[0] ^= 0x01;
    for (final tampered in [
      copy(ciphertext: flipped),
      copy(roomId: '43'), // 挪到别的会话
      copy(senderId: '2', recipientId: '1'), // 冒充成对方发的
    ]) {
      expect(
        () => E2eeCrypto.open(
          envelope: tampered,
          mine: bob,
          peerPublicKey: alice.publicKey,
        ),
        throwsA(isA<E2eeCryptoException>()),
      );
    }
  });

  test('a third key pair cannot decrypt or forge as the sender', () {
    final envelope = E2eeEnvelope.tryParse(sealFromAlice('private'))!;
    expect(
      () => E2eeCrypto.open(
          envelope: envelope, mine: mallory, peerPublicKey: alice.publicKey),
      throwsA(isA<E2eeCryptoException>()),
    );

    // Mallory 用自己的私钥冒充 alice 给 bob 发：bob 用 alice 的真实公钥解不开。
    final forged = E2eeCrypto.seal(
      roomId: '42',
      senderId: '1',
      mine: mallory,
      recipientId: '2',
      recipientKeyVersion: bob.version,
      peerPublicKey: bob.publicKey,
      payload: const E2eePayload(kind: 'text', text: 'from alice, honest'),
    );
    expect(
      () => E2eeCrypto.open(
        envelope: E2eeEnvelope.tryParse(forged)!,
        mine: bob,
        peerPublicKey: alice.publicKey,
      ),
      throwsA(isA<E2eeCryptoException>()),
    );
  });

  test('unknown envelopes are not parsed', () {
    expect(E2eeEnvelope.tryParse(null), isNull);
    expect(E2eeEnvelope.tryParse('not base64 at all'), isNull);
    expect(
      E2eeEnvelope.tryParse(base64Encode(utf8.encode('{"v":1,"alg":"x"}'))),
      isNull,
    );
  });

  group('private key wrapping', () {
    test('every device unwraps the same key with the password', () async {
      final wrapped = await E2eeCrypto.wrapPrivateKey(
        password: 'correct horse',
        userId: '1',
        keyPair: alice,
        argon2Params: _fastArgon2,
      );
      expect(wrapped.wrappedPrivateKey,
          isNot(contains(base64Encode(alice.privateKey))));

      // "手机"和"网页"各自从服务器那份包装解开，得到同一把私钥。
      final phone = await E2eeCrypto.unwrapPrivateKey(
          password: 'correct horse', userId: '1', wrapped: wrapped);
      final web = await E2eeCrypto.unwrapPrivateKey(
          password: 'correct horse', userId: '1', wrapped: wrapped);
      expect(phone.privateKey, alice.privateKey);
      expect(web.publicKey, alice.publicKey);

      final sealed = sealFromAlice('multi-device');
      expect(
        E2eeCrypto.open(
          envelope: E2eeEnvelope.tryParse(sealed)!,
          mine: web,
          peerPublicKey: bob.publicKey,
        ).text,
        'multi-device',
      );
    });

    test('wrong password, other user or swapped public key fails', () async {
      final wrapped = await E2eeCrypto.wrapPrivateKey(
        password: 'correct horse',
        userId: '1',
        keyPair: alice,
        argon2Params: _fastArgon2,
      );
      await expectLater(
        E2eeCrypto.unwrapPrivateKey(
            password: 'wrong', userId: '1', wrapped: wrapped),
        throwsA(isA<E2eeWrongPasswordException>()),
      );
      await expectLater(
        E2eeCrypto.unwrapPrivateKey(
            password: 'correct horse', userId: '2', wrapped: wrapped),
        throwsA(isA<E2eeWrongPasswordException>()),
      );
      await expectLater(
        E2eeCrypto.unwrapPrivateKey(
          password: 'correct horse',
          userId: '1',
          wrapped: E2eeWrappedKey(
            version: wrapped.version,
            publicKey: mallory.publicKeyBase64,
            wrappedPrivateKey: wrapped.wrappedPrivateKey,
            wrapSalt: wrapped.wrapSalt,
            wrapParams: wrapped.wrapParams,
          ),
        ),
        throwsA(isA<E2eeCryptoException>()),
      );
    });

    test('each wrap uses a fresh salt', () async {
      final first = await E2eeCrypto.wrapPrivateKey(
          password: 'pw',
          userId: '1',
          keyPair: alice,
          argon2Params: _fastArgon2);
      final second = await E2eeCrypto.wrapPrivateKey(
          password: 'pw',
          userId: '1',
          keyPair: alice,
          argon2Params: _fastArgon2);
      expect(first.wrapSalt, isNot(second.wrapSalt));
      expect(first.wrappedPrivateKey, isNot(second.wrappedPrivateKey));
    });
  });

  test('attachments round-trip and detect tampering', () async {
    final bytes = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final sealed = await E2eeCrypto.encryptAttachment(
      bytes: bytes,
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
    );
    expect(sealed.ciphertext.length, bytes.length + 16);
    expect(
      await E2eeCrypto.decryptAttachment(
          ciphertext: sealed.ciphertext, key: sealed.key),
      bytes,
    );
    final roundTripKey = E2eeAttachmentKey.fromJson(
      jsonDecode(jsonEncode(sealed.key.toJson())) as Map<String, dynamic>,
    );
    expect(roundTripKey.name, 'photo.jpg');

    final broken = Uint8List.fromList(sealed.ciphertext);
    broken[10] ^= 0xff;
    await expectLater(
      E2eeCrypto.decryptAttachment(ciphertext: broken, key: roundTripKey),
      throwsA(isA<E2eeCryptoException>()),
    );
  });
}
