import 'desktop_notification_backend.dart';

DesktopNotificationBackend createDesktopNotificationBackend() =>
    StubDesktopNotificationBackend();

class StubDesktopNotificationBackend implements DesktopNotificationBackend {
  StubDesktopNotificationBackend({
    this.supported = false,
    this.permissionGranted = false,
    this.visible = true,
    this.notifiesInsideChat = false,
  });

  bool supported;
  bool permissionGranted;
  bool visible;
  bool notifiesInsideChat;
  int lastUnreadCount = 0;
  final List<ShownDesktopNotification> shownNotifications = [];

  @override
  bool get isSupported => supported;

  @override
  bool get hasPermission => permissionGranted;

  @override
  bool get pageIsVisible => visible;

  @override
  bool get notifiesWhileInsideChat => notifiesInsideChat;

  @override
  Future<bool> requestPermission() async {
    permissionGranted = supported;
    return permissionGranted;
  }

  @override
  void showNotification({
    required String title,
    required String body,
    String? tag,
    String? payload,
  }) {
    shownNotifications.add(ShownDesktopNotification(
      title: title,
      body: body,
      tag: tag,
      payload: payload,
    ));
  }

  @override
  void updateUnreadBadge(int unreadCount) {
    lastUnreadCount = unreadCount;
  }
}

class ShownDesktopNotification {
  const ShownDesktopNotification({
    required this.title,
    required this.body,
    this.tag,
    this.payload,
  });

  final String title;
  final String body;
  final String? tag;
  final String? payload;
}
