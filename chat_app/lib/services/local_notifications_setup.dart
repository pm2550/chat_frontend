import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_tap_router.dart';

/// flutter_local_notifications 在本进程里只初始化一次。
///
/// 插件是单例：点通知的回调只认最后一次 initialize 传进去的那个；Windows 上
/// 每次 initialize 还会重写注册表并重新注册 COM 激活器。所以启动时的"点通知
/// 冷启动跳转"和聊天列表的消息通知必须共用同一次初始化。
class LocalNotificationsSetup {
  LocalNotificationsSetup._();

  static const String windowsAppUserModelId = 'PM2550.PMChat.Desktop';

  /// Windows 点通知时用来激活本应用的 COM 类 ID，发布后不能再改，
  /// 否则老版本在系统里留下的通知点了没反应。
  static const String windowsActivatorGuid =
      'b7c9e0b4-5d3a-4f8e-9c61-2a7d4e8f1c35';

  static Future<bool>? _initialization;

  /// 当前平台的 flutter_local_notifications 能不能发系统通知。
  ///
  /// 19.x 起插件覆盖 Android / iOS / macOS / Linux / Windows。
  static bool supportsPlatform(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows =>
        true,
      TargetPlatform.fuchsia => false,
    };
  }

  static bool isDesktop(TargetPlatform platform) {
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.windows;
  }

  static const InitializationSettings initializationSettings =
      InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
    // macOS 上不在初始化时弹授权框，等 requestPermissions 再问。
    macOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
    linux: LinuxInitializationSettings(defaultActionName: '打开'),
    windows: WindowsInitializationSettings(
      appName: 'PM chat',
      appUserModelId: windowsAppUserModelId,
      guid: windowsActivatorGuid,
    ),
  );

  /// 初始化插件并注册点通知的跳转；失败返回 false（比如 Linux 没有通知服务）。
  static Future<bool> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  static Future<bool> _initialize() async {
    try {
      final result = await FlutterLocalNotificationsPlugin().initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: NotificationTapRouter.handleResponse,
      );
      return result ?? true;
    } catch (error) {
      debugPrint('Local notifications unavailable: $error');
      // 允许下次再试（比如 Linux 通知服务稍后才起来）。
      _initialization = null;
      return false;
    }
  }
}
