import 'desktop_notification_backend.dart';
import 'desktop_notification_stub.dart'
    if (dart.library.js_interop) 'desktop_notification_web.dart' as platform;

class DesktopNotificationService {
  DesktopNotificationService({
    DesktopNotificationBackend? backend,
  }) : _backend = backend ?? platform.createDesktopNotificationBackend();

  final DesktopNotificationBackend _backend;

  int _unreadCount = 0;

  int get unreadCount => _unreadCount;
  bool get isSupported => _backend.isSupported;
  bool get hasPermission => _backend.hasPermission;

  Future<bool> requestPermission() => _backend.requestPermission();

  void syncUnreadCount(int count) {
    final nextCount = count < 0 ? 0 : count;
    if (nextCount == _unreadCount) return;
    _unreadCount = nextCount;
    _backend.updateUnreadBadge(_unreadCount);
  }

  void notifyIncomingMessage({
    required String chatName,
    required String body,
    bool muted = false,
  }) {
    if (muted || !_backend.isSupported || !_backend.hasPermission) {
      return;
    }
    if (_backend.pageIsVisible) {
      return;
    }
    _backend.showNotification(
      title: chatName,
      body: body,
      tag: 'pm-chat-message',
    );
  }
}
