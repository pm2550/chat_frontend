import 'dart:async';

import 'package:chat_app/models/app_version.dart';
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
}
