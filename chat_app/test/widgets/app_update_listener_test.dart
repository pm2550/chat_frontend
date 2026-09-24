import 'dart:async';

import 'package:chat_app/models/app_version.dart';
import 'package:chat_app/widgets/update_dialog.dart';
import 'package:chat_app/widgets/app_update_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows update dialog for matching WebSocket update event',
      (tester) async {
    final events = StreamController<Map<String, dynamic>>();

    await tester.pumpWidget(MaterialApp(
      home: AppUpdateListener(
        updateEvents: events.stream,
        currentPlatform: 'ANDROID',
        child: const Scaffold(body: Text('home')),
      ),
    ));

    events.add({
      'type': 'app_update_available',
      'platform': 'ANDROID',
      'versionName': '1.1.0',
      'versionCode': 11000,
      'forceUpdate': false,
      'releaseNotes': 'new build',
      'downloadUrl': '/api/v1/app/download/android/app.apk',
      'fileSize': 1024,
    });
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('1.1.0'), findsOneWidget);
    expect(find.text('new build'), findsOneWidget);

    await events.close();
  });

  testWidgets('does not show update dialog for mismatched platform',
      (tester) async {
    final events = StreamController<Map<String, dynamic>>();

    await tester.pumpWidget(MaterialApp(
      home: AppUpdateListener(
        updateEvents: events.stream,
        currentPlatform: 'ANDROID',
        child: const Scaffold(body: Text('home')),
      ),
    ));

    events.add({
      'type': 'app_update_available',
      'platform': 'MACOS',
      'versionName': '1.1.0',
      'versionCode': 11000,
    });
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsNothing);

    await events.close();
  });

  testWidgets('can inject custom presenter for WebSocket update event',
      (tester) async {
    final events = StreamController<Map<String, dynamic>>();
    AppVersionCheck? shown;

    await tester.pumpWidget(MaterialApp(
      home: AppUpdateListener(
        updateEvents: events.stream,
        currentPlatform: 'ANDROID',
        showUpdate: (context, check) async {
          shown = check;
        },
        child: const Scaffold(body: Text('home')),
      ),
    ));

    events.add({
      'type': 'app_update_available',
      'platform': 'ANDROID',
      'versionName': '1.1.0',
      'versionCode': 11000,
    });
    await tester.pumpAndSettle();

    expect(shown?.latestVersion, '1.1.0');
    expect(shown?.latestVersionCode, 11000);

    await events.close();
  });

  testWidgets('web client does not prompt for an Android release',
      (tester) async {
    final events = StreamController<Map<String, dynamic>>();
    AppVersionCheck? shown;

    await tester.pumpWidget(MaterialApp(
      home: AppUpdateListener(
        updateEvents: events.stream,
        currentPlatform: 'WEB',
        showUpdate: (context, check) async {
          shown = check;
        },
        child: const Scaffold(body: Text('home')),
      ),
    ));

    events.add({
      'type': 'app_update_available',
      'platform': 'ANDROID',
      'versionName': '1.1.0',
      'versionCode': 11000,
      'downloadUrl': '/api/v1/app/download/android/app.apk',
    });
    await tester.pumpAndSettle();
    expect(shown, isNull);

    events.add({
      'type': 'app_update_available',
      'platform': 'WEB',
      'versionName': '1.1.1',
      'versionCode': 11001,
    });
    await tester.pumpAndSettle();
    expect(shown?.latestVersion, '1.1.1');

    await events.close();
  });

  testWidgets('web update dialog reloads the page instead of downloading',
      (tester) async {
    var reloads = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpdateDialog(
          isWeb: true,
          onReloadWeb: () => reloads += 1,
          versionCheck: const AppVersionCheck(
            updateAvailable: true,
            forceUpdate: false,
            latestVersion: '1.1.1',
          ),
        ),
      ),
    ));

    await tester.tap(find.text('立即更新'));
    await tester.pump();

    expect(reloads, 1);
    expect(find.textContaining('下载中'), findsNothing);
  });
}
