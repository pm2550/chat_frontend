import 'package:chat_app/screens/downloads/downloads_screen.dart';
import 'package:chat_app/services/download_catalog_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all supported Flutter client targets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/login': (context) => const _LoginPlaceholder(),
        },
        home: const DownloadsScreen(
            downloadService: _FakeDownloadCatalogService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PM chat 客户端下载'), findsOneWidget);
    expect(find.text('网页版 / PWA'), findsWidgets);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('iPhone / iPad'), findsOneWidget);
    expect(find.text('Windows'), findsWidgets);
    expect(find.text('macOS'), findsWidgets);
    expect(find.text('Linux'), findsOneWidget);
  });

  testWidgets('falls back to web when detected platform has no package',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/login': (context) => const _LoginPlaceholder(),
        },
        home: const DownloadsScreen(
          downloadService: _UnavailableWindowsDownloadCatalogService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('推荐入口'), findsOneWidget);
    expect(find.text('打开网页版'), findsOneWidget);
    expect(find.text('下载 Windows 版'), findsNothing);
  });

  testWidgets('downloads a native client without navigating the app',
      (tester) async {
    String? openedUrl;
    String? openedFilename;
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/login': (context) => const _LoginPlaceholder(),
        },
        home: DownloadsScreen(
          downloadService: const _FakeDownloadCatalogService(),
          downloadOpener: (url, filename) async {
            openedUrl = url;
            openedFilename = filename;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('下载 Windows 版').first);
    await tester.pump();

    expect(
      openedUrl,
      'https://gateway.chat.pm2550.com/download/windows/pm-chat',
    );
    expect(openedFilename, 'pm-chat');
    expect(find.text('Login'), findsNothing);
  });

  testWidgets('Android card offers a separate 32-bit link for old phones',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/login': (context) => const _LoginPlaceholder(),
        },
        home: DownloadsScreen(
          downloadService: const _SplitAndroidDownloadCatalogService(),
          downloadOpener: (url, filename) async {
            opened.add(filename);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 推荐卡片（本设备按 Android 算）：主按钮 64 位，旁边一个 32 位小链接。
    expect(find.text('下载 Android（推荐，64 位）'), findsOneWidget);
    expect(find.text('32 位旧手机'), findsWidgets);

    await tester.tap(find.text('下载 Android（推荐，64 位）'));
    await tester.pump();
    await tester.tap(find.text('32 位旧手机').first);
    await tester.pump();

    expect(opened, [
      'pm-chat-android-arm64-v8a-v1.1.52-11052.apk',
      'pm-chat-android-armeabi-v7a-v1.1.52-11052.apk',
    ]);
  });

  testWidgets('the 32-bit link fits on a phone-width download page',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/login': (context) => const _LoginPlaceholder(),
        },
        home: const DownloadsScreen(
          downloadService: _SplitAndroidDownloadCatalogService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('下载 Android（推荐，64 位）'), findsOneWidget);
    expect(find.text('32 位旧手机'), findsWidgets);
  });

  _iosInstructionsTest();
}


void _iosInstructionsTest() {
  testWidgets('iPhone card explains Add to Home Screen instead of an .ipa',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? openedDownload;
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/login': (context) => const _LoginPlaceholder(),
        },
        home: DownloadsScreen(
          downloadService: const DownloadCatalogService(),
          downloadOpener: (url, filename) async {
            openedDownload = url;
            return true;
          },
          linkOpener: (url) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('网页版 · 添加到主屏幕'), findsOneWidget);
    await tester.tap(find.byTooltip('在 iPhone 上使用'));
    await tester.pumpAndSettle();

    expect(find.text('在 iPhone / iPad 上使用'), findsOneWidget);
    expect(find.textContaining('添加到主屏幕'), findsWidgets);
    expect(openedDownload, isNull);
  });
}

class _LoginPlaceholder extends StatelessWidget {
  const _LoginPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('Login'));
  }
}

class _FakeDownloadCatalogService extends DownloadCatalogService {
  const _FakeDownloadCatalogService();

  @override
  Future<List<ClientDownloadStatus>> fetchCatalog() async {
    return DownloadCatalogService.defaultTargets
        .map((target) => ClientDownloadStatus(
              target: target,
              latestVersion: target.isWeb ? null : '1.0.0',
              downloadUrl: target.isWeb
                  ? 'https://gateway.chat.pm2550.com'
                  : '/api/v1/app/download/${target.apiPlatform.toLowerCase()}/pm-chat',
              fileSize: target.isWeb ? null : 1024 * 1024,
            ))
        .toList(growable: false);
  }

  @override
  ClientDownloadTarget recommendedTarget({TargetPlatform? platform}) {
    return DownloadCatalogService.defaultTargets.firstWhere(
      (target) => target.platform == ClientDownloadPlatform.windows,
    );
  }
}

class _UnavailableWindowsDownloadCatalogService extends DownloadCatalogService {
  const _UnavailableWindowsDownloadCatalogService();

  @override
  Future<List<ClientDownloadStatus>> fetchCatalog() async {
    return DownloadCatalogService.defaultTargets
        .map((target) => ClientDownloadStatus(
              target: target,
              downloadUrl:
                  target.isWeb ? 'https://gateway.chat.pm2550.com' : null,
            ))
        .toList(growable: false);
  }

  @override
  ClientDownloadTarget recommendedTarget({TargetPlatform? platform}) {
    return DownloadCatalogService.defaultTargets.firstWhere(
      (target) => target.platform == ClientDownloadPlatform.windows,
    );
  }
}

class _SplitAndroidDownloadCatalogService extends DownloadCatalogService {
  const _SplitAndroidDownloadCatalogService();

  static ClientDownloadStatus _android(ClientDownloadTarget target) =>
      ClientDownloadStatus(
        target: target,
        latestVersion: '1.1.52',
        downloadUrl:
            '/api/v1/app/download/android/pm-chat-android-${target.abi}-v1.1.52-11052.apk',
        fileSize: 50 * 1024 * 1024,
      );

  @override
  Future<List<ClientDownloadStatus>> fetchCatalog() async {
    return DownloadCatalogService.defaultTargets.map((target) {
      if (target.platform == ClientDownloadPlatform.android) {
        return _android(target).withSecondary(_android(target.secondary!));
      }
      return ClientDownloadStatus(
        target: target,
        downloadUrl: target.isWeb ? 'https://gateway.chat.pm2550.com' : null,
      );
    }).toList(growable: false);
  }

  @override
  ClientDownloadTarget recommendedTarget({TargetPlatform? platform}) {
    return DownloadCatalogService.defaultTargets.firstWhere(
      (target) => target.platform == ClientDownloadPlatform.android,
    );
  }
}
