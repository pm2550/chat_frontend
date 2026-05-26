import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import 'auth_service.dart';

class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;
  PushService._internal();

  final AuthService _authService = AuthService();

  /// Register device token for push notifications
  Future<bool> registerDeviceToken(String token) async {
    try {
      String platform;
      if (kIsWeb) {
        platform = 'WEB';
      } else if (Platform.isAndroid) {
        platform = 'ANDROID';
      } else if (Platform.isIOS) {
        platform = 'IOS';
      } else if (Platform.isWindows) {
        platform = 'WINDOWS';
      } else if (Platform.isMacOS) {
        platform = 'MACOS';
      } else {
        platform = 'ANDROID'; // fallback
      }

      final response = await _authService.authenticatedRequest(
        'POST',
        ApiConstants.registerDevice,
        body: {
          'token': token,
          'platform': platform,
          'deviceInfo':
              '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Register device token error: $e');
      return false;
    }
  }

  /// Unregister device token
  Future<bool> unregisterDeviceToken(String token) async {
    try {
      final response = await _authService.authenticatedRequest(
        'POST',
        ApiConstants.unregisterDevice,
        body: {'token': token},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
