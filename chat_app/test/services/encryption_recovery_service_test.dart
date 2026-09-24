import 'package:chat_app/models/chat.dart';
import 'package:chat_app/models/message.dart';
import 'package:chat_app/services/encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_e2ee_server.dart';

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
}) {
  return Message.fromJson({
    'id': id,
    'content': kE2eeServerPlaceholder,
    'senderId': senderId,
    'chatRoomId': '42',
    'type': 'TEXT',
    'encryptedContent': envelope,
    'encryptionVersion': kE2eeEncryptionVersion,
    'createdAt': '2026-09-24T10:00:00',
  });
}

/// 恢复码：密码被管理员重置后，在一台全新的设备上用恢复码找回全部加密历史；
/// 恢复码从来不出现在发给服务器的任何请求里。
void main() {
  late FakeE2eeServer server;

  setUp(() {
    server = FakeE2eeServer()
      ..passwords['1'] = 'alice-pw'
      ..passwords['2'] = 'bob-pw'
      ..roomMembers['42'] = ['1', '2'];
  });

  tearDown(() => Message.contentRevealer = null);

  /// 请求日志里有没有这个恢复码（分组的、不分组的、只有数据部分的都算）。
  void expectNeverSent(E2eeRecoveryCode code) {
    for (final entry in server.requestLog) {
      final upper = entry.toUpperCase();
      expect(upper, isNot(contains(code.formatted)));
      expect(upper, isNot(contains(code.compact)));
      expect(upper, isNot(contains(code.data)));
    }
  }

  test(
      'after an admin password reset a fresh device restores history with the code',
      () async {
    final alicePhone = e2eeDevice(server, '1');
    final bob = e2eeDevice(server, '2');
    await alicePhone.enable('alice-pw');
    await bob.enable('bob-pw');
    expect((await alicePhone.accountStatus()).needsRecoveryCode, isTrue);

    final code = E2eeRecoveryCode.generate();
    await alicePhone.saveRecoveryCode(code);
    final status = await alicePhone.accountStatus();
    expect(status.recoveryConfigured, isTrue);
    expect(status.needsRecoveryCode, isFalse);
    final recoveryWrap = server.keys['1']![0]['recoveryWrappedPrivateKey'];
    expect(recoveryWrap, isNotNull);

    await alicePhone.roomState(dm('42'), refresh: true);
    final mine = await alicePhone.sealText(dm('42'), '密码重置之前的消息');
    await bob.roomState(dm('42'), refresh: true);
    final theirs = await bob.sealText(dm('42'), 'bob 在重置前发的');

    // 管理员重置密码：服务器上的密码包装还是用旧密码包的，新设备解不开。
    server.passwords['1'] = 'reset-pw';
    final laptop = e2eeDevice(server, '1');
    expect(await laptop.unlockWithPassword('reset-pw'),
        E2eeUnlockResult.wrongPassword);

    // 输错一个字：本地就发现，不碰服务器。
    final typo =
        code.compact.replaceRange(5, 6, code.compact[5] == 'A' ? 'B' : 'A');
    final before = server.requestLog.length;
    await expectLater(laptop.recoverWithCode(typo, password: 'reset-pw'),
        throwsA(isA<E2eeRecoveryCodeFormatException>()));
    expect(server.requestLog.length, before);
    // 格式对但不是这个账号的恢复码。
    await expectLater(
        laptop.recoverWithCode(E2eeRecoveryCode.generate().formatted,
            password: 'reset-pw'),
        throwsA(isA<E2eeWrongRecoveryCodeException>()));
    expect(laptop.hasUnlockedKeys, isFalse);

    // 小写、空格分组照样认。
    final result = await laptop.recoverWithCode(
        code.formatted.toLowerCase().replaceAll('-', ' '),
        password: 'reset-pw');
    expect(result, E2eeRecoveryResult.restored);
    await laptop.roomState(dm('42'), refresh: true);
    laptop.reveal(incoming(id: '1', senderId: '2', envelope: theirs!));
    await laptop.waitForPendingKeyFetches();
    expect(
        laptop
            .reveal(incoming(id: '1', senderId: '2', envelope: theirs))
            .content,
        'bob 在重置前发的');
    expect(
        laptop
            .reveal(incoming(id: '2', senderId: '1', envelope: mine!))
            .content,
        '密码重置之前的消息');

    // 密码包装已换成现在的密码：再来一台新设备，直接用现在的密码就能解锁。
    final tablet = e2eeDevice(server, '1');
    expect(
        await tablet.unlockWithPassword('reset-pw'), E2eeUnlockResult.unlocked);
    await tablet.roomState(dm('42'), refresh: true);
    await tablet.waitForPendingKeyFetches();
    expect(
        tablet.reveal(incoming(id: '2', senderId: '1', envelope: mine)).content,
        '密码重置之前的消息');
    // 恢复码包装原样保留，恢复码以后还能用。
    expect(server.keys['1']![0]['recoveryWrappedPrivateKey'], recoveryWrap);

    expectNeverSent(code);
  });

  test('the password re-wrap after recovery requires the current password',
      () async {
    final alice = e2eeDevice(server, '1');
    await alice.enable('alice-pw');
    final code = E2eeRecoveryCode.generate();
    await alice.saveRecoveryCode(code);
    server.passwords['1'] = 'reset-pw';
    final originalWrap = server.keys['1']![0]['wrappedPrivateKey'];

    final laptop = e2eeDevice(server, '1');
    await expectLater(
        laptop.recoverWithCode(code.formatted, password: 'typo-pw'),
        throwsA(isA<E2eeWrongPasswordException>()));
    // 恢复码对了：这台设备已经解锁，只是服务器上的密码包装没换。
    expect(laptop.hasUnlockedKeys, isTrue);
    expect(server.keys['1']![0]['wrappedPrivateKey'], originalWrap);

    await laptop.rewrapWithCurrentPassword('reset-pw');
    expect(server.keys['1']![0]['wrappedPrivateKey'], isNot(originalWrap));
    expect(await e2eeDevice(server, '1').unlockWithPassword('reset-pw'),
        E2eeUnlockResult.unlocked);
    expectNeverSent(code);
  });

  test(
      'reset to a legacy (plain-password) login: unlock locally, re-wrap on the next password change',
      () async {
    final alice = e2eeDevice(server, '1');
    await alice.enable('alice-pw');
    final code = E2eeRecoveryCode.generate();
    await alice.saveRecoveryCode(code);

    server
      ..passwords['1'] = 'temp-pw'
      ..legacyScheme.add('1');
    final laptop = e2eeDevice(server, '1');
    expect(await laptop.recoverWithCode(code.formatted, password: 'temp-pw'),
        E2eeRecoveryResult.restoredNeedsPasswordChange);
    expect(laptop.hasUnlockedKeys, isTrue);

    // 改密码时（旧密码解不开包装也没关系）用已解开的私钥带上新包装，其他设备随后可用新密码解锁。
    final extras = await laptop.passwordChangeExtras('temp-pw', 'brand-new-pw');
    expect(extras['e2eeKeyWraps'], hasLength(1));
    server
      ..applyPasswordChange('1', extras)
      ..passwords['1'] = 'brand-new-pw'
      ..legacyScheme.remove('1');
    expect(await e2eeDevice(server, '1').unlockWithPassword('brand-new-pw'),
        E2eeUnlockResult.unlocked);
    expectNeverSent(code);
  });

  test('regenerating the code invalidates the old one', () async {
    final alice = e2eeDevice(server, '1');
    await alice.enable('alice-pw');
    final oldCode = E2eeRecoveryCode.generate();
    await alice.saveRecoveryCode(oldCode);
    final newCode = E2eeRecoveryCode.generate();
    await alice.saveRecoveryCode(newCode);

    server.passwords['1'] = 'reset-pw';
    final laptop = e2eeDevice(server, '1');
    await expectLater(
        laptop.recoverWithCode(oldCode.formatted, password: 'reset-pw'),
        throwsA(isA<E2eeWrongRecoveryCodeException>()));
    expect(laptop.hasUnlockedKeys, isFalse);
    expect(
        await laptop.recoverWithCode(newCode.formatted, password: 'reset-pw'),
        E2eeRecoveryResult.restored);
    expectNeverSent(oldCode);
    expectNeverSent(newCode);
  });

  test(
      'a new key version needs a new code; the new code covers every unlocked version',
      () async {
    final alice = e2eeDevice(server, '1');
    await alice.enable('alice-pw');
    await alice.saveRecoveryCode(E2eeRecoveryCode.generate());

    // 另一台设备重置了密钥（例如老客户端）：新版本没有恢复码，设置页要提示。
    await e2eeDevice(server, '1').resetKeys('alice-pw');
    await alice.unlockWithPassword('alice-pw');
    final status = await alice.accountStatus();
    expect(status.activeKeyVersion, 2);
    expect(status.recoveryConfigured, isFalse);
    expect(status.needsRecoveryCode, isTrue);
    expect(status.hasRecoveryWraps, isTrue,
        reason: 'v1 still has the old wrap');

    final code = E2eeRecoveryCode.generate();
    await alice.saveRecoveryCode(code);
    expect(server.keys['1']!.map((k) => k['recoveryWrappedPrivateKey']),
        everyElement(isNotNull));

    server.passwords['1'] = 'reset-pw';
    final laptop = e2eeDevice(server, '1');
    await laptop.recoverWithCode(code.formatted, password: 'reset-pw');
    final restored = await laptop.accountStatus();
    expect(restored.unlockedOnDevice, isTrue);
    expectNeverSent(code);
  });

  test('setting a code needs the active key unlocked on this device', () async {
    await e2eeDevice(server, '1').enable('alice-pw');
    final locked = e2eeDevice(server, '1');
    await expectLater(locked.saveRecoveryCode(E2eeRecoveryCode.generate()),
        throwsA(isA<E2eeException>()));
    expect(server.keys['1']![0]['recoveryWrappedPrivateKey'], isNull);
  });
}
