abstract class DesktopNotificationBackend {
  bool get isSupported;
  bool get hasPermission;
  bool get pageIsVisible;

  /// 停在聊天页里时，其它会话的新消息也要弹系统通知（没有别的推送通道的平台）。
  bool get notifiesWhileInsideChat;

  Future<bool> requestPermission();

  /// [payload] 是点通知时交给 NotificationTapRouter 的 JSON（含 chatRoomId）。
  void showNotification({
    required String title,
    required String body,
    String? tag,
    String? payload,
  });

  void updateUnreadBadge(int unreadCount);
}
