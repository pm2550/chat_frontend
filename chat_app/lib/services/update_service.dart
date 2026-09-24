import 'dart:convert';
import 'dart:io' show Directory, Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/api_constants.dart';
import '../models/app_version.dart';
import 'app_update_installer.dart';

class UpdateService {
  static final Dio _dio = Dio();

  static String _platformName() {
    if (kIsWeb) return 'WEB';
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isIOS) return 'IOS';
    if (Platform.isMacOS) return 'MACOS';
    if (Platform.isWindows) return 'WINDOWS';
    if (Platform.isLinux) return 'LINUX';
    return 'WEB';
  }

  static String currentPlatformName() => _platformName();

  static bool shouldHandleUpdateForPlatform(
    String? updatePlatform, {
    String? currentPlatform,
  }) {
    final update = updatePlatform?.trim().toUpperCase();
    if (update == null || update.isEmpty) return false;
    final current = (currentPlatform ?? _platformName()).trim().toUpperCase();

    // 每个端只处理自己平台的发布：Web 用户收到 Android/Windows 的包时
    // “立即更新”只会去下载一个原生安装包，对网页本身毫无作用。
    return current == update;
  }

  static AppVersionCheck checkFromWebSocketPayload(
    Map<String, dynamic> payload,
  ) {
    return AppVersionCheck(
      updateAvailable: true,
      forceUpdate: payload['forceUpdate'] == true,
      latestVersion: payload['versionName']?.toString(),
      latestVersionCode: payload['versionCode'] is int
          ? payload['versionCode'] as int
          : int.tryParse(payload['versionCode']?.toString() ?? ''),
      releaseNotes: payload['releaseNotes']?.toString(),
      downloadUrl: payload['downloadUrl']?.toString(),
      fileSize: payload['fileSize'] is int
          ? payload['fileSize'] as int
          : int.tryParse(payload['fileSize']?.toString() ?? ''),
      sha256: payload['sha256']?.toString(),
    );
  }

  /// Check the backend for a newer version.
  static Future<AppVersionCheck> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      final platform = _platformName();

      final uri = Uri.parse(
        '${ApiConstants.appVersionCheck}?platform=$platform&currentVersionCode=$currentCode',
      );
      final response = await http.get(uri).timeout(ApiConstants.requestTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return AppVersionCheck.fromJson(json);
      }
    } catch (e) {
      _log('Update check failed: $e');
    }
    return AppVersionCheck.noUpdate();
  }

  /// Resolve absolute download URL from the version check response.
  static String resolveUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    return url.startsWith('http') ? url : '${ApiConstants.baseUrl}$url';
  }

  /// 把安装包下到 [directory]，[onProgress] 收到 0.0–1.0。
  ///
  /// 目录由调用方按平台选（path_provider），不能写死：Android 的多用户/工作资料
  /// 各有自己的 /data/user/<n>，iOS/macOS 沙盒也不让随便写 /tmp、/Applications。
  static Future<String> downloadArtifact(
    String downloadUrl, {
    required String directory,
    void Function(double progress)? onProgress,
  }) async {
    final fullUrl = resolveUrl(downloadUrl);
    final filename = p.basename(Uri.parse(fullUrl).path);
    await Directory(directory).create(recursive: true);
    final savePath = p.join(directory, filename);

    await _dio.download(
      fullUrl,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );

    return savePath;
  }

  /// 新版本启动后清理上次更新留下的临时文件（Linux 旧安装目录、下载缓存）。
  static Future<void> cleanupAfterUpdate() async {
    if (kIsWeb) return;
    try {
      if (Platform.isLinux && kReleaseMode) {
        await cleanupLinuxUpdateLeftovers(
          DesktopInstallation.fromExecutable(Platform.resolvedExecutable),
        );
      }
      if (Platform.isLinux || Platform.isWindows) {
        final temp = await getTemporaryDirectory();
        for (final name in [updateDownloadFolder, 'pmchat-update']) {
          final dir = Directory(p.join(temp.path, name));
          if (await dir.exists()) await dir.delete(recursive: true);
        }
      }
    } catch (e) {
      _log('Update cleanup failed: $e');
    }
  }

  /// Linux/Windows 下载安装包用的临时子目录。
  static const String updateDownloadFolder = 'pmchat-update-download';

  static void _log(String msg) {
    assert(() {
      // ignore: avoid_print
      print(msg);
      return true;
    }());
  }
}
