import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/e2ee/e2ee_crypto.dart';
import 'package:chat_app/services/encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_e2ee_server.dart';

EncryptionService device(FakeE2eeServer server, String userId) =>
    e2eeDevice(server, userId);

Chat dm(String id) => Chat(
      id: id,
      name: 'dm',
      type: ChatType.private,
      createdAt: DateTime(2026),
    );

Message incoming({
  required String id,
  required String senderId,
  required String envelope,
  String roomId = '42',
}) {
  return Message.fromJson({
    'id': id,
    'content': kE2eeServerPlaceholder,
    'senderId': senderId,
    'chatRoomId': roomId,
    'type': 'TEXT',
    'encryptedContent': envelope,
    'encryptionVersion': kE2eeEncryptionVersion,
    'createdAt': '2026-09-24T10:00:00',
  });
}

void main() {
  late FakeE2eeServer server;

  setUp(() {
    server = FakeE2eeServer()
      ..passwords['1'] = 'alice-pw'
      ..passwords['2'] = 'bob-pw'
      ..roomMembers['42'] = ['1', '2'];
  });

  tearDown(() => Message.contentRevealer = null);

  test(
      "both humans enabled: alice encrypts, bob and alice's other device decrypt",
      () async {
    final alicePhone = device(server, '1');
    final bob = device(server, '2');
    await alicePhone.enable('alice-pw');
    await bob.enable('bob-pw');

    final state = await alicePhone.roomState(dm('42'), refresh: true);
    expect(state.mode, E2eeRoomMode.active);

    final envelope = await alicePhone.sealText(dm('42'), '周五的方案我改好了');
    expect(envelope, isNotNull);
    final message = incoming(id: '100', senderId: '1', envelope: envelope!);
    expect(message.content, kE2eeServerPlaceholder,
        reason: 'no revealer installed: old-client placeholder is shown');

    // bob：第一次没钉过 alice 的公钥，先显示"正在解密"，取到公钥后能解开。
    expect(bob.reveal(message).content, contains('正在解密'));
    await bob.waitForPendingKeyFetches();
    expect(bob.reveal(message).content, '周五的方案我改好了');
    expect(bob.isReadable(message), isTrue);

    // alice 的电脑：新设备登录（密码刚验证过）→ 解开同一把私钥 → 读自己发过的消息。
    final aliceDesktop = device(server, '1');
    await aliceDesktop.ensureLoaded();
    expect(aliceDesktop.reveal(message).content, contains('解锁'));
    await aliceDesktop.handleVerifiedPassword('alice-pw');
    await aliceDesktop.roomState(dm('42'), refresh: true);
    expect(aliceDesktop.reveal(message).content, '周五的方案我改好了');
  });

  test(
      'Message.fromJson reveals through the installed hook; toJson never stores plaintext',
      () async {
    final alice = device(server, '1');
    final bob = device(server, '2');
    await alice.enable('alice-pw');
    await bob.enable('bob-pw');
    await bob.roomState(dm('42'), refresh: true); // 钉住 alice 的公钥
    final envelope = await alice.sealText(dm('42'), 'secret plan');

    Message.contentRevealer = bob.reveal;
    final message = incoming(id: '101', senderId: '1', envelope: envelope!);
    expect(message.content, 'secret plan');

    final cached = jsonEncode(message.toJson());
    expect(cached, isNot(contains('secret plan')));
    expect(
      Message.fromJson(jsonDecode(cached) as Map<String, dynamic>).content,
      'secret plan',
    );
  });

  test(
      'a message whose claimed sender or room differs from the envelope is rejected',
      () async {
    final alice = device(server, '1');
    final bob = device(server, '2');
    await alice.enable('alice-pw');
    await bob.enable('bob-pw');
    await bob.roomState(dm('42'), refresh: true);
    final envelope = await alice.sealText(dm('42'), 'from alice');

    // 先正常解开一次（结果会被缓存）。
    expect(
      bob
          .reveal(incoming(id: '101', senderId: '1', envelope: envelope!))
          .content,
      'from alice',
    );
    // 服务器把 alice 的消息说成是 bob 自己发的：不能沿用缓存里的结果。
    final relabelled = incoming(id: '102', senderId: '2', envelope: envelope);
    expect(bob.revealResult(relabelled).status, E2eeRevealStatus.failed);
    // 服务器把它挪到别的会话。
    final moved =
        incoming(id: '103', senderId: '1', envelope: envelope, roomId: '43');
    expect(bob.revealResult(moved).status, E2eeRevealStatus.failed);
  });

  test(
      'peer without keys: plaintext with a notice; needs-unlock blocks sending',
      () async {
    final alice = device(server, '1');
    await alice.enable('alice-pw');

    final peerOff = await alice.roomState(dm('42'), refresh: true);
    expect(peerOff.mode, E2eeRoomMode.peerOff);
    expect(peerOff.notice, contains('对方尚未启用'));
    expect(await alice.sealText(dm('42'), 'hello'), isNull);

    await device(server, '2').enable('bob-pw');
    final otherAliceDevice = device(server, '1');
    final locked = await otherAliceDevice.roomState(dm('42'), refresh: true);
    expect(locked.mode, E2eeRoomMode.needsUnlock);
    await expectLater(
      otherAliceDevice.sealText(dm('42'), 'must not leak'),
      throwsA(isA<E2eeSendBlockedException>()),
    );

    server.roomsWithBots.add('42');
    final withBot = await alice.roomState(dm('42'), refresh: true);
    expect(withBot.mode, E2eeRoomMode.hasBots);
    expect(await alice.sealText(dm('42'), 'bot can read this'), isNull);
  });

  test('turning encryption off keeps history readable and stops encrypting',
      () async {
    final alice = device(server, '1');
    final bob = device(server, '2');
    await alice.enable('alice-pw');
    await bob.enable('bob-pw');
    await bob.roomState(dm('42'), refresh: true);
    final envelope = await alice.sealText(dm('42'), 'before turning off');

    await alice.disable();
    expect(await alice.sealText(dm('42'), 'after'), isNull);
    expect(
      bob
          .reveal(incoming(id: '104', senderId: '1', envelope: envelope!))
          .content,
      'before turning off',
    );

    // 重新打开沿用原来的密钥。
    await alice.enable('alice-pw');
    expect(server.keys['1'], hasLength(1));
    expect(await alice.sealText(dm('42'), 'again'), isNotNull);
  });

  test('enabling with a mistyped password is refused', () async {
    final alice = device(server, '1');
    await expectLater(
      alice.enable('typo'),
      throwsA(isA<E2eeWrongPasswordException>()),
    );
    expect(server.keys['1'], isNull);
  });

  test(
      'password change re-wraps the key: new password unlocks, old one does not',
      () async {
    final alicePhone = device(server, '1');
    final bob = device(server, '2');
    await alicePhone.enable('alice-pw');
    await bob.enable('bob-pw');
    await alicePhone.roomState(dm('42'), refresh: true);
    final envelope = await alicePhone.sealText(dm('42'), 'old history');

    final extras =
        await alicePhone.passwordChangeExtras('alice-pw', 'alice-new');
    server.applyPasswordChange('1', extras);
    server.passwords['1'] = 'alice-new';

    final withOld = device(server, '1');
    expect(await withOld.unlockWithPassword('alice-pw'),
        E2eeUnlockResult.wrongPassword);

    final withNew = device(server, '1');
    expect(await withNew.unlockWithPassword('alice-new'),
        E2eeUnlockResult.unlocked);
    await withNew.roomState(dm('42'), refresh: true);
    expect(
      withNew
          .reveal(incoming(id: '105', senderId: '1', envelope: envelope!))
          .content,
      'old history',
    );
  });

  test(
      'a device that cannot unwrap the active key refuses to change the password',
      () async {
    final alice = device(server, '1');
    await alice.enable('alice-pw');
    final fresh = device(server, '1');
    await expectLater(
      fresh.passwordChangeExtras('wrong-old', 'new'),
      throwsA(isA<E2eeException>()),
    );
  });

  test(
      'after a password reset the old key is lost; resetting keys makes a new version',
      () async {
    final alice = device(server, '1');
    final bob = device(server, '2');
    await alice.enable('alice-pw');
    await bob.enable('bob-pw');
    await alice.roomState(dm('42'), refresh: true);
    final oldEnvelope = await alice.sealText(dm('42'), 'before reset');

    // 管理员把密码重置了：服务器上的私钥仍是用旧密码包的。
    server.passwords['1'] = 'reset-pw';
    final newDevice = device(server, '1');
    expect(await newDevice.unlockWithPassword('reset-pw'),
        E2eeUnlockResult.wrongPassword);

    await newDevice.resetKeys('reset-pw');
    expect(server.active['1'], 2);
    await newDevice.roomState(dm('42'), refresh: true);
    expect(
      newDevice
          .revealResult(
              incoming(id: '106', senderId: '1', envelope: oldEnvelope!))
          .status,
      E2eeRevealStatus.keyLost,
    );

    // bob 重新拉目录后给新版本加密，新设备能读。
    final bobState = await bob.roomState(dm('42'), refresh: true);
    expect(bobState.peerKeyVersion, 2);
    final fresh = await bob.sealText(dm('42'), 'after reset');
    expect(
      newDevice
          .reveal(incoming(id: '107', senderId: '2', envelope: fresh!))
          .content,
      'after reset',
    );
  });

  test('a public key swapped by the server after pinning is refused', () async {
    final alice = device(server, '1');
    final bob = device(server, '2');
    await alice.enable('alice-pw');
    await bob.enable('bob-pw');
    expect((await alice.roomState(dm('42'), refresh: true)).mode,
        E2eeRoomMode.active);

    final impostor = await E2eeCrypto.generateKeyPair(1);
    server.keys['2']!.first['publicKey'] = impostor.publicKeyBase64;
    final state = await alice.roomState(dm('42'), refresh: true);
    expect(state.mode, E2eeRoomMode.keyChanged);
    await expectLater(
      alice.sealText(dm('42'), 'to impostor'),
      throwsA(isA<E2eeSendBlockedException>()),
    );
  });

  test(
      'encrypted attachments: real type/name restored, bytes decrypt, cache keeps server shape',
      () async {
    final alice = device(server, '1');
    final bob = device(server, '2');
    await alice.enable('alice-pw');
    await bob.enable('bob-pw');
    await bob.roomState(dm('42'), refresh: true);

    final photo = Uint8List.fromList(List.generate(2048, (i) => i % 256));
    final sealed = await alice.sealFile(
      dm('42'),
      name: 'IMG_0001.jpg',
      mimeType: 'image/jpeg',
      kind: 'image',
      readBytes: () async => photo,
    );
    expect(sealed, isNotNull);

    final message = Message.fromJson({
      'id': '200',
      'content': kE2eeServerPlaceholder,
      'senderId': '1',
      'chatRoomId': '42',
      'type': 'FILE',
      'fileUrl': '/api/files/chat/abc.bin',
      'fileName': kE2eeServerAttachmentName,
      'fileType': 'application/octet-stream',
      'encryptedContent': sealed!.envelope,
      'encryptionVersion': kE2eeEncryptionVersion,
      'createdAt': '2026-09-24T10:00:00',
    });
    final revealed = bob.reveal(message);
    expect(revealed.type, MessageType.image);
    expect(revealed.fileName, 'IMG_0001.jpg');
    expect(revealed.previewImageUrl, '/api/files/chat/abc.bin');
    expect(await bob.openAttachment(revealed, sealed.ciphertext), photo);
    expect(
      await bob.openDownloadedFile(
          '/api/files/chat/abc.bin', sealed.ciphertext),
      photo,
    );
    // 本地缓存里仍是服务器的样子：解不开时不会把密文当图片渲染。
    expect(revealed.toJson()['type'], 'FILE');
    expect(revealed.toJson()['fileName'], kE2eeServerAttachmentName);
  });

  test(
      'ChatDataService uploads only ciphertext to encrypted DMs and decrypts downloads',
      () async {
    final alice = device(server, '1');
    final bob = device(server, '2');
    await alice.enable('alice-pw');
    await bob.enable('bob-pw');
    await bob.roomState(dm('42'), refresh: true);

    final contract = Uint8List.fromList(utf8.encode('甲方：……乙方：……' * 40));
    Map<String, String>? captured;
    PickedChatFile? uploaded;
    final aliceChat = ChatDataService(
      authenticatedRequest: (method, url, {headers, body}) async =>
          throw UnimplementedError(),
      multipartRequest: (url, {required fields, required file}) async {
        captured = Map.of(fields);
        uploaded = file;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'data': {
              'id': 300,
              'content': kE2eeServerPlaceholder,
              'senderId': 1,
              'chatRoomId': 42,
              'messageType': 'FILE',
              'fileUrl': '/api/files/chat/f.bin',
              'fileName': kE2eeServerAttachmentName,
              'fileType': 'application/octet-stream',
              'encryptedContent': captured!['encryptedContent'],
              'encryptionVersion': kE2eeEncryptionVersion,
              'createdAt': '2026-09-24T10:00:00',
            },
          })),
          200,
        );
      },
      encryptionService: alice,
    );

    Message.contentRevealer = alice.reveal;
    final sent = await aliceChat.sendFileMessage(
      '42',
      PickedChatFile(
        name: '合同.pdf',
        size: contract.length,
        mimeType: 'application/pdf',
        bytes: contract,
      ),
      chat: dm('42'),
    );

    expect(captured!['messageType'], 'FILE');
    expect(captured!['encryptionVersion'], '$kE2eeEncryptionVersion');
    expect(uploaded!.name, 'encrypted.bin');
    expect(uploaded!.mimeType, 'application/octet-stream');
    expect(uploaded!.bytes, isNot(contract));
    expect(utf8.decode(uploaded!.bytes!, allowMalformed: true),
        isNot(contains('甲方')));
    expect(sent.fileName, '合同.pdf',
        reason: 'sender sees the real name right away');
    Message.contentRevealer = null;

    final serverCopy = Message.fromJson({
      'id': '300',
      'content': kE2eeServerPlaceholder,
      'senderId': '1',
      'chatRoomId': '42',
      'type': 'FILE',
      'fileUrl': '/api/files/chat/f.bin',
      'fileName': kE2eeServerAttachmentName,
      'fileType': 'application/octet-stream',
      'encryptedContent': captured!['encryptedContent'],
      'encryptionVersion': kE2eeEncryptionVersion,
      'createdAt': '2026-09-24T10:00:00',
    });
    final bobChat = ChatDataService(
      authenticatedRequest: (method, url, {headers, body}) async =>
          http.Response.bytes(uploaded!.bytes!, 200),
      encryptionService: bob,
    );
    final downloaded = await bobChat.downloadFile(bob.reveal(serverCopy));
    expect(downloaded.name, '合同.pdf');
    expect(downloaded.mimeType, 'application/pdf');
    expect(downloaded.bytes, contract);

    // 群聊（或对方没开）照常明文上传。
    final plainFields = <String, String>{};
    final groupChat = ChatDataService(
      authenticatedRequest: (method, url, {headers, body}) async =>
          throw UnimplementedError(),
      multipartRequest: (url, {required fields, required file}) async {
        plainFields.addAll(fields);
        expect(file.name, 'notes.txt');
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'data': {
              'id': 301,
              'content': 'notes.txt',
              'senderId': 1,
              'chatRoomId': 7
            },
          })),
          200,
        );
      },
      encryptionService: alice,
    );
    await groupChat.sendFileMessage(
      '7',
      const PickedChatFile(name: 'notes.txt', size: 1, bytes: [1]),
      chat: Chat(
          id: '7', name: 'g', type: ChatType.group, createdAt: DateTime(2026)),
    );
    expect(plainFields.containsKey('encryptedContent'), isFalse);
  });
}
