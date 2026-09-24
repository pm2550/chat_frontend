import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 发布包的格式（看下载地址的文件名）。
enum UpdateArtifactKind { apk, zip, tarGz, ipa, unknown }

UpdateArtifactKind updateArtifactKindFor(String urlOrPath) {
  final path = Uri.tryParse(urlOrPath)?.path ?? urlOrPath;
  final name = path.toLowerCase();
  if (name.endsWith('.apk')) return UpdateArtifactKind.apk;
  if (name.endsWith('.zip')) return UpdateArtifactKind.zip;
  if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) {
    return UpdateArtifactKind.tarGz;
  }
  if (name.endsWith('.ipa')) return UpdateArtifactKind.ipa;
  return UpdateArtifactKind.unknown;
}

/// 各平台拿到新版本后怎么装。
enum UpdateInstallMode {
  /// Android：下载 APK 交给系统安装器。
  androidApk,

  /// Linux / Windows：在当前安装目录原地替换，然后重启。
  replaceInstallation,

  /// macOS：沙盒应用改不了 /Applications，只能存到「下载」让用户自己替换。
  saveToDownloads,

  /// iOS：浏览器下载的 .ipa 装不上，只能跳 TestFlight / 网页版。
  openLink,

  /// 发布包和当前平台对不上，只能打开下载页。
  unsupported,
}

UpdateInstallMode updateInstallModeFor(
  TargetPlatform platform,
  UpdateArtifactKind kind,
) {
  return switch (platform) {
    TargetPlatform.android when kind == UpdateArtifactKind.apk =>
      UpdateInstallMode.androidApk,
    TargetPlatform.linux when kind == UpdateArtifactKind.tarGz =>
      UpdateInstallMode.replaceInstallation,
    TargetPlatform.windows when kind == UpdateArtifactKind.zip =>
      UpdateInstallMode.replaceInstallation,
    TargetPlatform.macOS when kind == UpdateArtifactKind.zip =>
      UpdateInstallMode.saveToDownloads,
    TargetPlatform.iOS => UpdateInstallMode.openLink,
    _ => UpdateInstallMode.unsupported,
  };
}

class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 正在运行的桌面版装在哪：可执行文件所在目录就是整个安装目录
/// （Flutter 的 Linux bundle / Windows Release 目录都是这样）。
class DesktopInstallation {
  const DesktopInstallation({
    required this.installDir,
    required this.executableName,
    required this.windows,
  });

  factory DesktopInstallation.fromExecutable(
    String resolvedExecutable, {
    bool? windows,
  }) {
    final isWindows = windows ?? Platform.isWindows;
    final context = isWindows ? p.windows : p.posix;
    return DesktopInstallation(
      installDir: context.dirname(resolvedExecutable),
      executableName: context.basename(resolvedExecutable),
      windows: isWindows,
    );
  }

  final String installDir;
  final String executableName;
  final bool windows;

  p.Context get _path => windows ? p.windows : p.posix;

  String get executablePath => _path.join(installDir, executableName);
  String get installParent => _path.dirname(installDir);
  String get installDirName => _path.basename(installDir);

  /// Linux 的替换是把新目录改名成安装目录，所以暂存目录必须放在同一个上级目录里
  /// （同一文件系统，rename 才是原子的）。
  String stagingDirFor(String stamp) =>
      _path.join(installParent, '.$installDirName.update-$stamp');

  String backupDirFor(String stamp) =>
      _path.join(installParent, '.$installDirName.old-$stamp');

  bool isLeftoverSibling(String name) =>
      name.startsWith('.$installDirName.update-') ||
      name.startsWith('.$installDirName.old-');
}

/// 在解压出来的目录里找新版本的根目录：必须有同名可执行文件和 data/flutter_assets。
/// CI 的 Linux 包外面包了一层 bundle/，Windows 的 zip 没有，所以两层都看。
String? findUpdatePayloadRoot(
  String extractedDir,
  String executableName, {
  bool caseInsensitive = false,
}) {
  bool looksLikeBundle(Directory dir) {
    final flutterAssets =
        Directory(p.join(dir.path, 'data', 'flutter_assets')).existsSync();
    if (!flutterAssets) return false;
    final wanted =
        caseInsensitive ? executableName.toLowerCase() : executableName;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      var name = p.basename(entity.path);
      if (caseInsensitive) name = name.toLowerCase();
      if (name == wanted) return true;
    }
    return false;
  }

  final root = Directory(extractedDir);
  if (!root.existsSync()) return null;
  if (looksLikeBundle(root)) return root.path;
  for (final entity in root.listSync(followLinks: false)) {
    if (entity is Directory && looksLikeBundle(entity)) return entity.path;
  }
  return null;
}

/// 校验下载的安装包：大小和（服务端给了的话）SHA-256 都要对上。
Future<void> verifyDownloadedArtifact(
  File file, {
  int? expectedSize,
  String? expectedSha256,
}) async {
  final length = await file.length();
  if (expectedSize != null && expectedSize > 0 && length != expectedSize) {
    throw UpdateInstallException(
      '安装包大小不对（应为 $expectedSize 字节，实际 $length 字节），可能没下载完整，请重试',
    );
  }
  final expected = expectedSha256?.trim().toLowerCase();
  if (expected == null || expected.isEmpty) return;
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString() != expected) {
    throw const UpdateInstallException('安装包校验失败（SHA-256 不一致），已停止安装，请重试');
  }
}

String updateStamp([DateTime? now]) {
  final t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}'
      '${two(t.second)}${t.millisecond.toString().padLeft(3, '0')}';
}

bool _canWriteInto(String dir) {
  final probe = File(p.join(dir, '.pmchat-write-test-$pid'));
  try {
    probe.writeAsStringSync('');
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// 下载、校验、解压完、随时可以替换的新版本。
class StagedDesktopUpdate {
  const StagedDesktopUpdate({
    required this.installation,
    required this.payloadDir,
    required this.stagingDir,
  });

  final DesktopInstallation installation;

  /// 新版本根目录（里面直接是可执行文件）。
  final String payloadDir;

  /// 本次更新的暂存目录，替换完或取消后删掉。
  final String stagingDir;

  Future<void> discard() async {
    try {
      await Directory(stagingDir).delete(recursive: true);
    } catch (_) {}
  }
}

typedef UpdateProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  ProcessStartMode mode,
});

typedef UpdateProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

Future<ProcessResult> _defaultRun(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) =>
    Process.run(executable, arguments, environment: environment);

/// Linux：把 tar.gz 解到安装目录旁边，校验通过后再换。
Future<StagedDesktopUpdate> stageLinuxUpdate({
  required File archive,
  required DesktopInstallation installation,
  UpdateProcessRunner run = _defaultRun,
  DateTime? now,
}) async {
  if (!_canWriteInto(installation.installParent)) {
    throw UpdateInstallException(
      '没有权限写入 ${installation.installParent}，无法自动更新。'
      '请用有权限的账号解压新版本覆盖 ${installation.installDir}',
    );
  }
  final staging = installation.stagingDirFor(updateStamp(now));
  await Directory(staging).create(recursive: true);
  try {
    final result = await run('tar', ['-xzf', archive.path, '-C', staging]);
    if (result.exitCode != 0) {
      throw UpdateInstallException('解压失败: ${result.stderr}'.trim());
    }
    final payload =
        findUpdatePayloadRoot(staging, installation.executableName);
    if (payload == null) {
      throw UpdateInstallException(
        '安装包里没有找到 ${installation.executableName}，不是这个客户端的 Linux 版',
      );
    }
    return StagedDesktopUpdate(
      installation: installation,
      payloadDir: payload,
      stagingDir: staging,
    );
  } catch (_) {
    try {
      await Directory(staging).delete(recursive: true);
    } catch (_) {}
    rethrow;
  }
}

/// Linux：运行中的程序可以直接改名替换（已加载的文件不受影响）。
/// 旧目录改名成 .old-*，新目录改名成安装目录，然后启动新版本；
/// 启动失败就换回去。旧目录由新版本下次启动时清理。
Future<void> applyLinuxUpdate(
  StagedDesktopUpdate staged, {
  UpdateProcessStarter start = Process.start,
  DateTime? now,
}) async {
  final installation = staged.installation;
  final backup = installation.backupDirFor(updateStamp(now));
  final installDir = Directory(installation.installDir);

  await installDir.rename(backup);
  try {
    await Directory(staged.payloadDir).rename(installation.installDir);
  } catch (error) {
    await Directory(backup).rename(installation.installDir);
    throw UpdateInstallException('替换安装目录失败: $error');
  }

  try {
    await start(
      installation.executablePath,
      const [],
      workingDirectory: installation.installDir,
      mode: ProcessStartMode.detached,
    );
  } catch (error) {
    // 新版本起不来：换回旧版本，别让用户下次打不开。
    try {
      final failed = '${installation.installDir}.failed-${updateStamp(now)}';
      await Directory(installation.installDir).rename(failed);
      await Directory(backup).rename(installation.installDir);
    } catch (_) {}
    throw UpdateInstallException('新版本启动失败，已恢复旧版本: $error');
  }
  await staged.discard();
}

/// Linux：上次更新留下的 .old-* / .update-* 目录。
Future<void> cleanupLinuxUpdateLeftovers(DesktopInstallation installation) async {
  try {
    final parent = Directory(installation.installParent);
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! Directory) continue;
      if (!installation.isLeftoverSibling(p.basename(entity.path))) continue;
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  } catch (_) {}
}

/// Windows：运行中的 exe/dll 被锁，不能在进程里替换。先解压到临时目录并校验，
/// 真正的替换交给一个等本进程退出后再动手的 PowerShell 脚本。
Future<StagedDesktopUpdate> stageWindowsUpdate({
  required File archive,
  required DesktopInstallation installation,
  required String tempRoot,
  UpdateProcessRunner run = _defaultRun,
  DateTime? now,
}) async {
  if (!_canWriteInto(installation.installDir)) {
    throw UpdateInstallException(
      '没有权限写入 ${installation.installDir}（比如装在 Program Files 里），无法自动更新。'
      '请手动解压新版本覆盖该目录',
    );
  }
  final staging = p.join(tempRoot, 'pmchat-update', updateStamp(now));
  final extractDir = p.join(staging, 'payload');
  await Directory(extractDir).create(recursive: true);
  try {
    // 路径走环境变量，免得路径里的引号、空格破坏命令。
    final result = await run(
      'powershell.exe',
      const [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'Expand-Archive -LiteralPath $env:PMCHAT_UPDATE_ZIP '
            r'-DestinationPath $env:PMCHAT_UPDATE_DEST -Force',
      ],
      environment: {
        'PMCHAT_UPDATE_ZIP': archive.path,
        'PMCHAT_UPDATE_DEST': extractDir,
      },
    );
    if (result.exitCode != 0) {
      throw UpdateInstallException('解压失败: ${result.stderr}'.trim());
    }
    final payload = findUpdatePayloadRoot(
      extractDir,
      installation.executableName,
      caseInsensitive: true,
    );
    if (payload == null) {
      throw UpdateInstallException(
        '安装包里没有找到 ${installation.executableName}，不是这个客户端的 Windows 版',
      );
    }
    return StagedDesktopUpdate(
      installation: installation,
      payloadDir: payload,
      stagingDir: staging,
    );
  } catch (_) {
    try {
      await Directory(staging).delete(recursive: true);
    } catch (_) {}
    rethrow;
  }
}

/// Windows 更新助手脚本。参数都从环境变量读：
/// PMCHAT_UPDATE_PID / PAYLOAD / INSTALL_DIR / EXE / STAGING / LOG。
///
/// 只替换新版本里有的顶层文件和目录（用户可能把程序解压在「下载」之类放了别的
/// 东西的目录里，绝不能整目录清空）；被替换的旧文件先挪进备份目录，
/// 任何一步失败就把复制了一半的新文件删掉、旧文件挪回去。最后总会重新启动程序。
const String windowsUpdateHelperScript = r'''
$ErrorActionPreference = 'Stop'
$pidToWait = [int]$env:PMCHAT_UPDATE_PID
$payload = $env:PMCHAT_UPDATE_PAYLOAD
$install = $env:PMCHAT_UPDATE_INSTALL_DIR
$exeName = $env:PMCHAT_UPDATE_EXE
$staging = $env:PMCHAT_UPDATE_STAGING
$logFile = $env:PMCHAT_UPDATE_LOG

function Write-UpdateLog([string]$message) {
  try { Add-Content -LiteralPath $logFile -Value ((Get-Date -Format o) + ' ' + $message) } catch {}
}

function Invoke-WithRetry([scriptblock]$action) {
  # 进程退出后，杀毒软件等可能还短暂占着文件，重试一会儿。
  for ($i = 1; $i -le 40; $i++) {
    try { & $action; return } catch {
      if ($i -eq 40) { throw }
      Start-Sleep -Milliseconds 500
    }
  }
}

Write-UpdateLog "waiting for process $pidToWait"
try { Wait-Process -Id $pidToWait -Timeout 120 -ErrorAction SilentlyContinue } catch {}

$backup = Join-Path $install ('.pmchat-update-backup-' + (Get-Date -Format 'yyyyMMddHHmmss'))
$movedAside = New-Object System.Collections.Generic.List[string]
$copied = New-Object System.Collections.Generic.List[string]
$ok = $false
try {
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $payload -Force) {
    $name = $item.Name
    $target = Join-Path $install $name
    if (Test-Path -LiteralPath $target) {
      Invoke-WithRetry { Move-Item -LiteralPath $target -Destination (Join-Path $backup $name) -Force }
      $movedAside.Add($name)
    }
    $copied.Add($name)
    Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
  }
  $ok = $true
  Write-UpdateLog 'update applied'
} catch {
  Write-UpdateLog ('update failed, rolling back: ' + $_)
  foreach ($name in $copied) {
    $target = Join-Path $install $name
    try {
      if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    } catch { Write-UpdateLog ('cannot remove new ' + $name + ': ' + $_) }
  }
  foreach ($name in $movedAside) {
    try {
      Move-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $install $name) -Force
    } catch { Write-UpdateLog ('cannot restore ' + $name + ': ' + $_) }
  }
}

# 成功，或回滚后备份目录已经空了，就删掉备份目录；否则留着给人工恢复。
if ($ok -or -not (Get-ChildItem -LiteralPath $backup -Force -ErrorAction SilentlyContinue)) {
  Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
Start-Process -FilePath (Join-Path $install $exeName) -WorkingDirectory $install
''';

/// 启动 Windows 更新助手（独立进程，本进程退出后它继续跑）。
Future<void> launchWindowsUpdateHelper(
  StagedDesktopUpdate staged, {
  required int processId,
  required String logPath,
  UpdateProcessStarter start = Process.start,
}) async {
  final script = File(p.join(staged.stagingDir, 'apply-update.ps1'));
  // 带 BOM 的 UTF-8：Windows PowerShell 5.1 才会按 UTF-8 读脚本。
  await script.writeAsBytes(
    [0xEF, 0xBB, 0xBF, ...utf8.encode(windowsUpdateHelperScript)],
  );
  await start(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
    ],
    workingDirectory: staged.stagingDir,
    environment: windowsUpdateHelperEnvironment(
      staged,
      processId: processId,
      logPath: logPath,
    ),
    mode: ProcessStartMode.detached,
  );
}

Map<String, String> windowsUpdateHelperEnvironment(
  StagedDesktopUpdate staged, {
  required int processId,
  required String logPath,
}) {
  return {
    'PMCHAT_UPDATE_PID': '$processId',
    'PMCHAT_UPDATE_PAYLOAD': staged.payloadDir,
    'PMCHAT_UPDATE_INSTALL_DIR': staged.installation.installDir,
    'PMCHAT_UPDATE_EXE': staged.installation.executableName,
    'PMCHAT_UPDATE_STAGING': staged.stagingDir,
    'PMCHAT_UPDATE_LOG': logPath,
  };
}
