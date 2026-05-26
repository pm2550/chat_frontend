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
