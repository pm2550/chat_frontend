import 'dart:io' show File, Platform, exit, pid;
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_constants.dart';
import '../models/app_version.dart';
import '../services/android_apk_installer.dart';
import '../services/app_update_installer.dart';
import '../services/update_service.dart';
import '../services/web_reload.dart' as web_reload;

/// 应用内更新：
///   - Android：下载 APK，交给系统安装器
///   - Linux / Windows：下载、校验、解压到暂存区，确认后原地替换当前安装目录并重启
///   - macOS：沙盒应用不能改 /Applications，下载到「下载」文件夹并说明怎么替换
///   - iOS：浏览器下载的 .ipa 装不上，跳 TestFlight（配置了的话）或网页版
///   - Web：直接刷新页面
class UpdateDialog extends StatefulWidget {
  final AppVersionCheck versionCheck;

  /// 是否按网页端处理“立即更新”（重新加载页面而不是下载安装包）。
  final bool isWeb;

  /// 网页端重新加载的实现，测试时可替换。
  final VoidCallback? onReloadWeb;

  const UpdateDialog({
    super.key,
    required this.versionCheck,
    this.isWeb = kIsWeb,
    this.onReloadWeb,
  });

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

enum _UpdateStage {
  idle,
  downloading,
  preparing,
  readyToRestart,
  restarting,
  savedToDownloads,
  androidInstalling,
}

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdateStage _stage = _UpdateStage.idle;
  double _progress = 0;
  String? _error;
  StagedDesktopUpdate? _staged;
  String? _savedPath;

  AppVersionCheck get _check => widget.versionCheck;

  UpdateInstallMode get _mode {
    if (widget.isWeb) return UpdateInstallMode.unsupported;
    return updateInstallModeFor(
      defaultTargetPlatform,
      updateArtifactKindFor(_check.downloadUrl ?? ''),
    );
  }

  bool get _busy =>
      _stage == _UpdateStage.downloading ||
      _stage == _UpdateStage.preparing ||
      _stage == _UpdateStage.restarting;

  @override
  void dispose() {
    // 用户没点"立即重启"就关了弹窗：暂存的新版本不用了，别留在磁盘上。
    final staged = _staged;
    if (staged != null) staged.discard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showIosHint =
        _mode == UpdateInstallMode.openLink && _stage == _UpdateStage.idle;
    return AlertDialog(
      title: const Text('发现新版本'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _check.latestVersion ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (_check.releaseNotes != null &&
                _check.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('更新内容：',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_check.releaseNotes!),
            ],
            if (_check.fileSize != null &&
                _mode != UpdateInstallMode.openLink) ...[
              const SizedBox(height: 8),
              Text(
                '大小：${_formatSize(_check.fileSize!)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
            if (showIosHint) ...[
              const SizedBox(height: 12),
              Text(ApiConstants.iosTestFlightUrl.isNotEmpty
                  ? '请在 TestFlight 里安装新版本。'
                  : 'iPhone / iPad 暂时没有可以直接安装的安装包。'
                      '请用 Safari 打开网页版，点「分享 → 添加到主屏幕」即可像 App 一样使用。'),
            ],
            if (_check.forceUpdate && _stage == _UpdateStage.idle) ...[
              const SizedBox(height: 12),
              const Text('此版本为强制更新，请更新后继续使用。',
                  style: TextStyle(color: Colors.red)),
            ],
            if (_stage == _UpdateStage.downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('下载中... ${(_progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ],
            if (_stage == _UpdateStage.preparing ||
                _stage == _UpdateStage.restarting) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                _stage == _UpdateStage.preparing ? '正在校验安装包...' : '正在重启...',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
            if (_stage == _UpdateStage.readyToRestart)
              _statusRow('新版本已准备好，重启 PM chat 即可完成更新。'),
            if (_stage == _UpdateStage.androidInstalling)
              _statusRow('下载完成，请在系统安装界面确认安装。'),
            if (_stage == _UpdateStage.savedToDownloads) ...[
              _statusRow(
                  '安装包已保存到「下载」文件夹：\n${p.basename(_savedPath ?? '')}'),
              const SizedBox(height: 8),
              const Text(
                '请退出 PM chat，解压后把「PM chat.app」拖进「应用程序」文件夹替换旧版本。'
                '如果打开时提示无法验证开发者，请右键点应用选「打开」。',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: _buildActions(),
    );
  }

  Widget _statusRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    final canDismiss = !_check.forceUpdate && !_busy;
    final dismiss = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(_stage == _UpdateStage.savedToDownloads ? '关闭' : '稍后再说'),
    );
    switch (_stage) {
      case _UpdateStage.downloading:
      case _UpdateStage.preparing:
      case _UpdateStage.restarting:
        return const [];
      case _UpdateStage.readyToRestart:
        return [
          if (canDismiss) dismiss,
          ElevatedButton(
            onPressed: _restartIntoUpdate,
            child: const Text('立即重启'),
          ),
        ];
      case _UpdateStage.savedToDownloads:
        return [
          if (canDismiss) dismiss,
          TextButton(
            onPressed: _revealDownload,
            child: const Text('在访达中显示'),
          ),
          ElevatedButton(
            onPressed: _quitApp,
            child: const Text('退出 PM chat'),
          ),
        ];
      case _UpdateStage.androidInstalling:
        return [
          if (canDismiss) dismiss,
          ElevatedButton(
            onPressed: _startAutoUpdate,
            child: const Text('重新下载'),
          ),
        ];
      case _UpdateStage.idle:
        return [
          if (canDismiss) dismiss,
          if (_error != null && _mode != UpdateInstallMode.unsupported)
            TextButton(
              onPressed: _openDownloadsPage,
              child: const Text('打开下载页'),
            ),
          ElevatedButton(
            onPressed: _startAutoUpdate,
            child: Text(_primaryLabel()),
          ),
        ];
    }
  }

  String _primaryLabel() {
    // 网页端"更新"就是刷新页面。
    if (widget.isWeb) return '立即更新';
    return switch (_mode) {
      UpdateInstallMode.openLink =>
        ApiConstants.iosTestFlightUrl.isNotEmpty ? '前往 TestFlight' : '打开网页版',
      UpdateInstallMode.unsupported => '打开下载页',
      _ when _error != null => '重试',
      UpdateInstallMode.saveToDownloads => '下载新版本',
      _ => '立即更新',
    };
  }

  Future<void> _startAutoUpdate() async {
    final url = _check.downloadUrl;
    if (widget.isWeb) {
      // 网页端的新版本就是新的静态资源：重新加载页面即可生效，
      // 不存在需要下载的安装包。
      (widget.onReloadWeb ?? UpdateDialog._reloadWebPage)();
      return;
    }

    switch (_mode) {
      case UpdateInstallMode.openLink:
        await _launchExternal(ApiConstants.iosTestFlightUrl.isNotEmpty
            ? ApiConstants.iosTestFlightUrl
            : ApiConstants.webAppUrl);
        return;
      case UpdateInstallMode.unsupported:
        await _openDownloadsPage();
        return;
      case UpdateInstallMode.androidApk:
      case UpdateInstallMode.replaceInstallation:
      case UpdateInstallMode.saveToDownloads:
        break;
    }
    if (url == null || url.isEmpty) return;

    setState(() {
      _stage = _UpdateStage.downloading;
      _progress = 0;
      _error = null;
    });

    try {
      final directory = await _downloadDirectory();
      final path = await UpdateService.downloadArtifact(
        url,
        directory: directory,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _stage = _UpdateStage.preparing);
      await verifyDownloadedArtifact(
        File(path),
        expectedSize: _check.fileSize,
        expectedSha256: _check.sha256,
      );
      await _install(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _UpdateStage.idle;
          _error = e is UpdateInstallException ? e.message : '更新失败: $e';
        });
      }
    }
  }

  Future<String> _downloadDirectory() async {
    switch (_mode) {
      case UpdateInstallMode.saveToDownloads:
        // 沙盒里写「下载」需要 com.apple.security.files.downloads.read-write。
        final downloads = await getDownloadsDirectory();
        if (downloads == null) {
          throw const UpdateInstallException('找不到「下载」文件夹');
        }
        return downloads.path;
      case UpdateInstallMode.replaceInstallation:
        final temp = await getTemporaryDirectory();
        return p.join(temp.path, UpdateService.updateDownloadFolder);
      default:
        // Android：本用户自己的 cache 目录（FileProvider 的 cache-path 覆盖它）。
        return (await getTemporaryDirectory()).path;
    }
  }

  Future<void> _install(String path) async {
    switch (_mode) {
      case UpdateInstallMode.androidApk:
        setState(() => _stage = _UpdateStage.androidInstalling);
        await _installAndroidApk(path);
      case UpdateInstallMode.replaceInstallation:
        await _stageDesktopUpdate(path);
      case UpdateInstallMode.saveToDownloads:
        setState(() {
          _savedPath = path;
          _stage = _UpdateStage.savedToDownloads;
        });
        await _revealDownload();
      case UpdateInstallMode.openLink:
      case UpdateInstallMode.unsupported:
        break;
    }
  }

  Future<void> _stageDesktopUpdate(String archivePath) async {
    if (!kReleaseMode) {
      // flutter run 的可执行文件在 build/ 里，替换它没有意义。
      throw const UpdateInstallException('开发版不支持自动更新，请用正式安装包');
    }
    final installation =
        DesktopInstallation.fromExecutable(Platform.resolvedExecutable);
    final archive = File(archivePath);
    final StagedDesktopUpdate staged;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      staged = await stageWindowsUpdate(
        archive: archive,
        installation: installation,
        tempRoot: (await getTemporaryDirectory()).path,
      );
    } else {
      staged = await stageLinuxUpdate(
        archive: archive,
        installation: installation,
      );
    }
    try {
      await archive.delete();
    } catch (_) {}
    if (!mounted) {
      await staged.discard();
      return;
    }
    setState(() {
      _staged = staged;
      _stage = _UpdateStage.readyToRestart;
    });
  }

  Future<void> _restartIntoUpdate() async {
    final staged = _staged;
    if (staged == null) return;
    setState(() {
      _stage = _UpdateStage.restarting;
      _error = null;
    });
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final temp = await getTemporaryDirectory();
        await launchWindowsUpdateHelper(
          staged,
          processId: pid,
          logPath: p.join(temp.path, 'pmchat-update.log'),
        );
      } else {
        await applyLinuxUpdate(staged);
      }
      // 暂存区已交给新版本/更新助手处理，dispose 时不能再删。
      _staged = null;
      await _quitApp();
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _UpdateStage.readyToRestart;
          _error = e is UpdateInstallException ? e.message : '更新失败: $e';
        });
      }
    }
  }

  Future<void> _installAndroidApk(String apkPath) async {
    try {
      final launched = await AndroidApkInstaller.install(apkPath);
      if (launched) return;
    } catch (e) {
      debugPrint('Android APK installer failed: $e');
    }

    // If the native installer is unavailable, fall back to the browser so the
    // user can still sideload the APK manually.
    await _launchExternal(UpdateService.resolveUrl(_check.downloadUrl));
  }

  Future<void> _revealDownload() async {
    final path = _savedPath;
    if (path == null) return;
    await _launchExternal(Uri.directory(p.dirname(path)).toString());
  }

  Future<void> _openDownloadsPage() =>
      _launchExternal(ApiConstants.webDownloadsPageUrl);

  Future<void> _launchExternal(String url) async {
    if (url.isEmpty) return;
    try {
      final opened =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (opened) return;
    } catch (_) {}
    if (mounted) setState(() => _error = '无法打开 $url');
  }

  /// 正常关窗口退出；引擎不支持时直接结束进程。
  Future<void> _quitApp() async {
    try {
      await ServicesBinding.instance.exitApplication(AppExitType.required);
    } catch (_) {}
    exit(0);
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
