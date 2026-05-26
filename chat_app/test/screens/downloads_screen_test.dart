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
