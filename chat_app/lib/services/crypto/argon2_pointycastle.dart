import 'dart:typed_data';

import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/argon2.dart';

/// Argon2 的参数，和服务端存的 `m=...,t=...,p=...,v=...,hashLen=...` 一一对应。
class Argon2idRequest {
  const Argon2idRequest({
    required this.password,
    required this.salt,
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
    required this.version,
    required this.hashLen,
  });

  final Uint8List password;
  final Uint8List salt;
  final int memoryKb;
  final int iterations;
  final int parallelism;
  final int version;
  final int hashLen;
}

/// 纯 Dart 的 Argon2id。原生平台够快；编译到 web 后极慢（64MB 参数要几十秒），
/// web 端只作为 WebAssembly 实现加载失败时的兜底。
Uint8List argon2idWithPointycastle(Argon2idRequest request) {
  final generator = Argon2BytesGenerator()
    ..init(Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      request.salt,
      desiredKeyLength: request.hashLen,
      iterations: request.iterations,
      memory: request.memoryKb,
      lanes: request.parallelism,
      version: request.version,
    ));
  final output = Uint8List(request.hashLen);
  generator.deriveKey(request.password, 0, output, 0);
  return output;
}
