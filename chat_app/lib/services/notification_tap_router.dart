import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'pending_call_invite.dart';

/// 点系统通知后跳到对应聊天；来电通知还会在聊天页里弹出接听框。
class NotificationTapRouter {
  NotificationTapRouter._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static String? _pendingRoute;

  static void attach(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  /// flutter_local_notifications 的点击回调（前台、后台、冷启动都走这里）。
  static void handleResponse(NotificationResponse response) {
    handlePayload(response.payload);
  }

  static void handlePayload(String? payload, {DateTime? now}) {
    final route = routeForPayload(payload, now: now);
    if (route == null) return;
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      // 冷启动时导航器还没建好，等首页出来再跳。
      _pendingRoute = route;
      return;
    }
    navigator.pushNamed(route);
  }

  /// 首页建好后调用一次，补上冷启动时没来得及跳的通知。
  static void flushPending() {
    final route = _pendingRoute;
    final navigator = _navigatorKey?.currentState;
    if (route == null || navigator == null) return;
    _pendingRoute = null;
    navigator.pushNamed(route);
  }

  @visibleForTesting
  static String? routeForPayload(String? payload, {DateTime? now}) {
    if (payload == null || payload.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final data = Map<String, dynamic>.from(decoded);
    final chatRoomId = int.tryParse(data['chatRoomId']?.toString() ?? '');
    if (chatRoomId == null) return null;
    if (data['type'] == 'call') {
      final receivedAtMs = int.tryParse(data['receivedAt']?.toString() ?? '');
      PendingCallInvite.put(
        data,
        receivedAt: receivedAtMs == null
            ? now
            : DateTime.fromMillisecondsSinceEpoch(receivedAtMs),
      );
    }
    return '/chat/$chatRoomId';
  }
}
