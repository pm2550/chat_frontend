import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_app/services/e2ee/e2ee_crypto.dart';
import 'package:chat_app/services/e2ee/e2ee_key_store.dart';
import 'package:chat_app/services/encryption_service.dart';
import 'package:http/http.dart' as http;

/// 测试里用轻量 Argon2 参数，免得每次包装都跑 64MB。
const fastE2eeArgon2Params = 'm=1024,t=1,p=1,v=19,hashLen=32';

/// 模拟服务器上和端到端加密有关的几个接口：它只保存公钥和包装过的私钥。
class FakeE2eeServer {
  final Map<String, List<Map<String, dynamic>>> keys = {};
  final Map<String, bool> enabled = {};
  final Map<String, int> active = {};
  final Map<String, String> passwords = {};
  final Map<String, List<String>> roomMembers = {};
  final Set<String> roomsWithBots = {};

  E2eeHttpRequest requestAs(String userId) {
    return (method, url, {body}) async {
      final path = Uri.parse(url).path;
      final json = body is Map ? Map<String, dynamic>.from(body) : null;
      if (method == 'GET' && path.endsWith('/e2ee/keys/me')) {
        return _ok({
          'enabled': _enabled(userId),
          'activeKeyVersion': active[userId],
          'passwordSchemeSupported': true,
          'keys': keys[userId] ?? const [],
        });
      }
      if (method == 'POST' && path.endsWith('/e2ee/keys')) {
        final list = keys.putIfAbsent(userId, () => []);
        if (json!['expectedActiveKeyVersion'] != active[userId] ||
            json['keyVersion'] != list.length + 1) {
          return http.Response(jsonEncode({'code': 409, 'message': '冲突'}), 409);
        }
        list.add({
          'version': json['keyVersion'],
          'publicKey': json['publicKey'],
          'wrappedPrivateKey': json['wrappedPrivateKey'],
          'wrapSalt': json['wrapSalt'],
          'wrapParams': json['wrapParams'],
        });
        active[userId] = json['keyVersion'] as int;
        enabled[userId] = true;
        return _ok({'enabled': true});
      }
      if (method == 'PUT' && path.endsWith('/e2ee/enabled')) {
        enabled[userId] = json!['enabled'] == true;
        return _ok({'enabled': enabled[userId]});
      }
      final userKeys = RegExp(r'/e2ee/users/(\w+)/keys$').firstMatch(path);
      if (method == 'GET' && userKeys != null) {
        return _ok(_directory(userKeys.group(1)!));
      }
      final room = RegExp(r'/e2ee/rooms/(\w+)/status$').firstMatch(path);
      if (method == 'GET' && room != null) {
        final roomId = room.group(1)!;
        final members = roomMembers[roomId] ?? const <String>[];
        final peerId = members.firstWhere((id) => id != userId);
        return _ok({
          'roomId': roomId,
          'eligible': !roomsWithBots.contains(roomId),
          'reason': roomsWithBots.contains(roomId) ? 'HAS_BOTS' : 'OK',
          'self': _directory(userId),
          'peer': _directory(peerId),
        });
      }
      return http.Response('{}', 404);
    };
  }

  /// 服务器侧"改密码"：接受客户端带来的新包装。
  void applyPasswordChange(String userId, Map<String, dynamic> extras) {
    final wraps = (extras['e2eeKeyWraps'] as List).cast<Map<String, dynamic>>();
    for (final wrap in wraps) {
      final key =
          keys[userId]!.firstWhere((k) => k['version'] == wrap['version']);
      key['wrappedPrivateKey'] = wrap['wrappedPrivateKey'];
      key['wrapSalt'] = wrap['wrapSalt'];
      key['wrapParams'] = wrap['wrapParams'];
    }
  }

  bool _enabled(String userId) =>
      enabled[userId] == true && active[userId] != null;

  Map<String, dynamic> _directory(String userId) => {
        'userId': userId,
        'enabled': _enabled(userId),
        'activeKeyVersion': active[userId],
        'keys': [
          for (final key in keys[userId] ?? const <Map<String, dynamic>>[])
            {'version': key['version'], 'publicKey': key['publicKey']},
        ],
      };

  http.Response _ok(Object data) => http.Response.bytes(
        utf8.encode(jsonEncode({'code': 200, 'data': data})),
        200,
      );
}

/// 每台"设备"各自的本机存储。
class MemoryKeyStore extends E2eeKeyStore {
  MemoryKeyStore();

  final E2eeLocalState state = E2eeLocalState();

  @override
  Future<E2eeLocalState> load() async => state;

  @override
  Future<void> saveKeys(String userId, Map<int, E2eeKeyPair> keys) async {
    state.userId = userId;
    final copy = Map<int, E2eeKeyPair>.from(keys);
    state.keys
      ..clear()
      ..addAll(copy);
  }

  @override
  Future<void> savePins(String userId, Map<String, Uint8List> pins) async {
    state.pinsOwner = userId;
    final copy = Map<String, Uint8List>.from(pins);
    state.pins
      ..clear()
      ..addAll(copy);
  }
}

EncryptionService e2eeDevice(FakeE2eeServer server, String userId) {
  return EncryptionService.test(
    request: server.requestAs(userId),
    currentUserId: () => userId,
    verifyPassword: (password) async => server.passwords[userId] == password,
    store: MemoryKeyStore(),
    wrapArgon2Params: fastE2eeArgon2Params,
  );
}
