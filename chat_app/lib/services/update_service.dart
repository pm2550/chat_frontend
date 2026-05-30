import 'dart:convert';
import 'dart:io' show Platform, Process;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../constants/api_constants.dart';
import '../models/app_version.dart';

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

    // Native/desktop apps are strict. Web is also used as a production
    // smoke/redirect surface, so it can surface any published client build.
    return current == update || current == 'WEB';
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

  /// Download the artifact to a local temp path. [onProgress] receives 0.0–1.0.
  static Future<String> downloadArtifact(
    String downloadUrl, {
    void Function(double progress)? onProgress,
  }) async {
    final fullUrl = resolveUrl(downloadUrl);
    final filename = p.basename(Uri.parse(fullUrl).path);

    // Use platform-appropriate temp directory
    String dir;
    if (!kIsWeb && Platform.isAndroid) {
      // Android external cache so FileProvider can serve it
      dir = '/data/data/com.pm2550.chat/cache';
    } else if (!kIsWeb && (Platform.isMacOS || Platform.isLinux)) {
      dir = Platform.environment['TMPDIR'] ?? '/tmp';
    } else if (!kIsWeb && Platform.isWindows) {
      dir = Platform.environment['TEMP'] ?? r'C:\Temp';
    } else {
      dir = '/tmp';
    }

    final savePath = p.join(dir, filename);

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

  /// Android: trigger the system package installer for the downloaded APK.
  static Future<void> installApk(String apkPath) async {
    // Use Android Intent via platform channel or open_filex.
    // Since we already depend on url_launcher, we use a content:// URI approach.
    // For simplicity, invoke the system installer via a shell command using
    // Android's `am start` through Process. But on Android, Process.run
    // is sandboxed. The clean approach: use the open_filex package or
    // a small method channel.
    //
    // Fallback: open the file with url_launcher which on Android triggers
    // "open with" → package installer.
    // This requires the FileProvider we configured in AndroidManifest.xml.
    //
    // For now we use the 'open_filex' approach via Process on desktop,
    // and url_launcher on mobile.
    throw UnsupportedError(
      'installApk is handled by the UpdateDialog widget using platform-specific logic',
    );
  }

  /// macOS / Linux: unzip and replace the .app bundle.
  static Future<void> installDesktopUpdate(String zipPath) async {
    if (kIsWeb) return;

    if (Platform.isMacOS) {
      // Unzip to /Applications (user may need to grant permission)
      final result =
          await Process.run('unzip', ['-o', zipPath, '-d', '/Applications']);
      if (result.exitCode != 0) {
        throw Exception('解压失败: ${result.stderr}');
      }
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final result =
          await Process.run('unzip', ['-o', zipPath, '-d', '$home/chat_app']);
      if (result.exitCode != 0) {
        throw Exception('解压失败: ${result.stderr}');
      }
    } else if (Platform.isWindows) {
      // PowerShell Expand-Archive
      final home = Platform.environment['USERPROFILE'] ?? r'C:\Users\Public';
      final result = await Process.run('powershell', [
        '-Command',
        'Expand-Archive -Force -Path "$zipPath" -DestinationPath "$home\\ChatApp"',
      ]);
      if (result.exitCode != 0) {
        throw Exception('解压失败: ${result.stderr}');
      }
    }
  }

  /// Web: force-reload the page to pick up new service worker + assets.
  static void reloadWeb() {
    // This is called from update_dialog.dart which handles the web case
    // via dart:html (conditional import).
  }

  static void _log(String msg) {
    assert(() {
      // ignore: avoid_print
      print(msg);
      return true;
    }());
  }
}
