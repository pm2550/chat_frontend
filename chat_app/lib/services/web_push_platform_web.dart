import 'dart:convert';
import 'dart:js_interop';

import 'web_push_platform.dart';

WebPushPlatform createWebPushPlatform() => WebBrowserPushPlatform();

@JS('pmchatWebPushIsSupported')
external bool _isSupported();

@JS('pmchatWebPushIsStandalone')
external bool _isStandalone();

@JS('pmchatWebPushPermission')
external JSString _permission();

@JS('pmchatWebPushSubscribe')
external JSPromise<JSAny?> _subscribe(JSString vapidPublicKey);

@JS('pmchatWebPushUnsubscribe')
external JSPromise<JSAny?> _unsubscribe();

@JS('JSON.stringify')
external JSString _jsonStringify(JSAny? value);

class WebBrowserPushPlatform implements WebPushPlatform {
  @override
  bool get isSupported => _guardBool(() => _isSupported());

  @override
  bool get isStandalone => _guardBool(() => _isStandalone());

  @override
  String get permission {
    try {
      return _permission().toDart;
    } catch (_) {
      return 'unsupported';
    }
  }

  @override
  Future<Map<String, dynamic>> subscribe(String vapidPublicKey) async {
    final result = await _subscribe(vapidPublicKey.toJS).toDart;
    return _asStringKeyMap(result);
  }

  @override
  Future<Map<String, dynamic>> unsubscribe() async {
    final result = await _unsubscribe().toDart;
    return _asStringKeyMap(result);
  }

  bool _guardBool(bool Function() callback) {
    try {
      return callback();
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _asStringKeyMap(JSAny? value) {
    try {
      final encoded = _jsonStringify(value).toDart;
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {
      // Fall through to a structured failure value.
    }
    return {'ok': false, 'reason': 'invalid_result'};
  }
}
