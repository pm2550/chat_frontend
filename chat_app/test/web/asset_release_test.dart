import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_web_release_manifest.dart' as release;

void main() {
  test('release ships matching versioned fonts and asset manifests', () async {
    final root = await Directory.systemTemp.createTemp('pmchat-asset-test-');
    addTearDown(() => root.delete(recursive: true));
    const paths = [
      'index.html',
      'flutter.js',
      'flutter_bootstrap.js',
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
      'assets/images/example.webp',
      'assets/packages/icons/font.ttf',
      'pmchat_service_worker.js',
      'main.dart.js',
      'main.dart.mjs',
      'main.dart.wasm',
      'canvaskit/canvaskit.js',
      'canvaskit/canvaskit.wasm',
      'canvaskit/chromium/canvaskit.js',
      'canvaskit/chromium/canvaskit.wasm',
      'canvaskit/skwasm.js',
      'canvaskit/skwasm.wasm',
      'canvaskit/skwasm_heavy.js',
      'canvaskit/skwasm_heavy.wasm',
      'canvaskit/wimp.js',
      'canvaskit/wimp.wasm',
    ];
    for (final path in paths) {
      final file = File('${root.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsString('$path __PMCHAT_BUILD_ID__');
    }
    await release.main([root.path]);
    final manifest = jsonDecode(await File(
      '${root.path}/pmchat_build_manifest.json',
    ).readAsString()) as Map<String, dynamic>;
    final id = manifest['buildId'] as String;
    expect(id, matches(RegExp(r'^[a-f0-9]{20}$')));
    for (final path in paths.where((path) => path.startsWith('assets/'))) {
      final original = await File('${root.path}/$path').readAsBytes();
      final versioned =
          await File('${root.path}/pmchat-assets/$id/$path').readAsBytes();
      expect(versioned, original);
      final record = (manifest['requiredAssets'] as List).singleWhere(
        (asset) => asset['url'] == '/pmchat-assets/$id/$path',
      );
      expect(record['bytes'], original.length);
      expect(record['sha256'], sha256.convert(original).toString());
    }
    for (final path in [
      'index.html',
      'flutter_bootstrap.js',
      'pmchat_service_worker.js'
    ]) {
      final contents = await File('${root.path}/$path').readAsString();
      expect(contents, contains(id));
      expect(contents, isNot(contains('__PMCHAT_BUILD_ID__')));
    }
  });

  test('loader and worker keep release assets coherent and leave APIs alone',
      () async {
    final result = await Process.run('node', [
      '-e',
      r'''
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const id = '0123456789abcdef0123';
const bootstrap = fs.readFileSync('web/flutter_bootstrap.js', 'utf8')
  .replace(/\{\{flutter_(js|build_config)\}\}/g, '');
for (const versioned of [false, true]) {
  let loaded;
  const flutter = {
    buildConfig: {builds: [{mainJsPath:'main.dart.js'},
      {mainWasmPath:'main.dart.wasm',jsSupportRuntimePath:'main.dart.mjs'}]},
    loader: {load: options => { loaded = options; }},
  };
  vm.runInNewContext(versioned ? bootstrap.replaceAll('__PMCHAT_BUILD_ID__', id) : bootstrap,
    {window:{_flutter:flutter,__PMCHAT_BUILD_STAMP:id},_flutter:flutter});
  assert.equal(loaded.config.assetBase, versioned ? `pmchat-assets/${id}/` : undefined);
  assert.equal(flutter.buildConfig.builds[0].mainJsPath, `main.dart.js?v=${id}`);
}
const listeners = {};
const requests = [];
const stores = new Map();
const scope = {
  URL, Request, Response, console,
  self: {location:{origin:'https://chat.example'},addEventListener:(name,cb)=>listeners[name]=cb},
  caches: {open:async name => {
    if (!stores.has(name)) stores.set(name,new Map());
    const store=stores.get(name);
    const key=value=>new URL(typeof value==='string'?value:value.url,'https://chat.example').pathname;
    return {match:async value=>store.get(key(value))?.clone(),
      put:async (value,response)=>store.set(key(value),response.clone())};
  }},
  fetch: async request => {
    requests.push(typeof request==='string'?request:request.url);
    return new Response('font-data');
  },
};
vm.createContext(scope);
vm.runInContext(fs.readFileSync('web/pmchat_service_worker.js','utf8')
  .replaceAll('__PMCHAT_BUILD_ID__',id),scope);
(async()=>{
  const path=`/pmchat-assets/${id}/assets/fonts/MaterialIcons-Regular.otf`;
  async function dispatch(url, method='GET') {
    let response;
    listeners.fetch({request:new Request(url,{method}),respondWith:value=>{response=value;}});
    return await response;
  }
  const first=await dispatch('https://chat.example'+path);
  assert.equal(await first.text(),'font-data');
  assert.equal(requests.at(-1),'https://chat.example'+path+'?v='+id);
  await dispatch('https://chat.example'+path);
  assert.equal(requests.length,1,'second request is served from the release cache');
  await dispatch('https://chat.example/flutter_bootstrap.js?v=explicit');
  assert.equal(requests.at(-1),'https://chat.example/flutter_bootstrap.js?v=explicit');
  for (const [url,method] of [
    ['https://chat.example/api/profile','GET'],
    ['https://chat.example/actuator/health','GET'],
    ['https://other.example/assets/font.otf','GET'],
    ['https://chat.example/assets/upload','POST'],
  ]) assert.equal(await dispatch(url,method),undefined);
  assert.equal(requests.length,2);
})().catch(error=>{console.error(error);process.exitCode=1;});
'''
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
