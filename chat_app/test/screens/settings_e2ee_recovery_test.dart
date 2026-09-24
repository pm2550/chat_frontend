import 'dart:convert';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/screens/settings/settings_screen.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/encryption_service.dart';
import 'package:chat_app/services/file_save_result.dart';
import 'package:chat_app/services/user_profile_service.dart';
import 'package:chat_app/widgets/e2ee_recovery_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_e2ee_server.dart';

/// 设置页的恢复码：没有恢复码时一直提示；生成的恢复码只显示一次，可复制、存文件、
/// 用自己的邮件应用发给自己（不经过服务器）；确认保存后才上传包装；
/// 密码被重置后可以从解锁失败或设置里"用恢复码找回"。
void main() {
  late FakeE2eeServer server;
  late List<Uri> launched;
  late List<({String name, String text, String? mimeType})> savedFiles;
  late List<String> copied;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = FakeE2eeServer()..passwords['user1'] = 'me-pw';
    launched = [];
    savedFiles = [];
    copied = [];
  });

  UserProfileService profileService() => UserProfileService(
        authService: AuthService(),
        authenticatedRequest: (method, url, {headers, body}) async {
          expect(url, ApiConstants.profileSettings);
          return http.Response(
            jsonEncode({'success': true, 'data': <String, dynamic>{}}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        },
      );

  E2eeRecoveryActions actions() => E2eeRecoveryActions(
        selfEmail: () => 'me@example.com',
        openUrl: (uri) async {
          launched.add(uri);
          return true;
        },
        saveFile: ({required bytes, required name, mimeType}) async {
          savedFiles
              .add((name: name, text: utf8.decode(bytes), mimeType: mimeType));
          return const FileSaveResult.saved(
              FileSaveDestination.browserDownloads);
        },
        copyText: (text) async => copied.add(text),
      );

  Future<void> pumpSettings(
      WidgetTester tester, EncryptionService service) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        profileService: profileService(),
        encryptionService: service,
        recoveryActions: actions(),
      ),
    ));
    await settle(tester);
  }

  String shownCode(WidgetTester tester) => tester
      .widget<SelectableText>(find.byKey(const ValueKey('e2ee-recovery-code')))
      .data!;

  void expectCodeNeverSent(String formatted) {
    final compact = formatted.replaceAll('-', '');
    for (final entry in server.requestLog) {
      expect(entry.toUpperCase(), isNot(contains(formatted)));
      expect(entry.toUpperCase(), isNot(contains(compact)));
      expect(entry.toUpperCase(), isNot(contains(compact.substring(0, 20))));
    }
  }

  testWidgets(
      'an enabled account without a code sees the banner and can set one up',
      (tester) async {
    await tester.runAsync(() => e2eeDevice(server, 'user1').enable('me-pw'));
    final me = e2eeDevice(server, 'user1');
    await tester.runAsync(() => me.unlockWithPassword('me-pw'));
    await pumpSettings(tester, me);

    expect(find.byKey(const ValueKey('settings-e2ee-recovery-banner')),
        findsOneWidget);
    expect(find.textContaining('还没有恢复码'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('settings-e2ee-recovery-setup')));
    await tester.pumpAndSettle();
    final code = shownCode(tester);
    expect(code,
        matches(RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){6}[0-9A-HJKMNP-TV-Z]{4}$')));
    expect(find.textContaining('登录密码和恢复码都丢了'), findsOneWidget);

    // 点对话框外面关不掉：必须确认保存或明确"稍后再说"。
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('e2ee-recovery-code')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-copy')));
    await tester.pumpAndSettle();
    expect(copied, [code]);

    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-save')));
    await tester.pumpAndSettle();
    expect(savedFiles, hasLength(1));
    expect(savedFiles.single.name, endsWith('.txt'));
    expect(savedFiles.single.mimeType, 'text/plain');
    expect(savedFiles.single.text, contains(code));

    // 发送到我的邮箱：收件人是自己的邮箱（可改），打开的是本机邮件应用的 mailto 链接。
    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-email')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey('e2ee-recovery-email-field')))
          .controller!
          .text,
      'me@example.com',
    );
    expect(find.textContaining('任何能读取这个邮箱的人'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-email-open')));
    await tester.pumpAndSettle();
    expect(launched, hasLength(1));
    expect(launched.single.scheme, 'mailto');
    expect(launched.single.path, 'me@example.com');
    final body = Uri.decodeComponent(RegExp(r'body=([^&]*)')
        .firstMatch(launched.single.toString())!
        .group(1)!);
    expect(body, contains(code));

    // 还没确认：服务器上什么都没有，"我已保存"不可点。
    expect(server.keys['user1']![0]['recoveryWrappedPrivateKey'], isNull);
    FilledButton done() => tester
        .widget<FilledButton>(find.byKey(const ValueKey('e2ee-recovery-done')));
    expect(done().onPressed, isNull);
    await tester.enterText(
        find.byKey(const ValueKey('e2ee-recovery-confirm-field')),
        code.substring(0, 4) == code.substring(code.length - 4)
            ? '0000'
            : code.substring(0, 4));
    await tester.pump();
    expect(done().onPressed, isNull);

    await tester.enterText(
        find.byKey(const ValueKey('e2ee-recovery-confirm-field')),
        code.substring(code.length - 4).toLowerCase());
    await tester.pump();
    expect(done().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-done')));
    await settle(tester);

    expect(find.byKey(const ValueKey('e2ee-recovery-code')), findsNothing);
    expect(server.keys['user1']![0]['recoveryWrappedPrivateKey'], isNotNull);
    expect(find.byKey(const ValueKey('settings-e2ee-recovery-banner')),
        findsNothing);
    expect(find.textContaining('已设置：忘记密码或密码被重置时'), findsOneWidget);
    expectCodeNeverSent(code);

    // 设置好的恢复码真的能用：换一台设备（密码被重置）找回。
    server.passwords['user1'] = 'reset-pw';
    final laptop = e2eeDevice(server, 'user1');
    await tester
        .runAsync(() => laptop.recoverWithCode(code, password: 'reset-pw'));
    expect(laptop.hasUnlockedKeys, isTrue);
  });

  testWidgets('"稍后再说" uploads nothing and keeps the banner', (tester) async {
    await tester.runAsync(() => e2eeDevice(server, 'user1').enable('me-pw'));
    final me = e2eeDevice(server, 'user1');
    await tester.runAsync(() => me.unlockWithPassword('me-pw'));
    await pumpSettings(tester, me);

    await tester
        .tap(find.byKey(const ValueKey('settings-e2ee-recovery-setup')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后再说'));
    await settle(tester);
    expect(server.keys['user1']![0]['recoveryWrappedPrivateKey'], isNull);
    expect(find.byKey(const ValueKey('settings-e2ee-recovery-banner')),
        findsOneWidget);
  });

  testWidgets(
      'turning encryption on for the first time asks for a recovery code',
      (tester) async {
    await pumpSettings(tester, e2eeDevice(server, 'user1'));

    await tester.tap(find.byKey(const ValueKey('settings-e2ee-switch')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('e2ee-password-field')), 'me-pw');
    await tester.tap(find.text('开启'));
    await settle(tester);

    expect(server.keys['user1'], hasLength(1));
    expect(find.text('保存你的恢复码'), findsOneWidget);
    final code = shownCode(tester);
    await tester.enterText(
        find.byKey(const ValueKey('e2ee-recovery-confirm-field')),
        code.substring(code.length - 4));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-done')));
    await settle(tester);
    expect(server.keys['user1']![0]['recoveryWrappedPrivateKey'], isNotNull);
    expectCodeNeverSent(code);
  });

  testWidgets(
      'after an admin reset, a failed unlock offers the recovery code and restores the key',
      (tester) async {
    final phone = e2eeDevice(server, 'user1');
    final code = E2eeRecoveryCode.generate();
    await tester.runAsync(() async {
      await phone.enable('me-pw');
      await phone.saveRecoveryCode(code);
    });
    server.passwords['user1'] = 'reset-pw';
    final oldPasswordWrap = server.keys['user1']![0]['wrappedPrivateKey'];

    final laptop = e2eeDevice(server, 'user1');
    await pumpSettings(tester, laptop);
    await tester.tap(find.widgetWithText(TextButton, '解锁'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('e2ee-password-field')), 'reset-pw');
    await tester.tap(find.widgetWithText(FilledButton, '解锁'));
    await settle(tester);

    expect(find.text('无法解开加密密钥'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('e2ee-unlock-use-recovery')));
    await tester.pumpAndSettle();
    // 刚输过的登录密码直接用，不用再问。
    expect(find.byKey(const ValueKey('e2ee-recovery-password-field')),
        findsNothing);

    // 格式不对：本地就提示，不碰服务器。
    await tester.enterText(
        find.byKey(const ValueKey('e2ee-recovery-input')), 'ABCD-EFGH');
    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-submit')));
    await settle(tester);
    expect(find.textContaining('恢复码应为 28 个字符'), findsOneWidget);

    // 格式对、不是自己的恢复码。
    await tester.enterText(find.byKey(const ValueKey('e2ee-recovery-input')),
        E2eeRecoveryCode.generate().formatted);
    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-submit')));
    await settle(tester);
    expect(find.textContaining('恢复码不正确'), findsOneWidget);
    expect(laptop.hasUnlockedKeys, isFalse);

    await tester.enterText(find.byKey(const ValueKey('e2ee-recovery-input')),
        code.formatted.toLowerCase());
    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-submit')));
    await settle(tester);

    expect(find.text('用恢复码找回'), findsWidgets); // 设置里的入口还在
    expect(find.byKey(const ValueKey('e2ee-recovery-input')), findsNothing);
    expect(laptop.hasUnlockedKeys, isTrue);
    expect(
        server.keys['user1']![0]['wrappedPrivateKey'], isNot(oldPasswordWrap));
    expect(find.textContaining('已开启：和同样开启的好友私聊时自动加密'), findsOneWidget);
    expectCodeNeverSent(code.formatted);

    // 其他新设备现在用重置后的密码就能解锁。
    final tablet = e2eeDevice(server, 'user1');
    expect(await tester.runAsync(() => tablet.unlockWithPassword('reset-pw')),
        E2eeUnlockResult.unlocked);
  });

  testWidgets('regenerating from settings makes the old code stop working',
      (tester) async {
    final me = e2eeDevice(server, 'user1');
    final oldCode = E2eeRecoveryCode.generate();
    await tester.runAsync(() async {
      await me.enable('me-pw');
      await me.saveRecoveryCode(oldCode);
    });
    await pumpSettings(tester, me);

    await tester
        .tap(find.byKey(const ValueKey('settings-e2ee-recovery-regenerate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('旧的恢复码立即失效'), findsOneWidget);
    final newCode = shownCode(tester);
    expect(newCode, isNot(oldCode.formatted));
    await tester.enterText(
        find.byKey(const ValueKey('e2ee-recovery-confirm-field')),
        newCode.substring(newCode.length - 4));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('e2ee-recovery-done')));
    await settle(tester);

    server.passwords['user1'] = 'reset-pw';
    final laptop = e2eeDevice(server, 'user1');
    await tester.runAsync(() async {
      await expectLater(
          laptop.recoverWithCode(oldCode.formatted, password: 'reset-pw'),
          throwsA(isA<E2eeWrongRecoveryCodeException>()));
      expect(await laptop.recoverWithCode(newCode, password: 'reset-pw'),
          E2eeRecoveryResult.restored);
    });
    expectCodeNeverSent(newCode);
  });
}

Future<void> settle(WidgetTester tester) async {
  // 包装私钥要跑 Argon2（在后台 isolate 里），给真实时间让它算完。
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  await tester.pumpAndSettle();
}
