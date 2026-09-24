import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:cryptography/dart.dart' as crypto_dart;
import 'package:pointycastle/export.dart' as pc;

import '../crypto/argon2_backend.dart';
import '../crypto/argon2_pointycastle.dart';
import 'e2ee_constants.dart';

export 'e2ee_constants.dart';

/// 私聊端到端加密的密码学部分（纯函数，不碰网络和存储）。
///
/// 方案：
/// * 每个用户一对长期 X25519 身份密钥（可有多个版本，密码被重置后会换新版本）。
/// * 私钥用"登录密码经 Argon2id 派生的包装密钥"做 AES-256-GCM 包装后存到服务器，
///   手机、网页、电脑登录时各自取回、用密码解开——多设备读同一份历史。
///   包装密钥的盐每次包装都由客户端重新随机生成，和登录用的 clientHash 盐不同，
///   输入里还加了域前缀，所以它和服务器在登录时看到的 clientHash 毫无关系。
/// * 每条消息：shared = X25519(我的私钥, 对方公钥)；key = HKDF-SHA256(shared, 随机盐, 上下文)；
///   AES-256-GCM(随机 12 字节 IV)，上下文同时作为 AAD。上下文包含会话 id、发送方和
///   接收方的用户 id 与密钥版本——密文不能被挪到别的会话，也不能被改成"另一个人发的"。
/// * 发送方认证：只有持有发送方私钥或接收方私钥的人才算得出这个共享密钥。服务器两把都没有，
///   伪造不了；接收方看到 AEAD 校验通过、而消息不是自己写的，就只能是对方写的
///   （标准的静态-静态 DH 认证，对第三方可否认）。服务器声称的发送者必须和信封里的一致。
///
/// 局限（诚实地写下来）：没有前向保密（长期密钥泄露能解开全部历史）；公钥目录由服务器提供，
/// 首次见到时信任并在本机钉住（TOFU），恶意服务器在首次交换时仍可能做中间人。
///
/// 全部实现都是纯 Dart（DartX25519 + pointycastle），同步可用，web/wasm、Android、桌面结果一致。

/// 包装私钥用的 Argon2id 参数：和登录哈希同一档（web 上约 0.35 秒）。
const String kE2eeWrapArgon2Params = 'm=65536,t=3,p=1,v=19,hashLen=32';

const String _algorithm = 'X25519-HKDF-SHA256-AES256GCM';
const String _messageContextPrefix = 'pmchat-e2ee/v2';
const String _wrapContextPrefix = 'pmchat-e2ee-keywrap/v1';
const String _wrapPasswordPrefix = 'pmchat-e2ee-keywrap-v1:';
const String _attachmentAlgorithm = 'AES256GCM';

final Random _secureRandom = Random.secure();

Uint8List e2eeRandomBytes(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = _secureRandom.nextInt(256);
  }
  return bytes;
}

class E2eeCryptoException implements Exception {
  const E2eeCryptoException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 包装密钥解不开：密码不对，或者私钥是用以前的密码包的（密码被重置过）。
class E2eeWrongPasswordException extends E2eeCryptoException {
  const E2eeWrongPasswordException() : super('密码不正确，或加密密钥是用以前的密码保护的');
}

/// 一把身份密钥。[privateKey] 是 32 字节 X25519 私钥（已按规范处理过位）。
class E2eeKeyPair {
  const E2eeKeyPair({
    required this.version,
    required this.privateKey,
    required this.publicKey,
  });

  final int version;
  final Uint8List privateKey;
  final Uint8List publicKey;

  String get publicKeyBase64 => base64Encode(publicKey);
}

/// 服务器上保存的一份私钥包装。
class E2eeWrappedKey {
  const E2eeWrappedKey({
    required this.version,
    required this.publicKey,
    required this.wrappedPrivateKey,
    required this.wrapSalt,
    required this.wrapParams,
  });

  final int version;
  final String publicKey;
  final String wrappedPrivateKey;
  final String wrapSalt;
  final String wrapParams;

  Map<String, dynamic> toWrapJson() => {
        'version': version,
        'wrappedPrivateKey': wrappedPrivateKey,
        'wrapSalt': wrapSalt,
        'wrapParams': wrapParams,
      };
}

/// 解开的消息内容。text 消息只有 [text]；附件另有 [attachment]。
class E2eePayload {
  const E2eePayload({
    required this.kind,
    this.text = '',
    this.attachment,
  });

  /// text / image / file / voice / video / audio
  final String kind;
  final String text;
  final E2eeAttachmentKey? attachment;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'text': text,
        if (attachment != null) 'file': attachment!.toJson(),
      };

  static E2eePayload fromJson(Map<String, dynamic> json) {
    final file = json['file'];
    return E2eePayload(
      kind: json['kind']?.toString() ?? 'text',
      text: json['text']?.toString() ?? '',
      attachment: file is Map
          ? E2eeAttachmentKey.fromJson(Map<String, dynamic>.from(file))
          : null,
    );
  }
}

/// 附件的解密信息：随机文件密钥 + 真实文件名/类型/大小，跟着消息密文走。
class E2eeAttachmentKey {
  const E2eeAttachmentKey({
    required this.key,
    required this.nonce,
    required this.name,
    required this.mimeType,
    required this.size,
    this.durationMs,
  });

  final Uint8List key;
  final Uint8List nonce;
  final String name;
  final String mimeType;
  final int size;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
        'alg': _attachmentAlgorithm,
        'key': base64Encode(key),
        'iv': base64Encode(nonce),
        'name': name,
        'mime': mimeType,
        'size': size,
        if (durationMs != null) 'durationMs': durationMs,
      };

  static E2eeAttachmentKey fromJson(Map<String, dynamic> json) {
    if (json['alg'] != _attachmentAlgorithm) {
      throw const E2eeCryptoException('不支持的附件加密格式');
    }
    final key = base64Decode(json['key'].toString());
    final nonce = base64Decode(json['iv'].toString());
    if (key.length != 32 || nonce.length != 12) {
      throw const E2eeCryptoException('附件密钥格式不正确');
    }
    return E2eeAttachmentKey(
      key: key,
      nonce: nonce,
      name: json['name']?.toString() ?? '附件',
      mimeType: json['mime']?.toString() ?? 'application/octet-stream',
      size: (json['size'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt(),
    );
  }
}

/// 解析后的消息信封（还没解密）。头部字段都参与密钥派生和 AAD，改任何一个都解不开。
class E2eeEnvelope {
  const E2eeEnvelope({
    required this.roomId,
    required this.senderId,
    required this.senderKeyVersion,
    required this.recipientId,
    required this.recipientKeyVersion,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
  });

  final String roomId;
  final String senderId;
  final int senderKeyVersion;
  final String recipientId;
  final int recipientKeyVersion;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List ciphertext;

  /// 线上格式：JSON 的 UTF-8 字节再 base64（服务器按字节存）。
  String encode() => base64Encode(utf8.encode(jsonEncode({
        'v': kE2eeEncryptionVersion,
        'alg': _algorithm,
        'room': roomId,
        's': senderId,
        'sk': senderKeyVersion,
        'r': recipientId,
        'rk': recipientKeyVersion,
        'salt': base64Encode(salt),
        'iv': base64Encode(nonce),
        'ct': base64Encode(ciphertext),
      })));

  static E2eeEnvelope? tryParse(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
      if (decoded is! Map ||
          decoded['v'] != kE2eeEncryptionVersion ||
          decoded['alg'] != _algorithm) {
        return null;
      }
      final envelope = E2eeEnvelope(
        roomId: decoded['room'].toString(),
        senderId: decoded['s'].toString(),
        senderKeyVersion: (decoded['sk'] as num).toInt(),
        recipientId: decoded['r'].toString(),
        recipientKeyVersion: (decoded['rk'] as num).toInt(),
        salt: base64Decode(decoded['salt'].toString()),
        nonce: base64Decode(decoded['iv'].toString()),
        ciphertext: base64Decode(decoded['ct'].toString()),
      );
      if (envelope.salt.length != 16 || envelope.nonce.length != 12) {
        return null;
      }
      return envelope;
    } catch (_) {
      return null;
    }
  }

  Uint8List get context => Uint8List.fromList(utf8.encode(
        '$_messageContextPrefix|room=$roomId'
        '|s=$senderId:$senderKeyVersion|r=$recipientId:$recipientKeyVersion',
      ));
}

class E2eeCrypto {
  const E2eeCrypto._();

  static const crypto_dart.DartX25519 _x25519 = crypto_dart.DartX25519();

  /// 新生成一对身份密钥。
  static Future<E2eeKeyPair> generateKeyPair(int version) {
    return keyPairFromPrivate(version, e2eeRandomBytes(32));
  }

  /// 由私钥恢复出完整的一对（解包后校验公钥用）。
  static Future<E2eeKeyPair> keyPairFromPrivate(
    int version,
    Uint8List privateKey,
  ) async {
    final pair = await _x25519.newKeyPairFromSeed(privateKey);
    final publicKey = await pair.extractPublicKey();
    return E2eeKeyPair(
      version: version,
      privateKey: Uint8List.fromList(await pair.extractPrivateKeyBytes()),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// X25519 共享密钥；对方给的是低阶点（结果全 0）时拒绝。
  static Uint8List sharedSecret(E2eeKeyPair mine, Uint8List peerPublicKey) {
    if (peerPublicKey.length != 32) {
      throw const E2eeCryptoException('对方公钥格式不正确');
    }
    final secret = _x25519.sharedSecretSync(
      keyPairData: crypto.SimpleKeyPairData(
        mine.privateKey,
        publicKey: crypto.SimplePublicKey(
          mine.publicKey,
          type: crypto.KeyPairType.x25519,
        ),
        type: crypto.KeyPairType.x25519,
      ),
      remotePublicKey: crypto.SimplePublicKey(
        peerPublicKey,
        type: crypto.KeyPairType.x25519,
      ),
    ) as crypto.SecretKeyData;
    final bytes = Uint8List.fromList(secret.bytes);
    if (bytes.every((b) => b == 0)) {
      throw const E2eeCryptoException('对方公钥无效');
    }
    return bytes;
  }

  /// 加密一条消息。[mine] 是发送方当前密钥，[peerPublicKey] 是接收方当前公钥。
  static String seal({
    required String roomId,
    required String senderId,
    required E2eeKeyPair mine,
    required String recipientId,
    required int recipientKeyVersion,
    required Uint8List peerPublicKey,
    required E2eePayload payload,
  }) {
    final header = E2eeEnvelope(
      roomId: roomId,
      senderId: senderId,
      senderKeyVersion: mine.version,
      recipientId: recipientId,
      recipientKeyVersion: recipientKeyVersion,
      salt: e2eeRandomBytes(16),
      nonce: e2eeRandomBytes(12),
      ciphertext: Uint8List(0),
    );
    final context = header.context;
    final key = hkdfSha256(
      ikm: sharedSecret(mine, peerPublicKey),
      salt: header.salt,
      info: context,
      length: 32,
    );
    final ciphertext = aesGcm(
      encrypt: true,
      key: key,
      nonce: header.nonce,
      aad: context,
      input: Uint8List.fromList(utf8.encode(jsonEncode(payload.toJson()))),
    );
    return E2eeEnvelope(
      roomId: header.roomId,
      senderId: header.senderId,
      senderKeyVersion: header.senderKeyVersion,
      recipientId: header.recipientId,
      recipientKeyVersion: header.recipientKeyVersion,
      salt: header.salt,
      nonce: header.nonce,
      ciphertext: ciphertext,
    ).encode();
  }

  /// 解密。[mine] 是本人在这条消息里用的那把密钥（发送方看 sk，接收方看 rk），
  /// [peerPublicKey] 是另一方对应版本的公钥。校验失败抛 [E2eeCryptoException]。
  static E2eePayload open({
    required E2eeEnvelope envelope,
    required E2eeKeyPair mine,
    required Uint8List peerPublicKey,
  }) {
    final context = envelope.context;
    final key = hkdfSha256(
      ikm: sharedSecret(mine, peerPublicKey),
      salt: envelope.salt,
      info: context,
      length: 32,
    );
    final Uint8List plain;
    try {
      plain = aesGcm(
        encrypt: false,
        key: key,
        nonce: envelope.nonce,
        aad: context,
        input: envelope.ciphertext,
      );
    } catch (_) {
      throw const E2eeCryptoException('消息校验失败');
    }
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map) {
      throw const E2eeCryptoException('消息格式不正确');
    }
    return E2eePayload.fromJson(Map<String, dynamic>.from(decoded));
  }

  /// 用密码包装私钥。盐每次都新生成（绝不用服务器给的盐来包装）。
  static Future<E2eeWrappedKey> wrapPrivateKey({
    required String password,
    required String userId,
    required E2eeKeyPair keyPair,
    String argon2Params = kE2eeWrapArgon2Params,
  }) async {
    final salt = e2eeRandomBytes(16);
    final wrapKey = await deriveWrapKey(
      password: password,
      salt: salt,
      argon2Params: argon2Params,
    );
    return wrapPrivateKeyWithDerivedKey(
      wrapKey: wrapKey,
      salt: salt,
      argon2Params: argon2Params,
      userId: userId,
      keyPair: keyPair,
    );
  }

  /// 同一次改密码里要包好几把，只派生一次包装密钥。
  static E2eeWrappedKey wrapPrivateKeyWithDerivedKey({
    required Uint8List wrapKey,
    required Uint8List salt,
    required String argon2Params,
    required String userId,
    required E2eeKeyPair keyPair,
  }) {
    final iv = e2eeRandomBytes(12);
    final sealed = aesGcm(
      encrypt: true,
      key: wrapKey,
      nonce: iv,
      aad: _wrapContext(userId, keyPair.version, keyPair.publicKeyBase64),
      input: keyPair.privateKey,
    );
    return E2eeWrappedKey(
      version: keyPair.version,
      publicKey: keyPair.publicKeyBase64,
      wrappedPrivateKey: base64Encode([...iv, ...sealed]),
      wrapSalt: base64Encode(salt),
      wrapParams: argon2Params,
    );
  }

  /// 用密码解开服务器上的私钥，并确认它和登记的公钥是一对。
  static Future<E2eeKeyPair> unwrapPrivateKey({
    required String password,
    required String userId,
    required E2eeWrappedKey wrapped,
    Map<String, Uint8List>? derivedKeyCache,
  }) async {
    final cacheKey = '${wrapped.wrapSalt}|${wrapped.wrapParams}';
    final wrapKey = derivedKeyCache?[cacheKey] ??
        await deriveWrapKey(
          password: password,
          salt: base64Decode(wrapped.wrapSalt),
          argon2Params: wrapped.wrapParams,
        );
    derivedKeyCache?[cacheKey] = wrapKey;
    final blob = base64Decode(wrapped.wrappedPrivateKey);
    if (blob.length != 12 + 32 + 16) {
      throw const E2eeCryptoException('加密私钥格式不正确');
    }
    final Uint8List privateKey;
    try {
      privateKey = aesGcm(
        encrypt: false,
        key: wrapKey,
        nonce: Uint8List.sublistView(blob, 0, 12),
        aad: _wrapContext(userId, wrapped.version, wrapped.publicKey),
        input: Uint8List.sublistView(blob, 12),
      );
    } catch (_) {
      throw const E2eeWrongPasswordException();
    }
    final pair = await keyPairFromPrivate(wrapped.version, privateKey);
    if (pair.publicKeyBase64 != wrapped.publicKey) {
      throw const E2eeCryptoException('加密私钥和公钥不匹配');
    }
    return pair;
  }

  static Future<Uint8List> deriveWrapKey({
    required String password,
    required Uint8List salt,
    required String argon2Params,
  }) {
    final match = RegExp(r'^m=(\d+),t=(\d+),p=(\d+),v=(\d+),hashLen=(\d+)$')
        .firstMatch(argon2Params);
    if (match == null || match.group(5) != '32') {
      throw const E2eeCryptoException('密钥派生参数格式不正确');
    }
    return deriveArgon2id(Argon2idRequest(
      // 域前缀：即使盐碰巧相同，也和登录用的 clientHash 不是同一个值。
      password:
          Uint8List.fromList(utf8.encode('$_wrapPasswordPrefix$password')),
      salt: salt,
      memoryKb: int.parse(match.group(1)!),
      iterations: int.parse(match.group(2)!),
      parallelism: int.parse(match.group(3)!),
      version: int.parse(match.group(4)!),
      hashLen: 32,
    ));
  }

  /// 附件：随机文件密钥加密文件字节。web 上走 WebCrypto，快；返回 密文||标签。
  static Future<({Uint8List ciphertext, E2eeAttachmentKey key})>
      encryptAttachment({
    required Uint8List bytes,
    required String name,
    required String mimeType,
    int? durationMs,
  }) async {
    final key = e2eeRandomBytes(32);
    final nonce = e2eeRandomBytes(12);
    final box = await crypto.AesGcm.with256bits().encrypt(
      bytes,
      secretKey: crypto.SecretKey(key),
      nonce: nonce,
    );
    return (
      ciphertext: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
      key: E2eeAttachmentKey(
        key: key,
        nonce: nonce,
        name: name,
        mimeType: mimeType,
        size: bytes.length,
        durationMs: durationMs,
      ),
    );
  }

  static Future<Uint8List> decryptAttachment({
    required Uint8List ciphertext,
    required E2eeAttachmentKey key,
  }) async {
    if (ciphertext.length < 16) {
      throw const E2eeCryptoException('附件已损坏');
    }
    try {
      final plain = await crypto.AesGcm.with256bits().decrypt(
        crypto.SecretBox(
          Uint8List.sublistView(ciphertext, 0, ciphertext.length - 16),
          nonce: key.nonce,
          mac: crypto.Mac(
              Uint8List.sublistView(ciphertext, ciphertext.length - 16)),
        ),
        secretKey: crypto.SecretKey(key.key),
      );
      return Uint8List.fromList(plain);
    } on crypto.SecretBoxAuthenticationError {
      throw const E2eeCryptoException('附件校验失败');
    }
  }

  /// RFC 5869 HKDF-SHA256。
  static Uint8List hkdfSha256({
    required Uint8List ikm,
    required Uint8List salt,
    required Uint8List info,
    required int length,
  }) {
    final prk = _hmacSha256(salt.isEmpty ? Uint8List(32) : salt, ikm);
    final output = BytesBuilder(copy: false);
    var previous = Uint8List(0);
    var counter = 1;
    while (output.length < length) {
      previous = _hmacSha256(
        prk,
        Uint8List.fromList([...previous, ...info, counter]),
      );
      output.add(previous);
      counter++;
    }
    return Uint8List.fromList(output.toBytes().sublist(0, length));
  }

  static Uint8List aesGcm({
    required bool encrypt,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List input,
  }) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        encrypt,
        pc.AEADParameters(pc.KeyParameter(key), 128, nonce, aad),
      );
    return cipher.process(input);
  }

  static Uint8List _hmacSha256(Uint8List key, Uint8List data) {
    final hmac = pc.HMac(pc.SHA256Digest(), 64)..init(pc.KeyParameter(key));
    return hmac.process(data);
  }

  static Uint8List _wrapContext(String userId, int version, String publicKey) {
    return Uint8List.fromList(utf8.encode(
      '$_wrapContextPrefix|user=$userId|version=$version|pub=$publicKey',
    ));
  }
}
