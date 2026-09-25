import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Android 安装包按 CPU 架构拆成两个 APK（整包带两套原生库超过 100MB）：
/// 自更新、WebSocket 更新推送都要报上本机架构，拿对应的那个包。
class DeviceAbi {
  DeviceAbi._();

  /// 64 位手机（近几年的手机基本都是）。
  static const String arm64 = 'arm64-v8a';

  /// 只能跑 32 位的旧手机。
  static const String armeabiV7a = 'armeabi-v7a';

  /// 按优先级排：能跑 64 位就要 64 位包（更快，而且不少新手机已经不支持 32 位应用）。
  static const List<String> published = [arm64, armeabiV7a];

  /// 从系统报的 ABI 列表（Build.SUPPORTED_ABIS）里挑一个有发布包的。
  /// 两个都不支持（x86_64 模拟器且没有 ARM 转译）返回 null：不报架构，服务器按默认给 64 位包。
  static String? pick(Iterable<String> supportedAbis) {
    final supported = supportedAbis.map((abi) => abi.trim().toLowerCase()).toSet();
    for (final abi in published) {
      if (supported.contains(abi)) return abi;
    }
    return null;
  }

  static Future<String?>? _cached;

  /// 本机应该下载的 ABI；非 Android（网页、桌面、iOS）返回 null。
  static Future<String?> current() {
    final override = _debugOverride;
    if (override != null) return override();
    if (kIsWeb || !Platform.isAndroid) return Future<String?>.value();
    return _cached ??= _detect();
  }

  static Future<String?> _detect() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return pick(info.supportedAbis);
    } catch (e) {
      debugPrint('Failed to read supported ABIs: $e');
      return null;
    }
  }

  static Future<String?> Function()? _debugOverride;

  /// 测试里替换本机架构；传 null 恢复。
  @visibleForTesting
  static set debugOverride(Future<String?> Function()? value) {
    _debugOverride = value;
  }
}
