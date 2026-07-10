import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _buildIdMarker = '__PMCHAT_BUILD_ID__';

Future<void> main(List<String> arguments) async {
  final root = Directory(arguments.isEmpty ? 'build/web' : arguments.first);
  if (!root.existsSync()) {
    stderr.writeln('Web build directory does not exist: ${root.path}');
    exitCode = 2;
    return;
  }

  final requiredPaths = <String>[
    'index.html',
    'flutter.js',
    'flutter_bootstrap.js',
    'main.dart.js',
    'manifest.json',
    'version.json',
    'favicon.png',
    'icons/Icon-192.png',
    'icons/Icon-512.png',
    'icons/Icon-maskable-192.png',
    'icons/Icon-maskable-512.png',
    'assets/AssetManifest.bin',
    'assets/AssetManifest.bin.json',
    'assets/FontManifest.json',
    'assets/fonts/MaterialIcons-Regular.otf',
    'pmchat_service_worker.js',
    'canvaskit/canvaskit.js',
    'canvaskit/canvaskit.wasm',
    'canvaskit/chromium/canvaskit.js',
    'canvaskit/chromium/canvaskit.wasm',
  ];
  _requireFiles(root, requiredPaths);
  final seed = StringBuffer();
  for (final path in requiredPaths) {
    seed.write(path);
    seed.write(await _digest(File('${root.path}/$path')));
  }
  final buildId =
      sha256.convert(utf8.encode(seed.toString())).toString().substring(0, 20);

  for (final path in ['index.html', 'pmchat_service_worker.js']) {
    final file = File('${root.path}/$path');
    final content = await file.readAsString();
    await file.writeAsString(content.replaceAll(_buildIdMarker, buildId));
  }

  final assets = <Map<String, Object>>[];
  for (final path in requiredPaths) {
    final file = File('${root.path}/$path');
    assets.add({
      'url': '/$path',
      'sha256': await _digest(file),
      'bytes': await file.length(),
    });
  }
  final manifest = <String, Object>{
    'schemaVersion': 1,
    'buildId': buildId,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'requiredAssets': assets,
  };
  const encoder = JsonEncoder.withIndent('  ');
  await File('${root.path}/pmchat_build_manifest.json')
      .writeAsString('${encoder.convert(manifest)}\n');
  await File('${root.path}/.last_build_id').writeAsString('$buildId\n');
  stdout.writeln(buildId);
}

void _requireFiles(Directory root, List<String> paths) {
  final missing = paths
      .where((path) => !File('${root.path}/$path').existsSync())
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw StateError(
        'Release is missing required assets: ${missing.join(', ')}');
  }
}

Future<String> _digest(File file) async {
  return sha256.bind(file.openRead()).first.then((digest) => digest.toString());
}
