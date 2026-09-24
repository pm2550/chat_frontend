import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'e2ee_crypto.dart';

/// 端到端加密恢复码（纯函数，不碰网络和存储）。
///
/// 为什么要有：身份私钥在服务器上只以"登录密码包装"的形式存在，忘记密码或被管理员重置后，
/// 旧的包装就再也解不开，加密历史随之丢失。恢复码是同一把私钥的第二份包装的钥匙。
///
/// 方案：
/// * 恢复码在客户端用 CSPRNG 生成：26 个 Crockford base32 字符（130 位随机）+ 2 个校验字符，
///   显示成 7 组、每组 4 个字符。Crockford 字母表没有 I、L、O、U，输入时把 O 当 0、I/L 当 1，
///   大小写、空格、连字符都不计较。
/// * 校验字符 = SHA-256(域前缀 || 26 个数据字符) 的前 10 位。只用来尽早提示"输错了"：
///   单个字符写错、相邻两个字符写反，漏检的概率都约为 1/1024；漏掉的那一点点
///   还会在 AES-GCM 解包时失败，同样提示"恢复码不正确"。
/// * 包装密钥 = HKDF-SHA256(ikm = 26 个数据字符, salt = 随机 16 字节, info = 域前缀 + 用户 id)。
///   这里不用 Argon2：Argon2 的作用是让"低熵的密码"难以暴力猜，而恢复码本身有 130 位随机性，
///   拿到数据库的人也不可能穷举，慢哈希只会白白拖慢手机和网页。
/// * 包装 = AES-256-GCM(随机 12 字节 IV)，AAD 里有用户 id、密钥版本和公钥（域前缀和密码包装不同），
///   密文不能被挪给别的用户、别的版本，也不能和密码包装互换。
/// * 服务器只存 base64(iv || 密文)、盐和参数名 [kE2eeRecoveryWrapParams]；恢复码从不离开这台设备
///   （"发送到我的邮箱"是用本机的邮件应用发给自己，不经过我们的服务器）。

/// 服务器上记的派生参数名（后端 E2eeKeyService.RECOVERY_WRAP_PARAMS 只认这一种）。
const String kE2eeRecoveryWrapParams = 'hkdf-sha256,v=1';

/// Crockford base32 字母表。
const String kCrockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

const int _dataChars = 26;
const int _checkChars = 2;
const int _groupSize = 4;
const String _checkPrefix = 'pmchat-e2ee-recovery-check/v1|';
const String _hkdfInfoPrefix = 'pmchat-e2ee-recovery/v1|user=';
const String _wrapContextPrefix = 'pmchat-e2ee-recoverywrap/v1';

/// 恢复码格式不对（长度、字符、校验位）。还没碰服务器就能发现。
class E2eeRecoveryCodeFormatException extends E2eeCryptoException {
  const E2eeRecoveryCodeFormatException(super.message);
}

/// 格式对，但解不开服务器上的恢复码包装：不是这个账号当前的恢复码（或已经重新生成过）。
class E2eeWrongRecoveryCodeException extends E2eeCryptoException {
  const E2eeWrongRecoveryCodeException() : super('恢复码不正确，或者已经重新生成过（旧恢复码会失效）');
}

/// 一个恢复码。[data] 是 26 个规范化后的数据字符（真正的秘密），[formatted] 给用户看。
class E2eeRecoveryCode {
  E2eeRecoveryCode._(this.data)
      : assert(data.length == _dataChars),
        formatted = _group('$data${_checksum(data)}');

  /// 用 CSPRNG 生成一个新恢复码。
  factory E2eeRecoveryCode.generate() {
    final random = e2eeRandomBytes(_dataChars);
    final buffer = StringBuffer();
    for (final byte in random) {
      // 256 是 32 的整数倍，取低 5 位不会偏。
      buffer.write(kCrockfordAlphabet[byte & 0x1f]);
    }
    return E2eeRecoveryCode._(buffer.toString());
  }

  /// 测试用：由 26 个数据字符直接构造。
  factory E2eeRecoveryCode.fromData(String data) {
    final normalized = _normalize(data);
    if (normalized.length != _dataChars) {
      throw const E2eeRecoveryCodeFormatException('恢复码长度不正确');
    }
    return E2eeRecoveryCode._(normalized);
  }

  /// 解析用户输入的恢复码。大小写、空格、连字符随意；O 当 0，I、L 当 1。
  /// 格式或校验位不对时抛 [E2eeRecoveryCodeFormatException]。
  static E2eeRecoveryCode parse(String input) {
    final normalized = _normalize(input);
    if (normalized.isEmpty) {
      throw const E2eeRecoveryCodeFormatException('请输入恢复码');
    }
    for (final char in normalized.split('')) {
      if (!kCrockfordAlphabet.contains(char)) {
        throw E2eeRecoveryCodeFormatException('恢复码里不应有字符"$char"，请检查');
      }
    }
    if (normalized.length != _dataChars + _checkChars) {
      throw E2eeRecoveryCodeFormatException(
        '恢复码应为 ${_dataChars + _checkChars} 个字符，你输入了 ${normalized.length} 个',
      );
    }
    final data = normalized.substring(0, _dataChars);
    if (normalized.substring(_dataChars) != _checksum(data)) {
      throw const E2eeRecoveryCodeFormatException('恢复码有误，请逐个字符检查是否输错');
    }
    return E2eeRecoveryCode._(data);
  }

  final String data;

  /// 带校验位、分组后的样子，例如 `7K3M-...-QX2F`。
  final String formatted;

  /// 最后一组（用户复核"已保存"时要重新输入的部分）。
  String get lastGroup => formatted.substring(formatted.lastIndexOf('-') + 1);

  /// 规范化后的 28 个字符（不分组），用来判断某段文字里是不是含有这个恢复码。
  String get compact => formatted.replaceAll('-', '');

  /// 这段输入是不是等于最后一组（同样宽松地规范化）。
  bool matchesLastGroup(String input) => _normalize(input) == lastGroup;

  @override
  String toString() => 'E2eeRecoveryCode(***)';

  static String _normalize(String input) => input
      .toUpperCase()
      .replaceAll(RegExp(r'[\s\-_]'), '')
      .replaceAll('O', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1');

  static String _checksum(String data) {
    final digest = pc.SHA256Digest().process(
      Uint8List.fromList(utf8.encode('$_checkPrefix$data')),
    );
    final bits = (digest[0] << 2) | (digest[1] >> 6); // 前 10 位
    return '${kCrockfordAlphabet[bits >> 5]}${kCrockfordAlphabet[bits & 0x1f]}';
  }

  static String _group(String chars) {
    final groups = <String>[];
    for (var i = 0; i < chars.length; i += _groupSize) {
      groups.add(chars.substring(i, i + _groupSize));
    }
    return groups.join('-');
  }
}

class E2eeRecovery {
  const E2eeRecovery._();

  /// 由恢复码派生包装密钥。每次设置恢复码时 [salt] 重新随机，同一个恢复码包装的各版本共用。
  static Uint8List deriveWrapKey({
    required E2eeRecoveryCode code,
    required Uint8List salt,
    required String userId,
  }) {
    return E2eeCrypto.hkdfSha256(
      ikm: Uint8List.fromList(utf8.encode(code.data)),
      salt: salt,
      info: Uint8List.fromList(utf8.encode('$_hkdfInfoPrefix$userId')),
      length: 32,
    );
  }

  /// 用恢复码派生的密钥包装一把私钥。返回的 [E2eeWrappedKey] 里 wrap* 字段就是恢复码包装。
  static E2eeWrappedKey wrap({
    required Uint8List wrapKey,
    required Uint8List salt,
    required String userId,
    required E2eeKeyPair keyPair,
  }) {
    final iv = e2eeRandomBytes(12);
    final sealed = E2eeCrypto.aesGcm(
      encrypt: true,
      key: wrapKey,
      nonce: iv,
      aad: _context(userId, keyPair.version, keyPair.publicKeyBase64),
      input: keyPair.privateKey,
    );
    return E2eeWrappedKey(
      version: keyPair.version,
      publicKey: keyPair.publicKeyBase64,
      wrappedPrivateKey: base64Encode([...iv, ...sealed]),
      wrapSalt: base64Encode(salt),
      wrapParams: kE2eeRecoveryWrapParams,
    );
  }

  /// 用恢复码解开服务器上的恢复码包装，并确认和登记的公钥是一对。
  /// 解不开抛 [E2eeWrongRecoveryCodeException]。
  static Future<E2eeKeyPair> unwrap({
    required E2eeRecoveryCode code,
    required String userId,
    required E2eeWrappedKey wrapped,
    Map<String, Uint8List>? derivedKeyCache,
  }) async {
    if (wrapped.wrapParams != kE2eeRecoveryWrapParams) {
      throw const E2eeCryptoException('不支持的恢复码格式，请更新到最新版本');
    }
    final Uint8List salt;
    final Uint8List blob;
    try {
      salt = base64Decode(wrapped.wrapSalt);
      blob = base64Decode(wrapped.wrappedPrivateKey);
    } on FormatException {
      throw const E2eeCryptoException('恢复码包装格式不正确');
    }
    if (blob.length != 12 + 32 + 16) {
      throw const E2eeCryptoException('恢复码包装格式不正确');
    }
    final wrapKey = derivedKeyCache?[wrapped.wrapSalt] ??
        deriveWrapKey(code: code, salt: salt, userId: userId);
    derivedKeyCache?[wrapped.wrapSalt] = wrapKey;
    final Uint8List privateKey;
    try {
      privateKey = E2eeCrypto.aesGcm(
        encrypt: false,
        key: wrapKey,
        nonce: Uint8List.sublistView(blob, 0, 12),
        aad: _context(userId, wrapped.version, wrapped.publicKey),
        input: Uint8List.sublistView(blob, 12),
      );
    } catch (_) {
      throw const E2eeWrongRecoveryCodeException();
    }
    final pair = await E2eeCrypto.keyPairFromPrivate(
      wrapped.version,
      privateKey,
    );
    if (pair.publicKeyBase64 != wrapped.publicKey) {
      throw const E2eeCryptoException('加密私钥和公钥不匹配');
    }
    return pair;
  }

  static Uint8List _context(String userId, int version, String publicKey) {
    return Uint8List.fromList(
      utf8.encode(
        '$_wrapContextPrefix|user=$userId|version=$version|pub=$publicKey',
      ),
    );
  }
}

/// "发送到我的邮箱"：拼一个 mailto: 链接，交给本机的邮件应用。恢复码只进这个链接，
/// 不经过我们的服务器。
class E2eeRecoveryMail {
  const E2eeRecoveryMail._();

  static const String subject = 'PM chat 端到端加密恢复码';

  /// 只放行常见的邮箱写法：? & # % 之类会改变链接含义的字符一律不要。
  static final RegExp _emailPattern = RegExp(
    r'^[A-Za-z0-9._+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$',
  );

  static bool isValidAddress(String address) =>
      _emailPattern.hasMatch(address.trim());

  static String body(E2eeRecoveryCode code) => [
        '这是你的 PM chat 端到端加密恢复码：',
        '',
        code.formatted,
        '',
        '用途：忘记登录密码，或者密码被管理员重置后，在 PM chat「设置 → 隐私安全 → 用恢复码找回」'
            '输入它，就能找回加密聊天记录。',
        '',
        '注意：',
        '1. 任何能读取这个邮箱的人，拿到你的账号后都能解密你的加密聊天。请保护好这个邮箱，'
            '或者把恢复码另存到安全的地方后删除这封邮件。',
        '2. 登录密码和恢复码都丢了，加密聊天记录将永久无法找回，PM chat 也无法帮你恢复。',
        '3. 重新生成恢复码后，这个恢复码立即失效。',
      ].join('\n');

  /// mailto 链接：收件人是自己的邮箱，主题和正文按 RFC 6068 百分号编码
  /// （空格是 %20 而不是 +，换行是 %0D%0A），中文按 UTF-8 编码。
  static Uri buildUri({required String to, required E2eeRecoveryCode code}) {
    final address = to.trim();
    if (!isValidAddress(address)) {
      throw const FormatException('邮箱地址格式不正确');
    }
    final encodedBody = Uri.encodeComponent(
      body(code).replaceAll('\n', '\r\n'),
    );
    return Uri.parse(
      'mailto:$address'
      '?subject=${Uri.encodeComponent(subject)}'
      '&body=$encodedBody',
    );
  }

  /// 保存为文件时的内容（和邮件正文一样）。
  static String fileText(E2eeRecoveryCode code) =>
      '$subject\n\n${body(code)}\n';

  static const String fileName = 'PM-chat-recovery-code.txt';
}
