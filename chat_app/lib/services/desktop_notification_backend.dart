abstract class DesktopNotificationBackend {
  bool get isSupported;
  bool get hasPermission;
  bool get pageIsVisible;

  Future<bool> requestPermission();

  void showNotification({
    required String title,
    required String body,
    String? tag,
  });

  void updateUnreadBadge(int unreadCount);
}
