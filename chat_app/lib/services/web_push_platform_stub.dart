import 'web_push_platform.dart';

WebPushPlatform createWebPushPlatform() => StubWebPushPlatform();

class StubWebPushPlatform implements WebPushPlatform {
  @override
  bool get isSupported => false;

  @override
  bool get isStandalone => false;

  @override
  String get permission => 'unsupported';

  @override
  Future<Map<String, dynamic>> subscribe(String vapidPublicKey) async => {
        'ok': false,
        'reason': 'unsupported',
      };

  @override
  Future<Map<String, dynamic>> unsubscribe() async => {
        'ok': false,
        'reason': 'unsupported',
      };
}
