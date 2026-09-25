import 'dart:async';
import 'dart:convert';

import 'package:chat_app/services/download_catalog_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('DownloadCatalogService', () {
    test('detects current platform recommendation', () {
      const service = DownloadCatalogService();

      expect(
        service.recommendedTarget(platform: TargetPlatform.android).apiPlatform,
        'ANDROID',
      );
      expect(
        service.recommendedTarget(platform: TargetPlatform.iOS).apiPlatform,
        'IOS',
      );
      expect(
        service.recommendedTarget(platform: TargetPlatform.windows).apiPlatform,
        'WINDOWS',
      );
      expect(
        service.recommendedTarget(platform: TargetPlatform.macOS).apiPlatform,
        'MACOS',
      );
      expect(
        service.recommendedTarget(platform: TargetPlatform.linux).apiPlatform,
        'LINUX',
      );
    });

    test('lists all Flutter build targets plus web', () {
      const service = DownloadCatalogService();

      expect(
        service.targets.map((target) => target.apiPlatform),
        containsAll(['WEB', 'ANDROID', 'IOS', 'WINDOWS', 'MACOS', 'LINUX']),
      );
    });

    test('fetchCatalog requests native platform statuses concurrently',
        () async {
      final requests = <String>[];
      final responses = <Completer<http.Response>>[];
      final client = _FakeClient((request) {
        requests.add(request.url.queryParameters['platform']!);
        final response = Completer<http.Response>();
        responses.add(response);
        return response.future;
      });
      final service = DownloadCatalogService(client: client);

      final catalog = service.fetchCatalog();
      await Future<void>.delayed(Duration.zero);

      // iOS 是链接型通道（.ipa 在浏览器里装不上），不查发布包。
      // Android 查两次：64 位主包 + 32 位旧手机包。
      expect(requests, containsAll(['ANDROID', 'WINDOWS', 'MACOS', 'LINUX']));
      expect(requests, isNot(contains('IOS')));
      expect(requests.where((p) => p == 'ANDROID'), hasLength(2));
      expect(requests, hasLength(5));
      for (final response in responses) {
        response.complete(http.Response(
          jsonEncode({'updateAvailable': false}),
          200,
        ));
      }
      expect(await catalog, hasLength(6));
    });

    test('iPhone channel is honest when no TestFlight link is configured',
        () async {
      final client = _FakeClient((request) async {
        fail('iOS must not look up a published .ipa');
      });
      final service = DownloadCatalogService(client: client);
      final ios = service.recommendedTarget(platform: TargetPlatform.iOS);

      expect(ios.packageLabel, isNot(contains('TestFlight')));
      expect(ios.packageLabel, isNot(contains('App Store')));
      expect(ios.showsPwaInstructions, isTrue);
      final status = await service.fetchStatus(ios);
      expect(status.isAvailable, isTrue);
      expect(status.downloadUrl, isNot(endsWith('.ipa')));
    });

    test('a configured TestFlight link is used as the iPhone channel', () {
      const target = DownloadCatalogService.iosTestFlightTarget;
      expect(target.packageLabel, 'TestFlight');
      expect(target.showsPwaInstructions, isFalse);
    });

    test('desktop package labels match what CI actually publishes', () {
      const service = DownloadCatalogService();
      String label(TargetPlatform platform) =>
          service.recommendedTarget(platform: platform).packageLabel;
      expect(label(TargetPlatform.windows), isNot(contains('.exe')));
      expect(label(TargetPlatform.macOS), isNot(contains('.dmg')));
      expect(label(TargetPlatform.linux), isNot(contains('AppImage')));
    });

    test('fetchStatus reads public app version endpoint', () async {
      final client = _FakeClient((request) async {
        expect(request.url.path, '/api/v1/app/version');
        expect(request.url.queryParameters['platform'], 'ANDROID');
        expect(request.url.queryParameters['currentVersionCode'], '0');
        return http.Response(
          jsonEncode({
            'updateAvailable': true,
            'latestVersion': '1.2.3',
            'latestVersionCode': 12,
            'downloadUrl': '/api/v1/app/download/android/pm-chat.apk',
            'fileSize': 42,
          }),
          200,
        );
      });
      final service = DownloadCatalogService(client: client);
      final target = service.targets.firstWhere(
        (target) => target.platform == ClientDownloadPlatform.android,
      );

      final status = await service.fetchStatus(target);

      expect(status.latestVersion, '1.2.3');
      expect(status.downloadUrl, '/api/v1/app/download/android/pm-chat.apk');
      expect(status.fileSize, 42);
      expect(status.isAvailable, isTrue);
    });

    test('Android offers the 64-bit APK first and the 32-bit APK as a link',
        () async {
      final requestedAbis = <String?>[];
      final client = _FakeClient((request) async {
        final abi = request.url.queryParameters['abi'];
        requestedAbis.add(abi);
        return http.Response(
          jsonEncode({
            'updateAvailable': true,
            'latestVersion': '1.1.52',
            'downloadUrl':
                '/api/v1/app/download/android/pm-chat-android-$abi-v1.1.52-11052.apk',
            'fileSize': abi == 'arm64-v8a' ? 52000000 : 47000000,
            'abi': abi,
          }),
          200,
        );
      });
      final service = DownloadCatalogService(client: client);
      final android =
          service.recommendedTarget(platform: TargetPlatform.android);

      final status = await service.fetchStatus(android);

      expect(requestedAbis, unorderedEquals(['arm64-v8a', 'armeabi-v7a']));
      expect(android.primaryAction, contains('推荐，64 位'));
      expect(status.downloadUrl, contains('arm64-v8a'));
      expect(status.fileSize, 52000000);
      expect(status.secondary, isNotNull);
      expect(status.secondary!.target.primaryAction, '32 位旧手机');
      expect(status.secondary!.downloadUrl, contains('armeabi-v7a'));
      expect(status.secondary!.fileSize, 47000000);
    });

    test('a pre-split universal APK is not listed twice', () async {
      final client = _FakeClient((request) async => http.Response(
            jsonEncode({
              'updateAvailable': true,
              'latestVersion': '1.1.51',
              'downloadUrl':
                  '/api/v1/app/download/android/pm-chat-android-v1.1.51-11051.apk',
              'fileSize': 102375315,
            }),
            200,
          ));
      final service = DownloadCatalogService(client: client);

      final status = await service.fetchStatus(
        service.recommendedTarget(platform: TargetPlatform.android),
      );

      expect(status.hasDownloadUrl, isTrue);
      expect(status.secondary, isNull);
    });

    test('resolves compatibility download route to final static artifact', () {
      const service = DownloadCatalogService();

      expect(
        service.resolveDownloadUrl(
          '/api/v1/app/download/android/pm-chat-android.apk',
        ),
        'https://gateway.chat.pm2550.com/download/android/pm-chat-android.apk',
      );
      expect(
        service.resolveDownloadUrl('https://releases.example/pm-chat.zip'),
        'https://releases.example/pm-chat.zip',
      );
    });
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}
