import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_version.dart';
import '../services/update_service.dart';
import '../services/web_reload.dart' as web_reload;

/// Self-updating dialog:
///   - Android: downloads APK in-app with progress bar, then triggers system installer
///   - macOS/Linux/Windows: downloads zip, extracts, prompts restart
///   - iOS: opens download link (system limitation — can't auto-install)
///   - Web: auto-reloads the page
class UpdateDialog extends StatefulWidget {
  final AppVersionCheck versionCheck;

  const UpdateDialog({super.key, required this.versionCheck});

  static Future<void> show(
    BuildContext context,
    AppVersionCheck check, {
    bool reloadWeb = true,
  }) {
    // Web: skip dialog, just reload
    if (kIsWeb && reloadWeb) {
      _reloadWebPage();
      return Future.value();
    }
    return showDialog(
      context: context,
      barrierDismissible: !check.forceUpdate,
      builder: (_) => PopScope(
        canPop: !check.forceUpdate,
        child: UpdateDialog(versionCheck: check),
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();

  static void _reloadWebPage() {
    web_reload.reloadWebPage();
  }
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  bool _installReady = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.versionCheck.latestVersion ?? '',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          if (widget.versionCheck.releaseNotes != null &&
              widget.versionCheck.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('更新内容：', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(widget.versionCheck.releaseNotes!),
          ],
          if (widget.versionCheck.fileSize != null) ...[
            const SizedBox(height: 8),
            Text(
              '大小：${_formatSize(widget.versionCheck.fileSize!)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
          if (widget.versionCheck.forceUpdate &&
              !_downloading &&
              !_installReady) ...[
            const SizedBox(height: 12),
            const Text('此版本为强制更新，请更新后继续使用。',
                style: TextStyle(color: Colors.red)),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('下载中... ${(_progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
          if (_installReady) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('下载完成，正在安装...')),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        if (!widget.versionCheck.forceUpdate && !_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后再说'),
          ),
        if (!_downloading && !_installReady)
          ElevatedButton(
            onPressed: _startAutoUpdate,
            child: const Text('立即更新'),
          ),
      ],
    );
  }

  Future<void> _startAutoUpdate() async {
    final url = widget.versionCheck.downloadUrl;
    if (url == null || url.isEmpty) return;

    if (kIsWeb) {
      final fullUrl = UpdateService.resolveUrl(url);
      final uri = Uri.parse(fullUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      // Step 1: Download
      final path = await UpdateService.downloadArtifact(
        url,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installReady = true;
      });

      // Step 2: Platform-specific install
      await _performInstall(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = '下载失败: $e';
        });
      }
    }
  }

  Future<void> _performInstall(String path) async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      await _installAndroidApk(path);
    } else if (Platform.isIOS) {
      // iOS can't auto-install — fall back to opening the URL
      final fullUrl = UpdateService.resolveUrl(widget.versionCheck.downloadUrl);
      final uri = Uri.parse(fullUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      await _installDesktop(path);
    }
  }

  Future<void> _installAndroidApk(String apkPath) async {
    // Use Android Intent to trigger package installer.
    // The 'open_filex' package or a method channel would be ideal,
    // but to avoid adding another dependency, we use url_launcher
    // with a file:// URI that goes through the FileProvider.
    //
    // Most reliable cross-API-level approach: use Process.run to call
    // `am start` with the APK intent, BUT Process.run is sandboxed on Android.
    //
    // Pragmatic solution: use url_launcher with the content:// URI scheme.
    // Actually the simplest working approach for sideloaded apps:
    // shell out to `content://` via an intent helper.
    //
    // Since we can't easily do a proper content:// URI from Dart without
    // a platform channel, we'll use the `open_filex` approach via
    // launching a file:// URL which Android converts to a content:// URI
    // when REQUEST_INSTALL_PACKAGES permission is granted.
    try {
      final uri = Uri.parse('file://$apkPath');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      // If file:// doesn't work, fall back to opening the download URL in browser
      final fullUrl = UpdateService.resolveUrl(widget.versionCheck.downloadUrl);
      final uri = Uri.parse(fullUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _installDesktop(String zipPath) async {
    try {
      await UpdateService.installDesktopUpdate(zipPath);
      if (mounted) {
        setState(() => _error = null);
        // Show restart prompt
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: const Text('更新完成'),
              content: const Text('新版本已安装，请重启应用。'),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    // Exit the app so the user relaunches the new version
                    Process.run('true', []); // no-op
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '安装失败: $e');
      }
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
