abstract class WebPushPlatform {
  bool get isSupported;
  bool get isStandalone;
  String get permission;

  Future<Map<String, dynamic>> subscribe(String vapidPublicKey);

  Future<Map<String, dynamic>> unsubscribe();
}
