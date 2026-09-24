import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'desktop_notification_backend.dart';
import 'local_notifications_setup.dart';

DesktopNotificationBackend createDesktopNotificationBackend() =>
    IoDesktopNotificationBackend();

class IoDesktopNotificationBackend
    with WidgetsBindingObserver
    implements DesktopNotificationBackend {
  IoDesktopNotificationBackend() {
    WidgetsBinding.instance.addObserver(this);
  }

  static const AndroidNotificationChannel _messageChannel =
      AndroidNotificationChannel(
    'pm_chat_messages',
    'PM chat messages',
    description: 'Incoming PM chat message notifications',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _channelCreated = false;
  bool _permissionGranted = false;
  AppLifecycleState? _lifecycleState = WidgetsBinding.instance.lifecycleState;

  @override
  bool get isSupported =>
      LocalNotificationsSetup.supportsPlatform(defaultTargetPlatform);

  /// 桌面端没有推送通道，窗口在后台时只能靠本地通知提醒；
  /// 所以即使正停在某个聊天里，其它会话来消息也要弹。
  @override
  bool get notifiesWhileInsideChat =>
      LocalNotificationsSetup.isDesktop(defaultTargetPlatform);

  @override
  bool get hasPermission => _permissionGranted;

  @override
  bool get pageIsVisible => _lifecycleState == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      if (!await LocalNotificationsSetup.ensureInitialized()) return false;
      await _ensureChannel();
      // Linux / Windows 没有通知授权这回事，插件初始化成功就能发。
      var granted = true;
      if (Platform.isAndroid) {
        final android = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        granted = await android?.requestNotificationsPermission() ?? true;
      } else if (Platform.isIOS) {
        final ios = _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        granted = await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      } else if (Platform.isMacOS) {
        final macos = _notifications.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
        granted = await macos?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      _permissionGranted = granted;
      return granted;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void showNotification({
    required String title,
    required String body,
    String? tag,
    String? payload,
  }) {
    if (!isSupported || !_permissionGranted) return;
    unawaited(_show(title: title, body: body, tag: tag, payload: payload));
  }

  Future<void> _show({
    required String title,
    required String body,
    String? tag,
    String? payload,
  }) async {
    try {
      if (!await LocalNotificationsSetup.ensureInitialized()) return;
      await _notifications.show(
        // 同一个 tag（同一个会话）的新通知替换旧的，不在通知中心堆成一串。
        tag == null
            ? DateTime.now().millisecondsSinceEpoch.remainder(1 << 31)
            : tag.hashCode & 0x7fffffff,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannel.id,
            _messageChannel.name,
            channelDescription: _messageChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            tag: tag,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
          linux: const LinuxNotificationDetails(
            category: LinuxNotificationCategory.imReceived,
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      // Notification delivery is best-effort UI chrome; never break chat flow.
    }
  }

  @override
  void updateUnreadBadge(int unreadCount) {
    // Android launcher badges are OEM-specific; keep unread badge handling on web.
  }

  Future<void> _ensureChannel() async {
    if (_channelCreated) return;
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_messageChannel);
    _channelCreated = true;
  }
}
