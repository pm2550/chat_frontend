import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../constants/app_brand.dart';
import 'desktop_notification_backend.dart';

@JS('updateFaviconBadge')
external void _updateFaviconBadge(JSNumber count);

DesktopNotificationBackend createDesktopNotificationBackend() =>
    WebDesktopNotificationBackend();

class WebDesktopNotificationBackend implements DesktopNotificationBackend {
  @override
  bool get isSupported => true;

  @override
  bool get hasPermission => web.Notification.permission == 'granted';

  @override
  bool get pageIsVisible => web.document.visibilityState == 'visible';

  @override
  Future<bool> requestPermission() async {
    final permission = await web.Notification.requestPermission().toDart;
    return permission.toDart == 'granted';
  }

  @override
  void showNotification({
    required String title,
    required String body,
    String? tag,
  }) {
    if (!hasPermission) return;
    web.Notification(
      title,
      web.NotificationOptions(
        body: body,
        tag: tag ?? 'pm-chat-message',
        icon: 'icons/Icon-192.png',
        badge: 'icons/Icon-192.png',
      ),
    );
  }

  @override
  void updateUnreadBadge(int unreadCount) {
    final count = unreadCount < 0 ? 0 : unreadCount;
    web.document.title =
        count > 0 ? '($count) ${AppBrand.name}' : AppBrand.name;
    try {
      _updateFaviconBadge(count.toJS);
      return;
    } catch (_) {
      // Fall back to the SVG data URL path below when the host page is not
      // the production web shell.
    }

    final href = count > 0 ? _badgeFaviconDataUrl(count) : 'favicon.png';
    final type = count > 0 ? 'image/svg+xml' : 'image/png';
    var icon = web.document.querySelector("link[rel~='icon']");
    if (icon == null) {
      final link = web.HTMLLinkElement()
        ..rel = 'icon'
        ..type = type;
      web.document.head?.children.add(link);
      icon = link;
    }
    icon
      ..setAttribute('type', type)
      ..setAttribute('href', href);
  }

  String _badgeFaviconDataUrl(int unreadCount) {
    final label = unreadCount > 99 ? '99+' : unreadCount.toString();
    final fontSize = label.length > 2 ? 26 : 34;
    final svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#2D6CDF"/>
  <path d="M14 16h27a9 9 0 0 1 9 9v6a9 9 0 0 1-9 9H29L17 50V40h-3a9 9 0 0 1-9-9v-6a9 9 0 0 1 9-9z" fill="#fff"/>
  <circle cx="46" cy="18" r="16" fill="#EF4444"/>
  <text x="46" y="29" text-anchor="middle" font-family="Arial, sans-serif" font-size="$fontSize" font-weight="700" fill="#fff">$label</text>
</svg>
''';
    return 'data:image/svg+xml,${Uri.encodeComponent(svg)}';
  }
}
