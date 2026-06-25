import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'push_service.dart';

bool _nativePushStarted = false;
StreamSubscription<String>? _tokenRefreshSubscription;

Future<void> initializeNativePush() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  if (_nativePushStarted) return;
  _nativePushStarted = true;

  try {
    await Firebase.initializeApp();
  } on MissingPluginException catch (error) {
    debugPrint('Native push unavailable: Firebase plugin missing ($error)');
    return;
  } catch (error) {
    debugPrint('Native push unavailable: Firebase is not configured ($error)');
    return;
  }

  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    await _registerCurrentToken(messaging);
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen((token) {
      unawaited(PushService().registerDeviceToken(token));
    });
  } catch (error) {
    debugPrint('Native push registration failed: $error');
  }
}

Future<void> _registerCurrentToken(FirebaseMessaging messaging) async {
  final token = await messaging.getToken();
  if (token == null || token.isEmpty) return;
  await PushService().registerDeviceToken(token);
}
