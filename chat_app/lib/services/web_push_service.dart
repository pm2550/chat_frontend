import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import 'auth_service.dart';
import 'web_push_platform.dart';
import 'web_push_platform_stub.dart'
    if (dart.library.js_interop) 'web_push_platform_web.dart' as platform;

class WebPushStatus {
  const WebPushStatus({
    required this.supported,
    required this.standalone,
    required this.permission,
    required this.configured,
    this.message,
  });

  final bool supported;
  final bool standalone;
  final String permission;
  final bool configured;
  final String? message;

  bool get canRequest => supported && configured;
  bool get enabled => permission == 'granted';
}

class WebPushActionResult {
  const WebPushActionResult({
    required this.success,
    required this.message,
    required this.status,
  });

  final bool success;
  final String message;
  final WebPushStatus status;
}

class WebPushService {
  WebPushService({
    AuthService? authService,
    WebPushPlatform? platformBackend,
  })  : _authService = authService ?? AuthService(),
        _platform = platformBackend ?? platform.createWebPushPlatform();

  final AuthService _authService;
  final WebPushPlatform _platform;

  Future<WebPushStatus> getStatus() async {
    final keyInfo = await _fetchPublicKey();
    return WebPushStatus(
      supported: _platform.isSupported,
      standalone: _platform.isStandalone,
      permission: _platform.permission,
      configured: keyInfo.configured,
      message: _statusMessage(keyInfo.configured),
    );
  }

  Future<WebPushActionResult> enable() async {
    final keyInfo = await _fetchPublicKey();
    if (!_platform.isSupported) {
      return _result(false, '当前浏览器不支持 Web Push。', keyInfo.configured);
    }
    if (!keyInfo.configured || keyInfo.publicKey.isEmpty) {
      return _result(false, '服务器还没有配置 Web Push 密钥。', false);
    }
    final subscription = await _platform.subscribe(keyInfo.publicKey);
    if (subscription['ok'] != true) {
      return _result(false, _reasonToMessage(subscription['reason']), true);
    }
    final endpoint = subscription['endpoint']?.toString();
    final keys = subscription['keys'];
    if (endpoint == null || endpoint.isEmpty || keys is! Map) {
      return _result(false, '浏览器返回的订阅信息不完整。', true);
    }
    final response = await _authService.authenticatedRequest(
      'POST',
      ApiConstants.webPushSubscribe,
      body: {
        'endpoint': endpoint,
        'keys': {
          'p256dh': keys['p256dh']?.toString() ?? '',
          'auth': keys['auth']?.toString() ?? '',
        },
        'userAgent': subscription['userAgent']?.toString(),
      },
    );
    final success = response.statusCode >= 200 && response.statusCode < 300;
    return WebPushActionResult(
      success: success,
      message: success ? '后台推送已开启。' : '订阅保存失败：${response.statusCode}',
      status: await getStatus(),
    );
  }

  Future<WebPushActionResult> disable() async {
    final result = await _platform.unsubscribe();
    final endpoint = result['endpoint']?.toString();
    if (endpoint != null && endpoint.isNotEmpty) {
      await _authService.authenticatedRequest(
        'POST',
        ApiConstants.webPushUnsubscribe,
        body: {'endpoint': endpoint},
      );
    }
    return WebPushActionResult(
      success: true,
      message: '后台推送已关闭。',
      status: await getStatus(),
    );
  }

  Future<_VapidKeyInfo> _fetchPublicKey() async {
    try {
      final response = await _authService.authenticatedRequest(
        'GET',
        ApiConstants.webPushVapidPublicKey,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const _VapidKeyInfo('', false);
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final data = decoded is Map ? decoded['data'] : null;
      if (data is Map) {
        return _VapidKeyInfo(
          data['publicKey']?.toString() ?? '',
          data['configured'] == true,
        );
      }
    } catch (error) {
      debugPrint('Web Push public key error: $error');
    }
    return const _VapidKeyInfo('', false);
  }

  WebPushActionResult _result(
    bool success,
    String message,
    bool configured,
  ) {
    return WebPushActionResult(
      success: success,
      message: message,
      status: WebPushStatus(
        supported: _platform.isSupported,
        standalone: _platform.isStandalone,
        permission: _platform.permission,
        configured: configured,
        message: _statusMessage(configured),
      ),
    );
  }

  String _statusMessage(bool configured) {
    if (!_platform.isSupported) {
      return '当前浏览器不支持后台推送。';
    }
    if (!configured) {
      return '服务器 Web Push 密钥未配置。';
    }
    if (!_platform.isStandalone) {
      return 'iPhone/iPad 需要 iOS 16.4+，并先用 Safari 添加到主屏幕后才能后台推送。桌面浏览器安装 PWA 后体验最好。';
    }
    if (_platform.permission == 'denied') {
      return '浏览器已拒绝通知权限，请到系统或浏览器设置里重新允许。';
    }
    if (_platform.permission == 'granted') {
      return '后台推送已获得浏览器权限。';
    }
    return '点击开启后，浏览器会弹出通知权限确认。';
  }

  String _reasonToMessage(Object? reason) {
    switch (reason?.toString()) {
      case 'permission_denied':
        return '你拒绝了浏览器通知权限。';
      case 'unsupported':
        return '当前浏览器不支持 Web Push。';
      case 'service_worker_unavailable':
        return 'Service Worker 尚未准备好，请刷新后重试。';
      default:
        return '开启后台推送失败。';
    }
  }
}

class _VapidKeyInfo {
  const _VapidKeyInfo(this.publicKey, this.configured);

  final String publicKey;
  final bool configured;
}
