/// 网页端没有常驻服务：iPhone/Android 网页版靠 Web Push。
class BackgroundMessageService {
  BackgroundMessageService._();

  static bool get isSupported => false;

  static Future<void> ensureStarted() async {}

  static Future<void> stop() async {}
}
