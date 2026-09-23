import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'argon2_pointycastle.dart';

/// 自托管的 hash-wasm（MIT），不走第三方 CDN，国内也能加载。
const _hashWasmScript = 'vendor/hash-wasm-argon2-4.12.0.umd.min.js';

@JS('hashwasm')
external _HashWasm? get _hashWasm;

extension type _HashWasm(JSObject _) implements JSObject {
  external JSPromise<JSUint8Array> argon2id(_Argon2Options options);
}

extension type _Argon2Options._(JSObject _) implements JSObject {
  external factory _Argon2Options({
    JSUint8Array password,
    JSUint8Array salt,
    int parallelism,
    int iterations,
    int memorySize,
    int hashLength,
    String outputType,
  });
}

Future<void>? _loading;

/// 登录页一出现就可以先把脚本拉下来，按登录时不用再等。
Future<void> warmUpArgon2id() async {
  try {
    await _ensureHashWasm();
  } catch (_) {
    // 真正计算时还会再试一次，失败就走兜底实现。
  }
}

/// web 端用 WebAssembly 版 Argon2id：64MB/3 轮约 0.35 秒，
/// 而纯 Dart 编译到 web 要 40 秒以上并且卡死主线程。
/// 两者输出逐字节一致，已有账号的密码哈希不受影响。
Future<Uint8List> deriveArgon2id(Argon2idRequest request) async {
  // hash-wasm 只实现 Argon2 v1.3 (0x13 = 19)。
  if (request.version == 19) {
    try {
      await _ensureHashWasm();
      final hashWasm = _hashWasm;
      if (hashWasm != null) {
        final result = await hashWasm
            .argon2id(_Argon2Options(
              password: request.password.toJS,
              salt: request.salt.toJS,
              parallelism: request.parallelism,
              iterations: request.iterations,
              memorySize: request.memoryKb,
              hashLength: request.hashLen,
              outputType: 'binary',
            ))
            .toDart;
        return result.toDart;
      }
    } catch (_) {
      // 落到下面的纯 Dart 实现：慢，但结果一样，至少能登录。
    }
  }
  return argon2idWithPointycastle(request);
}

Future<void> _ensureHashWasm() {
  if (_hashWasm != null) return Future.value();
  return _loading ??= _injectScript();
}

Future<void> _injectScript() {
  final completer = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = _hashWasmScript
    ..async = true;
  script.onload = ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  script.onerror = ((web.Event _) {
    _loading = null;
    script.remove();
    if (!completer.isCompleted) {
      completer.completeError(StateError('Argon2 脚本加载失败'));
    }
  }).toJS;
  web.document.head?.append(script);
  return completer.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () {
      _loading = null;
      throw TimeoutException('Argon2 脚本加载超时');
    },
  );
}
