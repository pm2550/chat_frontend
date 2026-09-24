import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'e2ee_crypto.dart';

/// 本机保存的端到端加密状态：解开后的私钥 + 已钉住的对方公钥。
///
/// 私钥以明文存在本机（web 是 localStorage，App 是 SharedPreferences）：
/// 否则每次打开 App 都要重新输密码。代价是本机被入侵（或网页被注入脚本）时私钥可被读走——
/// 和大多数桌面/网页 IM 的取舍相同。退出登录时整份删除。
///
/// 对方公钥按"用户:版本"钉住（TOFU）：之后服务器若给出不同的公钥，以本机钉住的为准并报警，
/// 防止服务器事后替换公钥来冒充对方。
class E2eeKeyStore {
  const E2eeKeyStore();

  static const _keysKey = 'e2ee.v2.keys';
  static const _pinsKey = 'e2ee.v2.pins';

  // 老版本"假加密"留下的本地项，一并清掉。
  static const _legacyKeys = [
    'e2ee_keys_uploaded',
    'e2ee_local_secret',
    'e2ee_identity_public_key',
  ];

  Future<E2eeLocalState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final state = E2eeLocalState();
    try {
      final raw = prefs.getString(_keysKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        state.userId = decoded['userId']?.toString();
        for (final item in (decoded['keys'] as List? ?? const [])) {
          final map = Map<String, dynamic>.from(item as Map);
          final pair = E2eeKeyPair(
            version: (map['version'] as num).toInt(),
            privateKey: base64Decode(map['privateKey'].toString()),
            publicKey: base64Decode(map['publicKey'].toString()),
          );
          state.keys[pair.version] = pair;
        }
      }
    } catch (_) {
      state.keys.clear();
    }
    try {
      final raw = prefs.getString(_pinsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        state.pinsOwner = decoded['userId']?.toString();
        final pins = decoded['pins'] as Map? ?? const {};
        pins.forEach((key, value) {
          state.pins[key.toString()] = base64Decode(value.toString());
        });
      }
    } catch (_) {
      state.pins.clear();
    }
    return state;
  }

  Future<void> saveKeys(String userId, Map<int, E2eeKeyPair> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keysKey,
      jsonEncode({
        'userId': userId,
        'keys': [
          for (final pair in keys.values)
            {
              'version': pair.version,
              'privateKey': base64Encode(pair.privateKey),
              'publicKey': pair.publicKeyBase64,
            },
        ],
      }),
    );
  }

  Future<void> savePins(String userId, Map<String, Uint8List> pins) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pinsKey,
      jsonEncode({
        'userId': userId,
        'pins': pins.map((key, value) => MapEntry(key, base64Encode(value))),
      }),
    );
  }

  /// 退出登录：私钥和钉住的公钥都从本机删掉。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keysKey);
    await prefs.remove(_pinsKey);
    for (final key in _legacyKeys) {
      await prefs.remove(key);
    }
  }
}

class E2eeLocalState {
  String? userId;
  String? pinsOwner;
  final Map<int, E2eeKeyPair> keys = {};
  final Map<String, Uint8List> pins = {};
}
