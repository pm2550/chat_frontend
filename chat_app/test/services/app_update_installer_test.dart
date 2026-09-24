import 'dart:io';

import 'package:chat_app/models/app_version.dart';
import 'package:chat_app/services/app_update_installer.dart';
import 'package:chat_app/services/update_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('artifact kind and install mode', () {
    test('recognises every artifact CI publishes', () {
      expect(updateArtifactKindFor('/api/v1/app/download/linux/pm-chat-linux-x64-v1.2.0-12000.tar.gz'),
          UpdateArtifactKind.tarGz);
      expect(updateArtifactKindFor('https://x/download/windows/pm-chat-windows-x64-v1.zip?x=1'),
          UpdateArtifactKind.zip);
      expect(updateArtifactKindFor('/download/android/pm-chat-android-v1.apk'),
          UpdateArtifactKind.apk);
      expect(updateArtifactKindFor('/download/ios/pm-chat-ios-v1.ipa'),
          UpdateArtifactKind.ipa);
      expect(updateArtifactKindFor('/download/x/readme'), UpdateArtifactKind.unknown);
    });

    test('Linux replaces the tar.gz install in place instead of unzipping it', () {
      expect(
        updateInstallModeFor(TargetPlatform.linux, UpdateArtifactKind.tarGz),
        UpdateInstallMode.replaceInstallation,
      );
    });

    test('Windows replaces in place, macOS saves to Downloads', () {
      expect(updateInstallModeFor(TargetPlatform.windows, UpdateArtifactKind.zip),
          UpdateInstallMode.replaceInstallation);
      expect(updateInstallModeFor(TargetPlatform.macOS, UpdateArtifactKind.zip),
          UpdateInstallMode.saveToDownloads);
    });

    test('iOS never downloads the .ipa, Android keeps the APK installer', () {
      expect(updateInstallModeFor(TargetPlatform.iOS, UpdateArtifactKind.ipa),
          UpdateInstallMode.openLink);
      expect(updateInstallModeFor(TargetPlatform.android, UpdateArtifactKind.apk),
          UpdateInstallMode.androidApk);
    });

    test('mismatched artifacts fall back to the download page', () {
      expect(updateInstallModeFor(TargetPlatform.linux, UpdateArtifactKind.zip),
          UpdateInstallMode.unsupported);
      expect(updateInstallModeFor(TargetPlatform.windows, UpdateArtifactKind.tarGz),
          UpdateInstallMode.unsupported);
    });
  });

  group('install dir detection', () {
    test('Windows install dir is where the running exe lives', () {
      final install = DesktopInstallation.fromExecutable(
        r'D:\Tools\PM chat\chat_app.exe',
        windows: true,
      );
      expect(install.installDir, r'D:\Tools\PM chat');
      expect(install.executableName, 'chat_app.exe');
      expect(install.executablePath, r'D:\Tools\PM chat\chat_app.exe');
    });

    test('Linux stages next to the bundle so the swap is a rename', () {
      final install = DesktopInstallation.fromExecutable(
        '/home/u/apps/bundle/chat_app',
        windows: false,
      );
      expect(install.installDir, '/home/u/apps/bundle');
      expect(install.installParent, '/home/u/apps');
      expect(install.stagingDirFor('1'), '/home/u/apps/.bundle.update-1');
      expect(install.backupDirFor('1'), '/home/u/apps/.bundle.old-1');
      expect(install.isLeftoverSibling('.bundle.old-1'), isTrue);
      expect(install.isLeftoverSibling('bundle'), isFalse);
      expect(install.isLeftoverSibling('.other.old-1'), isFalse);
    });
  });

  group('download verification', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('pmchat-verify'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('accepts a matching size and sha256', () async {
      final file = File(p.join(temp.path, 'a.zip'))..writeAsStringSync('abc');
      await verifyDownloadedArtifact(
        file,
        expectedSize: 3,
        expectedSha256:
            'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD',
      );
    });

    test('rejects a truncated download', () async {
      final file = File(p.join(temp.path, 'a.zip'))..writeAsStringSync('ab');
      expect(
        () => verifyDownloadedArtifact(file, expectedSize: 3),
        throwsA(isA<UpdateInstallException>()),
      );
    });

    test('rejects a tampered download', () async {
      final file = File(p.join(temp.path, 'a.zip'))..writeAsStringSync('abd');
      expect(
        () => verifyDownloadedArtifact(
          file,
          expectedSize: 3,
          expectedSha256:
              'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
        throwsA(isA<UpdateInstallException>()),
      );
    });

    test('sha256 from the version API reaches the update model', () {
      expect(
        AppVersionCheck.fromJson({'updateAvailable': true, 'sha256': 'ab'}).sha256,
        'ab',
      );
      expect(
        UpdateService.checkFromWebSocketPayload({'sha256': 'cd'}).sha256,
        'cd',
      );
    });
  });

  group('payload detection', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('pmchat-payload'));
    tearDown(() => temp.deleteSync(recursive: true));

    void makeBundle(String dir, String exe) {
      Directory(p.join(dir, 'data', 'flutter_assets')).createSync(recursive: true);
      File(p.join(dir, exe)).writeAsStringSync('bin');
    }

    test('finds the bundle/ folder inside the Linux tarball', () {
      makeBundle(p.join(temp.path, 'bundle'), 'chat_app');
      expect(findUpdatePayloadRoot(temp.path, 'chat_app'),
          p.join(temp.path, 'bundle'));
    });

    test('finds a Windows zip whose files sit at the root', () {
      makeBundle(temp.path, 'Chat_App.exe');
      expect(
        findUpdatePayloadRoot(temp.path, 'chat_app.exe', caseInsensitive: true),
        temp.path,
      );
    });

    test('rejects archives that are not this app', () {
      makeBundle(p.join(temp.path, 'bundle'), 'other_app');
      expect(findUpdatePayloadRoot(temp.path, 'chat_app'), isNull);
    });
  });

  group('Linux in-place update (real tar, real rename, real relaunch)', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('pmchat-linux'));
    tearDown(() => temp.deleteSync(recursive: true));

    Future<File> buildTarball(String version, String marker) async {
      final src = Directory(p.join(temp.path, 'build-$version', 'bundle'));
      Directory(p.join(src.path, 'data', 'flutter_assets'))
          .createSync(recursive: true);
      File(p.join(src.path, 'data', 'flutter_assets', 'VERSION'))
          .writeAsStringSync(version);
      final exe = File(p.join(src.path, 'chat_app'))
        ..writeAsStringSync('#!/bin/sh\necho "$version" > "$marker"\n');
      await Process.run('chmod', ['+x', exe.path]);
      final tarball = File(p.join(temp.path, 'pm-chat-linux-x64-v$version.tar.gz'));
      final result = await Process.run(
        'tar',
        ['-C', p.dirname(src.path), '-czf', tarball.path, 'bundle'],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return tarball;
    }

    test('stages, swaps the running bundle and starts the new version',
        () async {
      final marker = p.join(temp.path, 'launched.txt');
      final installRoot = Directory(p.join(temp.path, 'apps'))..createSync();
      // "当前安装"：解压 1.0 的包，就像用户第一次安装那样。
      final v1 = await buildTarball('1.0', marker);
      await Process.run('tar', ['-xzf', v1.path, '-C', installRoot.path]);
      File(p.join(installRoot.path, 'notes.txt')).writeAsStringSync('keep me');
      final installation = DesktopInstallation.fromExecutable(
        p.join(installRoot.path, 'bundle', 'chat_app'),
        windows: false,
      );

      final v2 = await buildTarball('2.0', marker);
      final staged = await stageLinuxUpdate(
        archive: v2,
        installation: installation,
      );
      // 暂存时还没动当前安装。
      expect(
        File(p.join(installation.installDir, 'data', 'flutter_assets', 'VERSION'))
            .readAsStringSync(),
        '1.0',
      );

      await applyLinuxUpdate(staged);

      expect(
        File(p.join(installation.installDir, 'data', 'flutter_assets', 'VERSION'))
            .readAsStringSync(),
        '2.0',
      );
      // 同目录下用户自己的文件不受影响。
      expect(File(p.join(installRoot.path, 'notes.txt')).readAsStringSync(),
          'keep me');
      // 新版本真的被拉起来了（脚本写了 marker）。
      for (var i = 0; i < 50 && !File(marker).existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(File(marker).readAsStringSync().trim(), '2.0');

      // 新版本启动后清理旧目录和暂存目录。
      await cleanupLinuxUpdateLeftovers(installation);
      final leftovers = installRoot
          .listSync()
          .map((e) => p.basename(e.path))
          .where((name) => name.startsWith('.'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('rolls back to the old bundle when the new one cannot start',
        () async {
      final installRoot = Directory(p.join(temp.path, 'apps'))..createSync();
      final v1 = await buildTarball('1.0', p.join(temp.path, 'unused'));
      await Process.run('tar', ['-xzf', v1.path, '-C', installRoot.path]);
      final installation = DesktopInstallation.fromExecutable(
        p.join(installRoot.path, 'bundle', 'chat_app'),
        windows: false,
      );
      final v2 = await buildTarball('2.0', p.join(temp.path, 'unused'));
      final staged =
          await stageLinuxUpdate(archive: v2, installation: installation);

      await expectLater(
        applyLinuxUpdate(
          staged,
          start: (executable, arguments,
                  {workingDirectory, environment, mode = ProcessStartMode.normal}) =>
              throw const ProcessException('chat_app', [], 'boom'),
        ),
        throwsA(isA<UpdateInstallException>()),
      );
      expect(
        File(p.join(installation.installDir, 'data', 'flutter_assets', 'VERSION'))
            .readAsStringSync(),
        '1.0',
      );
    });

    test('refuses a tarball that does not contain this app', () async {
      final installRoot = Directory(p.join(temp.path, 'apps'))..createSync();
      final v1 = await buildTarball('1.0', p.join(temp.path, 'unused'));
      await Process.run('tar', ['-xzf', v1.path, '-C', installRoot.path]);
      final installation = DesktopInstallation.fromExecutable(
        p.join(installRoot.path, 'bundle', 'other_name'),
        windows: false,
      );

      await expectLater(
        stageLinuxUpdate(archive: v1, installation: installation),
        throwsA(isA<UpdateInstallException>()),
      );
      // 失败的暂存目录已清掉。
      expect(
        installRoot.listSync().map((e) => p.basename(e.path)),
        ['bundle'],
      );
    });
  });

  group('Windows update helper', () {
    test('helper waits for the app, never mirrors the folder, and relaunches',
        () {
      const script = windowsUpdateHelperScript;
      expect(script, contains(r'Wait-Process -Id $pidToWait'));
      // 只替换新版本里有的条目，绝不能 robocopy /MIR 或清空整个目录。
      expect(script, isNot(contains('/MIR')));
      expect(script, contains(r'Get-ChildItem -LiteralPath $payload'));
      expect(script, contains('rolling back'));
      expect(script, contains(r'Start-Process -FilePath (Join-Path $install $exeName)'));
    });

    test('helper gets every path through environment variables', () {
      const staged = StagedDesktopUpdate(
        installation: DesktopInstallation(
          installDir: r"C:\Users\o'neil\PM chat",
          executableName: 'chat_app.exe',
          windows: true,
        ),
        payloadDir: r'C:\Temp\pmchat-update\1\payload',
        stagingDir: r'C:\Temp\pmchat-update\1',
      );
      final env = windowsUpdateHelperEnvironment(
        staged,
        processId: 4242,
        logPath: r'C:\Temp\pmchat-update.log',
      );
      expect(env['PMCHAT_UPDATE_PID'], '4242');
      expect(env['PMCHAT_UPDATE_INSTALL_DIR'], r"C:\Users\o'neil\PM chat");
      expect(env['PMCHAT_UPDATE_EXE'], 'chat_app.exe');
      for (final key in RegExp(r'\$env:(PMCHAT_UPDATE_\w+)')
          .allMatches(windowsUpdateHelperScript)
          .map((m) => m.group(1))) {
        expect(env.containsKey(key), isTrue, reason: '$key is not provided');
      }
    });
  });
}
