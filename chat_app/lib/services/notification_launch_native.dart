import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_notifications_setup.dart';
import 'notification_tap_router.dart';

/// 原生端：注册通知点击回调，并处理"点通知冷启动 App"的情况。
Future<void> initNotificationLaunchRouting(
  GlobalKey<NavigatorState> navigatorKey,
) async {
  NotificationTapRouter.attach(navigatorKey);
  if (!LocalNotificationsSetup.supportsPlatform(defaultTargetPlatform)) return;
  try {
    if (!await LocalNotificationsSetup.ensureInitialized()) return;
    final launch = await FlutterLocalNotificationsPlugin()
        .getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      NotificationTapRouter.handlePayload(launch?.notificationResponse?.payload);
    }
  } catch (_) {
    // 通知跳转是锦上添花，初始化失败不能影响启动。
  }
}

void flushPendingNotificationRoute() => NotificationTapRouter.flushPending();
