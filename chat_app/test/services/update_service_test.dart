import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/services/update_service.dart';

void main() {
  group('UpdateService platform filtering', () {
    test('Android client accepts Android update', () {
      expect(
        UpdateService.shouldHandleUpdateForPlatform(
          'ANDROID',
          currentPlatform: 'ANDROID',
        ),
        isTrue,
      );
    });

    test('Android client ignores macOS update', () {
      expect(
        UpdateService.shouldHandleUpdateForPlatform(
          'MACOS',
          currentPlatform: 'ANDROID',
        ),
        isFalse,
      );
    });

    test('Web client can surface any client update for download smoke', () {
      expect(
        UpdateService.shouldHandleUpdateForPlatform(
          'ANDROID',
          currentPlatform: 'WEB',
        ),
        isTrue,
      );
    });

    test('WebSocket payload maps to update check model', () {
      final check = UpdateService.checkFromWebSocketPayload({
        'platform': 'ANDROID',
        'versionName': '1.1.0',
        'versionCode': '11000',
        'forceUpdate': false,
        'releaseNotes': 'Built from commit abc',
        'downloadUrl': '/api/v1/app/download/android/app.apk',
        'fileSize': '1234',
      });

      expect(check.updateAvailable, isTrue);
      expect(check.latestVersion, '1.1.0');
      expect(check.latestVersionCode, 11000);
      expect(check.fileSize, 1234);
    });
  });
}
