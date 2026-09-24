import 'package:chat_app/services/desktop_notification_io.dart';
import 'package:chat_app/services/local_notifications_setup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    test('native ${platform.name} app can send system notifications', () {
      debugDefaultTargetPlatformOverride = platform;
      final backend = IoDesktopNotificationBackend();

      expect(backend.isSupported, isTrue);
      // 桌面端没有推送通道，停在聊天页里也要弹通知。
      expect(backend.notifiesWhileInsideChat, isTrue);
    });
  }

  test('mobile keeps notifications on the chat list only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final backend = IoDesktopNotificationBackend();

    expect(backend.isSupported, isTrue);
    expect(backend.notifiesWhileInsideChat, isFalse);
  });

  test('platforms the plugin cannot serve are reported unsupported', () {
    expect(LocalNotificationsSetup.supportsPlatform(TargetPlatform.fuchsia),
        isFalse);
  });

  test('every desktop platform has plugin initialization settings', () {
    const settings = LocalNotificationsSetup.initializationSettings;
    expect(settings.windows, isNotNull);
    expect(settings.linux, isNotNull);
    expect(settings.macOS, isNotNull);
  });
}
