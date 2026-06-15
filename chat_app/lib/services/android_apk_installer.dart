import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class AndroidApkInstaller {
  static const MethodChannel _channel = MethodChannel('pmchat/apk_installer');

  static Future<bool> install(String apkPath) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final launched = await _channel.invokeMethod<bool>(
      'installApk',
      {'path': apkPath},
    );
    return launched == true;
  }
}
