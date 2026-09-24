import 'dart:convert';

import 'package:chat_app/constants/api_constants.dart';
import 'package:chat_app/screens/settings/settings_screen.dart';
import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/user_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  UserProfileService profileServiceReturning(Map<String, dynamic> settings) {
    return UserProfileService(
      authService: AuthService(),
      authenticatedRequest: (method, url, {headers, body}) async {
        expect(url, ApiConstants.profileSettings);
        return http.Response(
          jsonEncode({'success': true, 'data': settings}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      },
    );
  }

  testWidgets('settings list has no fake burn-after-reading row',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(profileService: profileServiceReturning({})),
    ));
    await tester.pumpAndSettle();

    expect(find.text('阅后即焚默认时间'), findsNothing);
    expect(find.text('显示在线状态'), findsWidgets);
    expect(find.text(SettingsCopy.messageNotifications), findsOneWidget);
  });

  testWidgets('desktop policy panel shows real online-status state',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        profileService: profileServiceReturning({'showOnlineStatus': false}),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('已连接后端设置'), findsNothing);
    expect(find.text('在线状态'), findsOneWidget);
    expect(find.text('已隐藏'), findsOneWidget);
  });

  testWidgets('privacy screen explains what each switch actually does',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PrivacySettingsScreen(
        initialSettings: const UserAppSettings(),
        profileService: profileServiceReturning({}),
      ),
    ));

    expect(find.text(SettingsCopy.showOnlineStatus), findsOneWidget);
    expect(find.text(SettingsCopy.allowFriendRequests), findsOneWidget);
    expect(find.text(SettingsCopy.allowDirectMessages), findsOneWidget);
  });
}
