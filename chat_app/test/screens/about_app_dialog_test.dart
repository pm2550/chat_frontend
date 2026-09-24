import 'package:chat_app/models/user.dart';
import 'package:chat_app/screens/home/profile_page.dart';
import 'package:chat_app/screens/profile/about_app_dialog.dart';
import 'package:chat_app/services/user_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'PM chat',
      packageName: 'com.pm2550.chat',
      version: '1.1.47',
      buildNumber: '11047',
      buildSignature: '',
    );
  });

  testWidgets('profile 关于 opens a real About dialog with the app version',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: ProfilePage(profileService: _FakeProfileService()),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('关于'), 200);
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutAppDialog), findsOneWidget);
    expect(find.text('1.1.47（构建 11047）'), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
    expect(find.text('下载客户端'), findsOneWidget);
    // The old implementation only flashed a snackbar with the app name.
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutAppDialog), findsNothing);
  });

  testWidgets('shows the build commit when one was injected', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAboutAppDialog(
            context,
            buildCommit: '9ed99d4abcdef0123456',
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('提交'), findsOneWidget);
    expect(find.text('9ed99d4abcde'), findsOneWidget);
  });

  testWidgets('下载客户端 navigates to the downloads page', (tester) async {
    await tester.pumpWidget(MaterialApp(
      routes: {
        '/downloads': (_) => const Scaffold(body: Text('downloads-page')),
      },
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAboutAppDialog(context),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载客户端'));
    await tester.pumpAndSettle();

    expect(find.text('downloads-page'), findsOneWidget);
  });
}

class _FakeProfileService extends UserProfileService {
  _FakeProfileService() : super(authenticatedRequest: _unusedRequest);

  static Future<http.Response> _unusedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User> getProfile() async => User(
        id: '1',
        username: 'me',
        email: 'me@example.com',
        displayName: '我',
        createdAt: DateTime(2026, 1, 1),
      );
}
