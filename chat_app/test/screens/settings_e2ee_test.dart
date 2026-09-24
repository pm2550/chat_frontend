import 'dart:convert';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/screens/settings/settings_screen.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/user_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_e2ee_server.dart';

/// 设置里的端到端加密开关是真的：开 = 输密码生成（或解锁）密钥，关 = 只是新消息不再加密。
void main() {
  late FakeE2eeServer server;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = FakeE2eeServer()..passwords['user1'] = 'me-pw';
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

  Future<void> settle(WidgetTester tester) async {
    // 包装私钥要跑 Argon2（在后台 isolate 里），给真实时间让它算完。
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'turning the switch on asks for the password and really creates keys',
      (tester) async {
    final me = e2eeDevice(server, 'user1');
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
          profileService: profileService(), encryptionService: me),
    ));
    await settle(tester);
    expect(find.text('开启后，和同样开启的好友私聊会自动加密'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-e2ee-switch')));
    await tester.pumpAndSettle();
    expect(find.text('开启端到端加密'), findsOneWidget);
    expect(find.textContaining('之前的加密聊天记录将永久无法解密'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('e2ee-password-field')), 'me-pw');
    await tester.tap(find.text('开启'));
    await settle(tester);

    // 新生成的密钥马上请用户保存恢复码（详见 settings_e2ee_recovery_test.dart），这里先跳过。
    expect(find.text('保存你的恢复码'), findsOneWidget);
    await tester.tap(find.text('稍后再说'));
    await settle(tester);

    expect(server.keys['user1'], hasLength(1));
    expect(server.enabled['user1'], isTrue);
    expect(find.textContaining('已开启：和同样开启的好友私聊时自动加密'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('settings-e2ee-switch')))
          .value,
      isTrue,
    );

    // 关：确认后只关掉"新消息加密"，密钥还在。
    await tester.tap(find.byKey(const ValueKey('settings-e2ee-switch')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已经加密的聊天记录仍可在已登录的设备上查看'), findsOneWidget);
    await tester.tap(find.text('关闭加密'));
    await settle(tester);

    expect(server.enabled['user1'], isFalse);
    expect(server.keys['user1'], hasLength(1));
    expect(find.text('已关闭：新消息不再加密，已加密的记录仍可查看'), findsOneWidget);

    // 再打开：沿用原来的密钥，这台设备已解锁，不用再输密码。
    await tester.tap(find.byKey(const ValueKey('settings-e2ee-switch')));
    await settle(tester);
    expect(find.byKey(const ValueKey('e2ee-password-field')), findsNothing);
    expect(server.enabled['user1'], isTrue);
    expect(server.keys['user1'], hasLength(1));
  });

  testWidgets('a device that has not unlocked the key offers to unlock it',
      (tester) async {
    await tester.runAsync(() => e2eeDevice(server, 'user1').enable('me-pw'));
    final laptop = e2eeDevice(server, 'user1');

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
          profileService: profileService(), encryptionService: laptop),
    ));
    await settle(tester);

    expect(find.text('已开启，但这台设备尚未解锁，点"解锁"输入登录密码'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '解锁'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('e2ee-password-field')), 'me-pw');
    await tester.tap(find.widgetWithText(FilledButton, '解锁'));
    await settle(tester);

    expect(laptop.hasUnlockedKeys, isTrue);
    expect(find.textContaining('已开启：和同样开启的好友私聊时自动加密'), findsOneWidget);
  });
}
