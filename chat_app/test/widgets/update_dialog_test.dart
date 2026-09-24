import 'package:chat_app/models/app_version.dart';
import 'package:chat_app/widgets/update_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(AppVersionCheck check) => MaterialApp(
        home: Scaffold(body: UpdateDialog(versionCheck: check)),
      );

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iPhone is pointed at the web app instead of an .ipa download',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(host(const AppVersionCheck(
      updateAvailable: true,
      latestVersion: '1.2.0',
      downloadUrl: '/api/v1/app/download/ios/pm-chat-ios-v1.2.0.ipa',
      fileSize: 1024 * 1024,
    )));

    expect(find.text('打开网页版'), findsOneWidget);
    expect(find.textContaining('添加到主屏幕'), findsOneWidget);
    expect(find.textContaining('大小'), findsNothing);
    expect(find.text('立即更新'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS offers to download into Downloads, not /Applications',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(host(const AppVersionCheck(
      updateAvailable: true,
      latestVersion: '1.2.0',
      downloadUrl: '/api/v1/app/download/macos/pm-chat-macos-v1.2.0.zip',
    )));

    expect(find.text('下载新版本'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Linux and Windows update in place', (tester) async {
    for (final entry in {
      TargetPlatform.linux: 'pm-chat-linux-x64-v1.2.0.tar.gz',
      TargetPlatform.windows: 'pm-chat-windows-x64-v1.2.0.zip',
    }.entries) {
      debugDefaultTargetPlatformOverride = entry.key;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host(AppVersionCheck(
        updateAvailable: true,
        latestVersion: '1.2.0',
        downloadUrl: '/api/v1/app/download/x/${entry.value}',
      )));
      expect(find.text('立即更新'), findsOneWidget, reason: '${entry.key}');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a package for another platform only offers the download page',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(host(const AppVersionCheck(
      updateAvailable: true,
      latestVersion: '1.2.0',
      downloadUrl: '/api/v1/app/download/linux/pm-chat-linux.zip',
    )));

    expect(find.text('打开下载页'), findsOneWidget);
    expect(find.text('立即更新'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
