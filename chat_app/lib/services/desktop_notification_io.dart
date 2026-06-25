import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'desktop_notification_backend.dart';

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

  bool _initialized = false;
  bool _permissionGranted = false;
  AppLifecycleState? _lifecycleState = WidgetsBinding.instance.lifecycleState;

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

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
      await _ensureInitialized();
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
  }) {
    if (!isSupported || !_permissionGranted) return;
    unawaited(_show(title: title, body: body, tag: tag));
  }

  Future<void> _show({
    required String title,
    required String body,
    String? tag,
  }) async {
    try {
      await _ensureInitialized();
      await _notifications.show(
        tag?.hashCode ??
            DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
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
        ),
      );
    } catch (_) {
      // Notification delivery is best-effort UI chrome; never break chat flow.
    }
  }

  @override
  void updateUnreadBadge(int unreadCount) {
    // Android launcher badges are OEM-specific; keep unread badge handling on web.
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(initializationSettings);
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_messageChannel);
    _initialized = true;
  }
}
