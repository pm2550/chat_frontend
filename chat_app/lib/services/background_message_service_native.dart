import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import 'auth_service.dart';
import 'background_message_client.dart';
import 'websocket_service.dart';

/// Android 后台保持连接（方案 A：前台常驻服务）。
///
/// 国内手机没有 Google 推送，App 一进后台就会被系统冻结或杀掉。这里用一个带常驻
/// 通知的前台服务把进程保住，服务里单独维持一条"后台连接"：服务器判断该推送时，
/// 把现成的通知（标题/正文已按免打扰、@提醒算好）从这条连接下发，服务负责弹出来。
class BackgroundMessageService {
  BackgroundMessageService._();

  static const int _serviceId = 7101;
  static const String _batteryPromptKey = 'pmchat.background.batteryPromptShown';
  static bool _authListenerAttached = false;

  static bool get isSupported => Platform.isAndroid;

  /// 登录后调用：申请通知权限、（只问一次）申请忽略电池优化，然后启动服务。
  static Future<void> ensureStarted() async {
    if (!isSupported) return;
    try {
      _initOptions();
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      await _askBatteryOptimizationOnce();
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          serviceId: _serviceId,
          serviceTypes: const [ForegroundServiceTypes.remoteMessaging],
          notificationTitle: 'PM chat 正在后台运行',
          notificationText: '保持连接，及时收到新消息和来电',
          callback: pmchatBackgroundTaskStart,
        );
      }
      // 服务接管后台通知：App 切到后台时前台连接可以放心断开，服务器立刻改走后台连接。
      WebSocketService().enableNativeBackgroundHandoff();
      _attachAuthListener();
    } catch (error) {
      debugPrint('Background message service unavailable: $error');
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (error) {
      debugPrint('Background message service stop failed: $error');
    }
  }

  static void _initOptions() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'pm_chat_background',
        channelName: '后台保持连接',
        channelDescription: '让 PM chat 在后台也能收到消息和来电',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 每 5 分钟检查一次连接，断了就催一次重连。
        eventAction: ForegroundTaskEventAction.repeat(5 * 60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> _askBatteryOptimizationOnce() async {
    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_batteryPromptKey) ?? false) return;
    await prefs.setBool(_batteryPromptKey, true);
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  static void _attachAuthListener() {
    if (_authListenerAttached) return;
    _authListenerAttached = true;
    final auth = AuthService();
    auth.addListener(() {
      // 退出登录或会话失效时停掉服务，不再以这个账号收通知。
      if (!auth.isAuthenticated && !auth.isLoading) unawaited(stop());
    });
  }
}

@pragma('vm:entry-point')
void pmchatBackgroundTaskStart() {
  FlutterForegroundTask.setTaskHandler(_PmChatBackgroundTask());
}

class _PmChatBackgroundTask extends TaskHandler {
  static const AndroidNotificationChannel _messages = AndroidNotificationChannel(
    'pm_chat_messages',
    'PM chat messages',
    description: 'Incoming PM chat message notifications',
    importance: Importance.high,
  );
  static const AndroidNotificationChannel _calls = AndroidNotificationChannel(
    'pm_chat_calls',
    'PM chat 来电',
    description: '语音和视频来电',
    importance: Importance.max,
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  BackgroundMessageClient? _client;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _notifications.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_messages);
    await android?.createNotificationChannel(_calls);

    final client = BackgroundMessageClient(
      endpoint: Uri.parse(ApiConstants.wsEndpoint),
      readAccessToken: _readAccessToken,
      refreshAccessToken: _refreshAccessToken,
      onNotification: (notification) => unawaited(_show(notification)),
      onSessionExpired: _onSessionExpired,
    );
    _client = client;
    await client.start();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final client = _client;
    if (client != null && !client.isConnected) {
      unawaited(client.reconnectNow());
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _client?.stop();
    _client = null;
  }

  @override
  void onNotificationPressed() {
    // 点常驻通知：把 App 拉回前台。
    FlutterForegroundTask.launchApp();
  }

  Future<String?> _readAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    // 主界面续期后会写入新的 token，这里读之前先刷新缓存。
    await prefs.reload();
    return prefs.getString('access_token');
  }

  Future<BackgroundTokenRefresh> _refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final auth = AuthService();
    await auth.initialize(validateInBackground: false);
    if (await auth.refreshAccessToken()) return BackgroundTokenRefresh.refreshed;
    return auth.refreshTokenRejected
        ? BackgroundTokenRefresh.rejected
        : BackgroundTokenRefresh.unavailable;
  }

  Future<void> _show(BackgroundNotification notification) async {
    final payload = jsonEncode({
      ...notification.data,
      'receivedAt': DateTime.now().millisecondsSinceEpoch,
    });
    final roomId = notification.chatRoomId ?? 0;
    try {
      if (notification.isCall) {
        await _notifications.show(
          900000 + roomId,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _calls.id,
              _calls.name,
              channelDescription: _calls.description,
              importance: Importance.max,
              priority: Priority.max,
              category: AndroidNotificationCategory.call,
              // 对方最多响铃 30 秒，过时的来电通知自动消失。
              timeoutAfter: 30000,
            ),
          ),
          payload: payload,
        );
        return;
      }
      await _notifications.show(
        roomId,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _messages.id,
            _messages.name,
            channelDescription: _messages.description,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      // 通知只是提醒，失败不能拖垮后台连接。
    }
  }

  void _onSessionExpired() {
    unawaited(_notifications.show(
      1,
      'PM chat 登录已过期',
      '打开 PM chat 重新登录后才能继续收到消息',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _messages.id,
          _messages.name,
          channelDescription: _messages.description,
        ),
      ),
    ));
    unawaited(FlutterForegroundTask.stopService());
  }
}
