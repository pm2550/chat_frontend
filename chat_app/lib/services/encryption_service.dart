import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'auth_service.dart';
import 'e2ee/e2ee_crypto.dart';
import 'e2ee/e2ee_key_store.dart';

export 'e2ee/e2ee_crypto.dart'
    show
        E2eeAttachmentKey,
        E2eeCryptoException,
        E2eeWrongPasswordException,
        kE2eeEncryptionVersion,
        kE2eeServerAttachmentName,
        kE2eeServerPlaceholder,
        kE2eeShortLabel;

typedef E2eeHttpRequest = Future<http.Response> Function(
  String method,
  String url, {
  Object? body,
});

/// 私聊能不能加密、现在是什么状态。决定聊天头部的锁、提示条和发送时加不加密。
enum E2eeRoomMode {
  /// 群聊、AI 会话等：不涉及端到端加密，什么都不显示。
  none,

  /// 自己没开：明文，不提示。
  selfOff,

  /// 自己开了、对方没开：明文，提示"对方尚未启用加密"。
  peerOff,

  /// 私聊里有机器人：机器人读不了密文，明文。
  hasBots,

  /// 双方都开了，但这台设备还没解开自己的私钥：先解锁才能发。
  needsUnlock,

  /// 对方公钥和本机钉住的不一致：可能被替换，暂停加密发送。
  keyChanged,

  /// 双方都开了：自动加密。
  active,

  /// 暂时查不到（断网等）。
  unknown,
}

class E2eeRoomState {
  const E2eeRoomState(
    this.mode, {
    this.peerId,
    this.peerKeyVersion,
    this.peerPublicKey,
    this.myKeyVersion,
    this.checkedAt,
  });

  static const none = E2eeRoomState(E2eeRoomMode.none);

  final E2eeRoomMode mode;
  final String? peerId;
  final int? peerKeyVersion;
  final Uint8List? peerPublicKey;
  final int? myKeyVersion;
  final DateTime? checkedAt;

  bool get encrypts => mode == E2eeRoomMode.active;

  /// 聊天里要显示的提示；没有就不显示。
  String? get notice => switch (mode) {
        E2eeRoomMode.peerOff => '对方尚未启用端到端加密，消息未加密',
        E2eeRoomMode.hasBots => '会话中有机器人，消息未端到端加密',
        E2eeRoomMode.needsUnlock => '此设备尚未解锁端到端加密，输入登录密码后才能查看和发送加密消息',
        E2eeRoomMode.keyChanged => '对方的加密密钥发生了变化，已暂停发送加密消息',
        _ => null,
      };
}

/// 为什么这条加密消息现在读不了（或读得了）。
enum E2eeRevealStatus {
  ok,
  locked,
  pending,
  failed,
  keyLost,
  keyChanged,
  unsupported,
}

class E2eeReveal {
  const E2eeReveal(this.status, [this.payload]);

  final E2eeRevealStatus status;
  final E2eePayload? payload;

  bool get isReadable => status == E2eeRevealStatus.ok;

  String get displayText => switch (status) {
        E2eeRevealStatus.ok => payload?.text ?? '',
        E2eeRevealStatus.locked => '[加密消息] 在此设备解锁端到端加密后可查看',
        E2eeRevealStatus.pending => '[加密消息] 正在解密…',
        E2eeRevealStatus.failed => '[加密消息] 无法解密这条消息',
        E2eeRevealStatus.keyLost => '[加密消息] 无法解密：对应的密钥已失效',
        E2eeRevealStatus.keyChanged => '[加密消息] 对方的加密密钥发生了变化，已拒绝解密',
        E2eeRevealStatus.unsupported => kE2eeServerPlaceholder,
      };
}

/// 本账号的加密状态（设置页用）。
class E2eeAccountStatus {
  const E2eeAccountStatus({
    required this.serverEnabled,
    required this.hasServerKeys,
    required this.unlockedOnDevice,
    required this.passwordSchemeSupported,
    this.activeKeyVersion,
  });

  final bool serverEnabled;
  final bool hasServerKeys;
  final bool unlockedOnDevice;
  final bool passwordSchemeSupported;
  final int? activeKeyVersion;
}

class E2eeException implements Exception {
  const E2eeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 发送被拦下：该加密却暂时加密不了，不能悄悄发明文。
class E2eeSendBlockedException extends E2eeException {
  const E2eeSendBlockedException(super.message);
}

enum E2eeUnlockResult { unlocked, wrongPassword, noKeys }

/// 加密好的附件：上传 [ciphertext]（服务器只看到一个 .bin），[envelope] 作为消息密文。
class E2eeSealedFile {
  const E2eeSealedFile({required this.ciphertext, required this.envelope});

  final Uint8List ciphertext;
  final String envelope;
}

/// 私聊端到端加密的客户端会话：管本机私钥、对方公钥、会话状态，负责加密发送和解密显示。
/// 密码学细节见 e2ee_crypto.dart。
///
/// 解密是同步的（纯 Dart 的 X25519 + AES-GCM），挂在 [Message.contentRevealer] 上：
/// 任何地方解析出来的消息（历史、实时推送、回复引用、置顶、收藏、会话列表预览）
/// 都直接拿到明文。缺对方公钥时先显示"正在解密"，取到后 [notifyListeners]，
/// 聊天页据此重新解一遍。
class EncryptionService extends ChangeNotifier {
  static final EncryptionService _instance = EncryptionService._(
    request: (method, url, {body}) =>
        AuthService().authenticatedRequest(method, url, body: body),
    currentUserId: () => AuthService().currentUser?.id,
    verifyPassword: (password) => AuthService().verifyPassword(password),
    store: const E2eeKeyStore(),
  );
  factory EncryptionService() => _instance;

  EncryptionService._({
    required E2eeHttpRequest request,
    required String? Function() currentUserId,
    required Future<bool> Function(String password) verifyPassword,
    required E2eeKeyStore store,
    String wrapArgon2Params = kE2eeWrapArgon2Params,
  })  : _request = request,
        _currentUserId = currentUserId,
        _verifyPassword = verifyPassword,
        _store = store,
        _wrapArgon2Params = wrapArgon2Params;

  @visibleForTesting
  EncryptionService.test({
    required E2eeHttpRequest request,
    required String? Function() currentUserId,
    Future<bool> Function(String password)? verifyPassword,
    E2eeKeyStore store = const E2eeKeyStore(),
    String wrapArgon2Params = kE2eeWrapArgon2Params,
  }) : this._(
          request: request,
          currentUserId: currentUserId,
          verifyPassword: verifyPassword ?? (_) async => true,
          store: store,
          wrapArgon2Params: wrapArgon2Params,
        );

  static const _roomStateTtl = Duration(minutes: 1);
  static const _maxCachedReveals = 3000;
  static const _maxEnvelopeBytes = 60000;

  final E2eeHttpRequest _request;
  final String? Function() _currentUserId;
  final Future<bool> Function(String password) _verifyPassword;
  final E2eeKeyStore _store;
  final String _wrapArgon2Params;

  String? _loadedUserId;
  Future<void>? _loading;
  final Map<int, E2eeKeyPair> _myKeys = {};
  final Map<String, Uint8List> _pins = {};
  final Set<String> _keyChangedPins = {};
  final Map<String, Future<void>> _peerFetches = {};
  final Map<String, DateTime> _peerFetchFailedAt = {};
  final LinkedHashMap<String, E2eeReveal> _reveals = LinkedHashMap();
  final Map<String, E2eeRoomState> _roomStates = {};
  final Map<String, E2eeAttachmentKey> _attachmentKeysByUrl = {};
  bool? _lastKnownSelfEnabled;
  AuthService? _installedAuth;

  /// 在 main() 里调用一次：接上消息解析、登录和改密码的钩子。
  void install({AuthService? authService}) {
    final auth = authService ?? AuthService();
    Message.contentRevealer = reveal;
    auth.onPasswordVerified = handleVerifiedPassword;
    auth.passwordChangeExtras = passwordChangeExtras;
    if (!identical(_installedAuth, auth)) {
      _installedAuth?.removeListener(_onAuthChanged);
      auth.addListener(_onAuthChanged);
      _installedAuth = auth;
    }
    unawaited(ensureLoaded());
  }

  void _onAuthChanged() {
    final userId = _currentUserId();
    if (userId == _loadedUserId) return;
    // 换了账号或退出登录：内存里的私钥、钉住的公钥和解密结果全部作废。
    _resetMemory();
    if (userId != null) unawaited(ensureLoaded());
    notifyListeners();
  }

  void _resetMemory() {
    _loadedUserId = null;
    _loading = null;
    _myKeys.clear();
    _pins.clear();
    _keyChangedPins.clear();
    _peerFetches.clear();
    _peerFetchFailedAt.clear();
    _reveals.clear();
    _roomStates.clear();
    _attachmentKeysByUrl.clear();
    _lastKnownSelfEnabled = null;
  }

  /// 读本机保存的私钥和钉住的公钥（只认当前账号的）。
  Future<void> ensureLoaded() {
    final userId = _currentUserId();
    if (userId == null) return Future.value();
    if (_loadedUserId == userId) return _loading ?? Future.value();
    // 换了账号：上一个账号的私钥、公钥和解密结果一律不能带过来。
    if (_loadedUserId != null) _resetMemory();
    _loadedUserId = userId;
    // 读完就清掉，之后的调用直接返回新的已完成 Future，不再挂在旧 Future 上。
    final loading = _load(userId).whenComplete(() {
      if (_loadedUserId == userId) _loading = null;
    });
    _loading = loading;
    return loading;
  }

  Future<void> _load(String userId) async {
    try {
      final local = await _store.load();
      if (_loadedUserId != userId) return;
      if (local.userId == userId) {
        for (final entry in local.keys.entries) {
          _myKeys.putIfAbsent(entry.key, () => entry.value);
        }
      }
      if (local.pinsOwner == userId) {
        for (final entry in local.pins.entries) {
          _pins.putIfAbsent(entry.key, () => entry.value);
        }
      }
      _reveals.removeWhere((_, value) => !value.isReadable);
      notifyListeners();
    } catch (e) {
      developer.log('E2EE local state load failed', error: e);
    }
  }

  bool get hasUnlockedKeys => _myKeys.isNotEmpty;

  // ---------------------------------------------------------------- 解密显示

  /// 把一条加密消息换成可显示的样子：能解就换成明文（附件还原真实类型和文件名），
  /// 解不了就换成原因说明。非加密消息原样返回。
  Message reveal(Message message) {
    if (!message.isEncrypted || message.isRemoved) return message;
    final result = revealResult(message);
    final payload = result.payload;
    if (!result.isReadable || payload == null) {
      return message.copyWith(content: result.displayText);
    }
    final attachment = payload.attachment;
    if (attachment == null) {
      return message.copyWith(content: payload.text);
    }
    final fileUrl = message.fileUrl;
    if (fileUrl != null && fileUrl.isNotEmpty) {
      _attachmentKeysByUrl[fileUrl] = attachment;
    }
    return message.copyWith(
      content: payload.text.isNotEmpty ? payload.text : attachment.name,
      type: _messageTypeForKind(payload.kind),
      fileName: attachment.name,
      fileType: attachment.mimeType,
      fileSize: attachment.size,
    );
  }

  /// 解密结果（带缓存）。
  E2eeReveal revealResult(Message message) {
    final ciphertext = message.encryptedContent;
    if (ciphertext == null || ciphertext.isEmpty) {
      return const E2eeReveal(E2eeRevealStatus.failed);
    }
    final cached = _reveals[ciphertext];
    if (cached != null) return cached;

    final result = _computeReveal(message, ciphertext);
    if (result.status != E2eeRevealStatus.locked &&
        result.status != E2eeRevealStatus.pending &&
        result.status != E2eeRevealStatus.keyLost) {
      _reveals[ciphertext] = result;
      while (_reveals.length > _maxCachedReveals) {
        _reveals.remove(_reveals.keys.first);
      }
    }
    return result;
  }

  /// 这条消息的内容能不能拿来复制、转发、引用、编辑。
  bool isReadable(Message message) =>
      !message.isEncrypted || revealResult(message).isReadable;

  /// 加密附件的解密信息（只有解开了才有）。
  E2eeAttachmentKey? attachmentKeyFor(Message message) {
    if (!message.isEncrypted) return null;
    final result = revealResult(message);
    return result.isReadable ? result.payload?.attachment : null;
  }

  E2eeReveal _computeReveal(Message message, String ciphertext) {
    if (message.encryptionVersion != kE2eeEncryptionVersion) {
      return const E2eeReveal(E2eeRevealStatus.unsupported);
    }
    final envelope = E2eeEnvelope.tryParse(ciphertext);
    if (envelope == null) {
      return const E2eeReveal(E2eeRevealStatus.unsupported);
    }
    // 服务器说的发送者、会话必须和信封里（参与了密钥派生）的一致。
    if (envelope.senderId != message.senderId ||
        (message.chatRoomId.isNotEmpty &&
            envelope.roomId != message.chatRoomId)) {
      return const E2eeReveal(E2eeRevealStatus.failed);
    }
    final me = _currentUserId();
    if (me == null || _loadedUserId != me) {
      unawaited(ensureLoaded());
      return const E2eeReveal(E2eeRevealStatus.pending);
    }
    final int myVersion;
    final String peerId;
    final int peerVersion;
    if (envelope.senderId == me) {
      myVersion = envelope.senderKeyVersion;
      peerId = envelope.recipientId;
      peerVersion = envelope.recipientKeyVersion;
    } else if (envelope.recipientId == me) {
      myVersion = envelope.recipientKeyVersion;
      peerId = envelope.senderId;
      peerVersion = envelope.senderKeyVersion;
    } else {
      return const E2eeReveal(E2eeRevealStatus.failed);
    }
    final mine = _myKeys[myVersion];
    if (mine == null) {
      return E2eeReveal(
          _myKeys.isEmpty ? E2eeRevealStatus.locked : E2eeRevealStatus.keyLost);
    }
    final pinKey = _pinKey(peerId, peerVersion);
    if (_keyChangedPins.contains(pinKey)) {
      return const E2eeReveal(E2eeRevealStatus.keyChanged);
    }
    final peerPublic = _pins[pinKey];
    if (peerPublic == null) {
      _fetchPeerKeys(peerId);
      return const E2eeReveal(E2eeRevealStatus.pending);
    }
    try {
      return E2eeReveal(
        E2eeRevealStatus.ok,
        E2eeCrypto.open(
          envelope: envelope,
          mine: mine,
          peerPublicKey: peerPublic,
        ),
      );
    } catch (_) {
      return const E2eeReveal(E2eeRevealStatus.failed);
    }
  }

  static MessageType _messageTypeForKind(String kind) => switch (kind) {
        'image' => MessageType.image,
        'voice' => MessageType.voice,
        'audio' => MessageType.audio,
        'video' => MessageType.video,
        'file' => MessageType.file,
        _ => MessageType.text,
      };

  // ---------------------------------------------------------------- 公钥目录

  static String _pinKey(String userId, int version) => '$userId:$version';

  void _fetchPeerKeys(String userId) {
    if (_peerFetches.containsKey(userId)) return;
    final failedAt = _peerFetchFailedAt[userId];
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < const Duration(seconds: 30)) {
      return;
    }
    _peerFetches[userId] = _loadPeerKeys(userId).whenComplete(() {
      _peerFetches.remove(userId);
    });
  }

  /// 等正在进行的公钥查询结束（测试和需要立刻拿到明文的地方用）。
  @visibleForTesting
  Future<void> waitForPendingKeyFetches() =>
      Future.wait(_peerFetches.values.toList());

  Future<void> _loadPeerKeys(String userId) async {
    try {
      final response = await _request('GET', ApiConstants.e2eeUserKeys(userId));
      if (response.statusCode != 200) {
        _peerFetchFailedAt[userId] = DateTime.now();
        return;
      }
      final data = _data(response);
      if (data != null && _pinDirectory(data)) {
        await _persistPins();
      }
      notifyListeners();
    } catch (e) {
      _peerFetchFailedAt[userId] = DateTime.now();
      developer.log('E2EE peer key fetch failed', error: e);
    }
  }

  /// 把服务器给的公钥目录钉到本机。已钉住却不一样的版本记为"密钥被换"，不采用新值。
  /// 返回是否新钉了公钥。
  bool _pinDirectory(Map<String, dynamic> directory) {
    final userId = directory['userId']?.toString();
    final keys = directory['keys'];
    if (userId == null || keys is! List) return false;
    var changed = false;
    for (final item in keys.whereType<Map>()) {
      final version = (item['version'] as num?)?.toInt();
      final encoded = item['publicKey']?.toString();
      if (version == null || encoded == null) continue;
      final Uint8List publicKey;
      try {
        publicKey = base64Decode(encoded);
      } catch (_) {
        continue;
      }
      if (publicKey.length != 32) continue;
      final pinKey = _pinKey(userId, version);
      final pinned = _pins[pinKey];
      if (pinned == null) {
        _pins[pinKey] = publicKey;
        changed = true;
      } else if (!listEquals(pinned, publicKey)) {
        _keyChangedPins.add(pinKey);
      }
    }
    return changed;
  }

  Future<void> _persistPins() async {
    final userId = _loadedUserId;
    if (userId == null) return;
    await _store.savePins(userId, _pins);
  }

  Future<void> _persistKeys() async {
    final userId = _loadedUserId;
    if (userId == null) return;
    await _store.saveKeys(userId, _myKeys);
  }

  // ---------------------------------------------------------------- 会话状态 / 发送

  /// 私聊的加密状态。群聊等直接返回 [E2eeRoomState.none]，不发请求。
  Future<E2eeRoomState> roomState(Chat chat, {bool refresh = false}) async {
    if (chat.type != ChatType.private || chat.id.isEmpty) {
      return E2eeRoomState.none;
    }
    return _roomStateForId(chat.id, refresh: refresh);
  }

  Future<E2eeRoomState> _roomStateForId(
    String chatId, {
    bool refresh = false,
  }) async {
    final cached = _roomStates[chatId];
    if (!refresh &&
        cached?.checkedAt != null &&
        DateTime.now().difference(cached!.checkedAt!) < _roomStateTtl) {
      return cached;
    }
    await ensureLoaded();
    try {
      final response =
          await _request('GET', ApiConstants.e2eeRoomStatus(chatId));
      if (response.statusCode == 404) {
        // 服务器还没有这个功能（前端先于后端上线）：当普通会话。
        return _rememberRoom(chatId, E2eeRoomState.none);
      }
      final data = response.statusCode == 200 ? _data(response) : null;
      if (data == null) {
        return cached ?? const E2eeRoomState(E2eeRoomMode.unknown);
      }
      return _rememberRoom(chatId, _parseRoomState(data));
    } catch (e) {
      developer.log('E2EE room status failed', error: e);
      return cached ?? const E2eeRoomState(E2eeRoomMode.unknown);
    }
  }

  /// 已知的会话状态（不发请求），用于同步判断。
  E2eeRoomState cachedRoomState(String chatId) =>
      _roomStates[chatId] ?? E2eeRoomState.none;

  E2eeRoomState _rememberRoom(String chatId, E2eeRoomState state) {
    _roomStates[chatId] = state;
    return state;
  }

  E2eeRoomState _parseRoomState(Map<String, dynamic> data) {
    final now = DateTime.now();
    final self = data['self'] is Map
        ? Map<String, dynamic>.from(data['self'] as Map)
        : const <String, dynamic>{};
    final peer = data['peer'] is Map
        ? Map<String, dynamic>.from(data['peer'] as Map)
        : null;
    final selfEnabled = self['enabled'] == true;
    _lastKnownSelfEnabled = selfEnabled;
    if (data['eligible'] != true) {
      final hasBots = data['reason'] == 'HAS_BOTS';
      return E2eeRoomState(
        hasBots && selfEnabled ? E2eeRoomMode.hasBots : E2eeRoomMode.none,
        checkedAt: now,
      );
    }
    if (!selfEnabled) {
      return E2eeRoomState(E2eeRoomMode.selfOff, checkedAt: now);
    }
    if (peer == null || peer['enabled'] != true) {
      return E2eeRoomState(E2eeRoomMode.peerOff, checkedAt: now);
    }
    if (_pinDirectory(peer)) {
      unawaited(_persistPins());
    }
    final peerId = peer['userId']?.toString();
    final peerVersion = (peer['activeKeyVersion'] as num?)?.toInt();
    final myVersion = (self['activeKeyVersion'] as num?)?.toInt();
    if (peerId == null || peerVersion == null || myVersion == null) {
      return E2eeRoomState(E2eeRoomMode.peerOff, checkedAt: now);
    }
    final pinKey = _pinKey(peerId, peerVersion);
    if (_keyChangedPins.contains(pinKey)) {
      return E2eeRoomState(E2eeRoomMode.keyChanged,
          peerId: peerId, checkedAt: now);
    }
    if (!_myKeys.containsKey(myVersion) || _pins[pinKey] == null) {
      return E2eeRoomState(E2eeRoomMode.needsUnlock,
          peerId: peerId, myKeyVersion: myVersion, checkedAt: now);
    }
    return E2eeRoomState(
      E2eeRoomMode.active,
      peerId: peerId,
      peerKeyVersion: peerVersion,
      peerPublicKey: _pins[pinKey],
      myKeyVersion: myVersion,
      checkedAt: now,
    );
  }

  /// 发送前调用：该加密就返回密文信封（base64），可以明文发就返回 null。
  /// 该加密却做不到（没解锁、公钥被换、状态查不到）时抛 [E2eeSendBlockedException]，
  /// 绝不悄悄降级成明文。
  Future<String?> sealText(Chat chat, String text) {
    return _seal(chat, E2eePayload(kind: 'text', text: text));
  }

  /// 同上，用于加密附件：[attachment] 带文件密钥和真实文件名。
  Future<String?> sealAttachment(
    Chat chat, {
    required String kind,
    required E2eeAttachmentKey attachment,
    String caption = '',
  }) {
    return _seal(
      chat,
      E2eePayload(kind: kind, text: caption, attachment: attachment),
    );
  }

  /// 加密附件：会话该加密时，用随机文件密钥加密文件字节，再把文件密钥和真实文件名
  /// 放进消息密文。返回 null 表示这个会话照常明文发送。
  /// [readBytes] 只在需要加密时才调用（大文件不用白读一遍）。
  Future<E2eeSealedFile?> sealFile(
    Chat chat, {
    required String name,
    required String mimeType,
    required String kind,
    required Future<Uint8List> Function() readBytes,
  }) async {
    if (!await shouldEncrypt(chat)) return null;
    final encrypted = await E2eeCrypto.encryptAttachment(
      bytes: await readBytes(),
      name: name,
      mimeType: mimeType,
    );
    final envelope = await sealAttachment(
      chat,
      kind: kind,
      attachment: encrypted.key,
    );
    if (envelope == null) {
      throw const E2eeSendBlockedException('端到端加密状态刚刚变化，请重试');
    }
    return E2eeSealedFile(ciphertext: encrypted.ciphertext, envelope: envelope);
  }

  /// 下载到的附件字节：是本机解开过的加密附件就解密，否则原样返回。
  /// 图片组件按地址取图时经过这里（地址 → 文件密钥由 [reveal] 登记）。
  Future<Uint8List> openDownloadedFile(String url, Uint8List bytes) async {
    final key = _attachmentKeysByUrl[url];
    if (key == null) {
      // 加密附件一律存成 .bin；还没解开对应消息就别把密文当图片缓存下来。
      if (url.toLowerCase().endsWith('.bin')) {
        throw const E2eeException('加密附件尚未解密');
      }
      return bytes;
    }
    return E2eeCrypto.decryptAttachment(ciphertext: bytes, key: key);
  }

  /// 解密加密附件消息下载到的字节。
  Future<Uint8List> openAttachment(Message message, Uint8List bytes) async {
    final key = attachmentKeyFor(message);
    if (key == null) {
      throw const E2eeException('无法解密这个附件');
    }
    return E2eeCrypto.decryptAttachment(ciphertext: bytes, key: key);
  }

  /// 编辑自己的加密消息：用原消息那一对密钥版本重新加密，对方用原来的密钥就能解，
  /// 和现在开没开加密无关（服务器也不允许把加密消息改成明文）。
  String sealEditedText(Message original, String text) {
    final envelope = E2eeEnvelope.tryParse(original.encryptedContent);
    final me = _currentUserId();
    if (envelope == null || me == null || envelope.senderId != me) {
      throw const E2eeException('只能编辑自己发的加密消息');
    }
    final mine = _myKeys[envelope.senderKeyVersion];
    final peerPublic =
        _pins[_pinKey(envelope.recipientId, envelope.recipientKeyVersion)];
    if (mine == null || peerPublic == null) {
      throw const E2eeSendBlockedException('此设备无法重新加密这条消息，请先解锁端到端加密');
    }
    return E2eeCrypto.seal(
      roomId: envelope.roomId,
      senderId: me,
      mine: mine,
      recipientId: envelope.recipientId,
      recipientKeyVersion: envelope.recipientKeyVersion,
      peerPublicKey: peerPublic,
      payload: E2eePayload(kind: 'text', text: text),
    );
  }

  /// 只看状态、决定这个会话发东西要不要加密（附件先加密文件再发）。
  /// 该加密却做不到时同样抛 [E2eeSendBlockedException]。
  Future<bool> shouldEncrypt(Chat chat) async {
    var state = await roomState(chat);
    if (state.mode == E2eeRoomMode.needsUnlock && _myKeys.isNotEmpty) {
      state = await roomState(chat, refresh: true);
    }
    _throwIfBlocked(state);
    return state.encrypts;
  }

  Future<String?> _seal(Chat chat, E2eePayload payload) async {
    var state = await roomState(chat);
    if (state.mode == E2eeRoomMode.needsUnlock && _myKeys.isNotEmpty) {
      // 可能刚刚才解锁，缓存还是旧的。
      state = await roomState(chat, refresh: true);
    }
    _throwIfBlocked(state);
    if (!state.encrypts) return null;
    final me = _currentUserId();
    final mine = _myKeys[state.myKeyVersion];
    final peerPublic = state.peerPublicKey;
    if (me == null || mine == null || peerPublic == null) {
      throw const E2eeSendBlockedException('此设备尚未解锁端到端加密');
    }
    final sealed = E2eeCrypto.seal(
      roomId: chat.id,
      senderId: me,
      mine: mine,
      recipientId: state.peerId!,
      recipientKeyVersion: state.peerKeyVersion!,
      peerPublicKey: peerPublic,
      payload: payload,
    );
    if (sealed.length * 3 ~/ 4 > _maxEnvelopeBytes) {
      throw const E2eeSendBlockedException('消息太长，加密后超出上限，请分几条发送');
    }
    return sealed;
  }

  void _throwIfBlocked(E2eeRoomState state) {
    switch (state.mode) {
      case E2eeRoomMode.needsUnlock:
        throw const E2eeSendBlockedException('此设备尚未解锁端到端加密，请先输入登录密码解锁');
      case E2eeRoomMode.keyChanged:
        throw const E2eeSendBlockedException('对方的加密密钥发生了变化，已暂停发送加密消息');
      case E2eeRoomMode.unknown:
        // 查不到状态时：知道自己开着（或本机有密钥）就拦下，免得悄悄发成明文；
        // 从没开过加密的人照常发。
        final maybeEnabled =
            _lastKnownSelfEnabled ?? (_myKeys.isNotEmpty ? true : false);
        if (maybeEnabled) {
          throw const E2eeSendBlockedException('暂时无法确认端到端加密状态，请稍后重试');
        }
        return;
      default:
        return;
    }
  }

  // ---------------------------------------------------------------- 密钥管理

  Future<E2eeAccountStatus> accountStatus() async {
    await ensureLoaded();
    final own = await _fetchOwnKeys();
    final active = (own['activeKeyVersion'] as num?)?.toInt();
    _lastKnownSelfEnabled = own['enabled'] == true;
    return E2eeAccountStatus(
      serverEnabled: own['enabled'] == true,
      hasServerKeys: _wrappedKeys(own).isNotEmpty,
      unlockedOnDevice: active != null && _myKeys.containsKey(active),
      passwordSchemeSupported: own['passwordSchemeSupported'] == true,
      activeKeyVersion: active,
    );
  }

  /// 登录成功后（密码刚被服务器验证过）：把服务器上的私钥解开存到本机。
  /// 没开过加密的账号只多一次请求。失败不影响登录。
  Future<void> handleVerifiedPassword(String password) async {
    try {
      await ensureLoaded();
      await unlockWithPassword(password);
    } catch (e) {
      developer.log('E2EE unlock after login failed', error: e);
    }
  }

  /// 用登录密码在这台设备上解开私钥（多设备：每台设备各解一次）。
  Future<E2eeUnlockResult> unlockWithPassword(String password) async {
    await ensureLoaded();
    final own = await _fetchOwnKeys();
    final wrapped = _wrappedKeys(own);
    if (wrapped.isEmpty) return E2eeUnlockResult.noKeys;
    final userId = _requireUserId();
    final derived = <String, Uint8List>{};
    for (final key in wrapped) {
      if (_myKeys.containsKey(key.version)) continue;
      try {
        _myKeys[key.version] = await E2eeCrypto.unwrapPrivateKey(
          password: password,
          userId: userId,
          wrapped: key,
          derivedKeyCache: derived,
        );
      } on E2eeCryptoException {
        // 这一版是用以前的密码包的（密码被重置过），解不开就算了。
      }
    }
    await _persistKeys();
    _afterKeysChanged();
    final active = (own['activeKeyVersion'] as num?)?.toInt();
    if (active != null && !_myKeys.containsKey(active)) {
      return E2eeUnlockResult.wrongPassword;
    }
    return E2eeUnlockResult.unlocked;
  }

  /// 开启：第一次就生成密钥（用密码包装后上传）；以前生成过就解锁后重新打开开关。
  Future<void> enable(String password) async {
    await ensureLoaded();
    final own = await _fetchOwnKeys();
    if (own['passwordSchemeSupported'] != true) {
      throw const E2eeException('请先修改一次登录密码（升级为新的密码保护方式），再开启端到端加密');
    }
    if (_wrappedKeys(own).isEmpty) {
      await _createKey(password, own);
      return;
    }
    final result = await unlockWithPassword(password);
    if (result != E2eeUnlockResult.unlocked) {
      throw const E2eeWrongPasswordException();
    }
    await _put(ApiConstants.e2eeEnabled, {'enabled': true});
    _lastKnownSelfEnabled = true;
    _afterKeysChanged();
  }

  /// 重新打开（以前生成过密钥、本机也已解锁）：不用再输密码。
  Future<void> reenable() async {
    await _put(ApiConstants.e2eeEnabled, {'enabled': true});
    _lastKnownSelfEnabled = true;
    _afterKeysChanged();
  }

  /// 关闭：只是以后的消息不再加密。密钥留着，已加密的历史照样能读。
  Future<void> disable() async {
    await _put(ApiConstants.e2eeEnabled, {'enabled': false});
    _lastKnownSelfEnabled = false;
    _afterKeysChanged();
  }

  /// 密码被重置、旧私钥解不开时：生成新的一把。用旧密钥加密的历史从此无法解密。
  Future<void> resetKeys(String password) async {
    await ensureLoaded();
    final own = await _fetchOwnKeys();
    if (own['passwordSchemeSupported'] != true) {
      throw const E2eeException('请先修改一次登录密码（升级为新的密码保护方式），再开启端到端加密');
    }
    await _createKey(password, own);
  }

  Future<void> _createKey(String password, Map<String, dynamic> own) async {
    final userId = _requireUserId();
    // 新私钥要用真正的登录密码包装：别的设备登录时只会拿登录密码去解。
    if (!await _verifyPassword(password)) {
      throw const E2eeWrongPasswordException();
    }
    final versions = _wrappedKeys(own).map((key) => key.version);
    final nextVersion =
        (versions.isEmpty ? 0 : versions.reduce((a, b) => a > b ? a : b)) + 1;
    final pair = await E2eeCrypto.generateKeyPair(nextVersion);
    final wrapped = await E2eeCrypto.wrapPrivateKey(
      password: password,
      userId: userId,
      keyPair: pair,
      argon2Params: _wrapArgon2Params,
    );
    final response = await _request('POST', ApiConstants.e2eeCreateKey, body: {
      'keyVersion': nextVersion,
      'publicKey': wrapped.publicKey,
      'wrappedPrivateKey': wrapped.wrappedPrivateKey,
      'wrapSalt': wrapped.wrapSalt,
      'wrapParams': wrapped.wrapParams,
      'expectedActiveKeyVersion': own['activeKeyVersion'],
    });
    if (response.statusCode == 409) {
      throw const E2eeException('加密密钥刚在其他设备上更新过，请重新打开设置后再试');
    }
    if (response.statusCode != 200) {
      throw E2eeException(_errorMessage(response, '开启端到端加密失败'));
    }
    _myKeys[pair.version] = pair;
    await _persistKeys();
    _lastKnownSelfEnabled = true;
    _afterKeysChanged();
  }

  /// 改密码时附在请求里的字段：用新密码重新包装本账号的每一把私钥。
  /// 本机还没解开的先用旧密码解；当前那把解不开就不让改（否则会丢掉加密历史）。
  Future<Map<String, dynamic>> passwordChangeExtras(
    String oldPassword,
    String newPassword,
  ) async {
    await ensureLoaded();
    final Map<String, dynamic> own;
    try {
      own = await _fetchOwnKeys();
    } on E2eeException catch (e) {
      if (e.message == _unsupportedServerMessage) return const {};
      rethrow;
    }
    final wrapped = _wrappedKeys(own);
    if (wrapped.isEmpty) return const {};
    final userId = _requireUserId();
    final derived = <String, Uint8List>{};
    for (final key in wrapped) {
      if (_myKeys.containsKey(key.version)) continue;
      try {
        _myKeys[key.version] = await E2eeCrypto.unwrapPrivateKey(
          password: oldPassword,
          userId: userId,
          wrapped: key,
          derivedKeyCache: derived,
        );
      } on E2eeCryptoException {
        // 以前某次密码重置前的旧密钥：本来就解不开，保持原样。
      }
    }
    final active = (own['activeKeyVersion'] as num?)?.toInt();
    if (active != null && !_myKeys.containsKey(active)) {
      throw const E2eeException('无法解开当前的端到端加密密钥，请先在设置里重置端到端加密');
    }
    final salt = e2eeRandomBytes(16);
    final wrapKey = await E2eeCrypto.deriveWrapKey(
      password: newPassword,
      salt: salt,
      argon2Params: _wrapArgon2Params,
    );
    final wraps = [
      for (final key in wrapped)
        if (_myKeys[key.version] != null)
          E2eeCrypto.wrapPrivateKeyWithDerivedKey(
            wrapKey: wrapKey,
            salt: salt,
            argon2Params: _wrapArgon2Params,
            userId: userId,
            keyPair: _myKeys[key.version]!,
          ).toWrapJson(),
    ];
    await _persistKeys();
    return {'e2eeKeyWraps': wraps};
  }

  void _afterKeysChanged() {
    _roomStates.clear();
    _reveals.removeWhere((_, value) => !value.isReadable);
    notifyListeners();
  }

  // ---------------------------------------------------------------- HTTP

  static const _unsupportedServerMessage = '服务器暂不支持端到端加密';

  Future<Map<String, dynamic>> _fetchOwnKeys() async {
    final response = await _request('GET', ApiConstants.e2eeMyKeys);
    if (response.statusCode == 404) {
      throw const E2eeException(_unsupportedServerMessage);
    }
    final data = response.statusCode == 200 ? _data(response) : null;
    if (data == null) {
      throw E2eeException(_errorMessage(response, '获取加密密钥失败'));
    }
    return data;
  }

  Future<void> _put(String url, Map<String, dynamic> body) async {
    final response = await _request('PUT', url, body: body);
    if (response.statusCode != 200) {
      throw E2eeException(_errorMessage(response, '操作失败'));
    }
  }

  List<E2eeWrappedKey> _wrappedKeys(Map<String, dynamic> own) {
    final keys = own['keys'];
    if (keys is! List) return const [];
    return [
      for (final item in keys.whereType<Map>())
        E2eeWrappedKey(
          version: (item['version'] as num).toInt(),
          publicKey: item['publicKey'].toString(),
          wrappedPrivateKey: item['wrappedPrivateKey'].toString(),
          wrapSalt: item['wrapSalt'].toString(),
          wrapParams: item['wrapParams'].toString(),
        ),
    ];
  }

  String _requireUserId() {
    final userId = _currentUserId();
    if (userId == null) throw const E2eeException('请先登录');
    return userId;
  }

  Map<String, dynamic>? _data(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final data = decoded is Map ? decoded['data'] : null;
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  String _errorMessage(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        final message = (decoded['message'] ?? decoded['error'])?.toString();
        if (message != null && message.isNotEmpty) return message;
      }
    } catch (_) {
      // 用默认提示。
    }
    return fallback;
  }
}
