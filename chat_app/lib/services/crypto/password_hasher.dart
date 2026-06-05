import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/argon2.dart';

class ClientPasswordHash {
  const ClientPasswordHash({
    required this.clientHash,
    required this.clientSalt,
    required this.argon2Params,
  });

  final String clientHash;
  final String clientSalt;
  final String argon2Params;
}

class ClientSaltParams {
  const ClientSaltParams({
    required this.salt,
    required this.argon2Params,
    required this.scheme,
  });

  final String salt;
  final String argon2Params;
  final String scheme;

  bool get isClientArgon2 => scheme == PasswordHasher.clientScheme;
}

class PasswordHasher {
  static const legacyScheme = 'BCRYPT_LEGACY';
  static const clientScheme = 'CLIENT_ARGON2_BCRYPT';
  static const defaultArgon2Params = 'm=65536,t=3,p=1,v=19,hashLen=32';

  static final _secureRandom = Random.secure();
  static final _paramsPattern = RegExp(
    r'^m=(\d+),t=(\d+),p=(\d+),v=(\d+),hashLen=(\d+)$',
  );

  Future<ClientPasswordHash> hashNewPassword(String password) async {
    final salt = _randomBytes(16);
    final saltText = _base64UrlNoPadding(salt);
    final clientHash = await hashWithSalt(
      password: password,
      salt: saltText,
      argon2Params: defaultArgon2Params,
    );
    return ClientPasswordHash(
      clientHash: clientHash,
      clientSalt: saltText,
      argon2Params: defaultArgon2Params,
    );
  }

  Future<String> hashWithSalt({
    required String password,
    required String salt,
    required String argon2Params,
  }) async {
    final parsed = _parseParams(argon2Params);
    final generator = Argon2BytesGenerator()
      ..init(Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        _base64UrlDecode(salt),
        desiredKeyLength: parsed.hashLen,
        iterations: parsed.iterations,
        memory: parsed.memoryKb,
        lanes: parsed.parallelism,
        version: parsed.version,
      ));

    final output = Uint8List(parsed.hashLen);
    final input = Uint8List.fromList(utf8.encode(password));
    generator.deriveKey(input, 0, output, 0);
    _zero(input);
    return _base64UrlNoPadding(output);
  }

  _Argon2Params _parseParams(String value) {
    final match = _paramsPattern.firstMatch(value);
    if (match == null) {
      throw ArgumentError('Invalid Argon2 params');
    }
    return _Argon2Params(
      memoryKb: int.parse(match.group(1)!),
      iterations: int.parse(match.group(2)!),
      parallelism: int.parse(match.group(3)!),
      version: int.parse(match.group(4)!),
      hashLen: int.parse(match.group(5)!),
    );
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _secureRandom.nextInt(256)),
    );
  }

  Uint8List _base64UrlDecode(String value) {
    final normalized =
        value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
    return base64Url.decode(normalized);
  }

  String _base64UrlNoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void _zero(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }
}

class _Argon2Params {
  const _Argon2Params({
    required this.memoryKb,
    required this.iterations,
    required this.parallelism,
    required this.version,
    required this.hashLen,
  });

  final int memoryKb;
  final int iterations;
  final int parallelism;
  final int version;
  final int hashLen;
}
