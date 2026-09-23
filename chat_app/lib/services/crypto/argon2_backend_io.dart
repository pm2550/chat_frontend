import 'dart:isolate';
import 'dart:typed_data';

import 'argon2_pointycastle.dart';

/// 原生平台：放到后台 isolate 里算，登录时界面不会被卡住。
Future<Uint8List> deriveArgon2id(Argon2idRequest request) {
  return Isolate.run(() => argon2idWithPointycastle(request));
}

Future<void> warmUpArgon2id() async {}
