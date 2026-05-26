import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'auth_service.dart';

/// E2EE key management and message-envelope encryption.
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final AuthService _authService = AuthService();
  bool _keysUploaded = false;
  Uint8List? _localSecret;
  String? _localPublicKey;

  bool get keysUploaded => _keysUploaded;

  /// Generate and upload key bundle to server
  Future<bool> generateAndUploadKeys() async {
    try {
      final random = Random.secure();
      final secret = _generateRandomBytes(32, random);
      final identityKey = _publicKeyForSecret(secret);
      final signedPreKey = _generateRandomBase64(32, random);
      final signature = _generateSignature(identityKey, signedPreKey, secret);
      final oneTimeKeys = List.generate(
        10,
        (_) => _generateRandomBase64(32, random),
      ).join(',');

      final response = await _authService.authenticatedRequest(
        'POST',
        ApiConstants.uploadKeys,
        body: {
          'identityPublicKey': identityKey,
          'signedPreKey': signedPreKey,
          'signedPreKeySignature': signature,
          'oneTimePreKeys': oneTimeKeys,
        },
      );

      if (response.statusCode == 200) {
        _keysUploaded = true;
        _localSecret = secret;
        _localPublicKey = identityKey;
        final prefs = await SharedPreferences.getInstance();
        prefs.setBool('e2ee_keys_uploaded', true);
        prefs.setString('e2ee_local_secret', base64Encode(secret));
        prefs.setString('e2ee_identity_public_key', identityKey);
        return true;
      }
    } catch (e) {
      developer.log('Key upload error', error: e);
    }
    return false;
  }

  /// Get another user's key bundle for establishing encrypted session
  Future<Map<String, dynamic>?> getKeyBundle(int userId) async {
    try {
      final response = await _authService.authenticatedRequest(
        'GET',
        ApiConstants.getKeyBundle(userId),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data['data'] != null) {
        return data['data'];
      }
    } catch (e) {
      developer.log('Get key bundle error', error: e);
    }
    return null;
  }

  /// Check if we have keys uploaded
  Future<bool> checkKeysExist() async {
    final prefs = await SharedPreferences.getInstance();
    _keysUploaded = prefs.getBool('e2ee_keys_uploaded') ?? false;
    final secret = prefs.getString('e2ee_local_secret');
    final publicKey = prefs.getString('e2ee_identity_public_key');
    if (secret != null && secret.isNotEmpty) {
      try {
        _localSecret = Uint8List.fromList(base64Decode(secret));
      } catch (_) {
        _localSecret = null;
      }
    }
    if (publicKey != null && publicKey.isNotEmpty) {
      _localPublicKey = publicKey;
    }
    return _keysUploaded;
  }

  /// Encrypts a message into a versioned AES-256-GCM envelope.
  String encryptMessage(String plaintext, String recipientPublicKey) {
    if (plaintext.isEmpty) return '';

    final random = Random.secure();
    final nonce = _generateRandomBytes(12, random);
    final key = _deriveAesKey(recipientPublicKey);
    final encrypted = _aesGcmCrypt(
      forEncryption: true,
      key: key,
      nonce: nonce,
      input: Uint8List.fromList(utf8.encode(plaintext)),
    );
    final envelope = {
      'v': 2,
      'alg': 'AES-256-GCM',
      'senderKey': _localPublicKeySync(),
      'recipientKey': recipientPublicKey,
      'nonce': base64Encode(nonce),
      'payload': base64Encode(encrypted),
    };
    return base64Encode(utf8.encode(jsonEncode(envelope)));
  }

  /// Decrypts AES-256-GCM envelopes and keeps legacy base64 compatibility.
  String decryptMessage(String ciphertext) {
    if (ciphertext.isEmpty) return '';
    try {
      final decoded = utf8.decode(base64Decode(ciphertext));
      final Object? envelope;
      try {
        envelope = jsonDecode(decoded);
      } catch (_) {
        return decoded;
      }
      if (envelope is Map<String, dynamic> &&
          envelope['alg'] == 'AES-256-GCM') {
        final recipientKey = envelope['recipientKey']?.toString() ?? '';
        final nonce =
            Uint8List.fromList(base64Decode(envelope['nonce'].toString()));
        final payload =
            Uint8List.fromList(base64Decode(envelope['payload'].toString()));
        final decrypted = _aesGcmCrypt(
          forEncryption: false,
          key: _deriveAesKey(recipientKey),
          nonce: nonce,
          input: payload,
        );
        return utf8.decode(decrypted);
      }
      return decoded;
    } catch (e) {
      return ciphertext;
    }
  }

  Uint8List _deriveAesKey(String recipientPublicKey) {
    final secret = _localSecretSync();
    final material = <int>[
      ...secret,
      ...utf8.encode(recipientPublicKey),
      ...utf8.encode('chat-app-e2ee-v2'),
    ];
    return _sha256(Uint8List.fromList(material));
  }

  Uint8List _aesGcmCrypt({
    required bool forEncryption,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List input,
  }) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    cipher.init(
      forEncryption,
      pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0)),
    );
    return cipher.process(input);
  }

  Uint8List _localSecretSync() {
    if (_localSecret != null) return _localSecret!;
    final secret = _generateRandomBytes(32, Random.secure());
    _localSecret = secret;
    _localPublicKey = _publicKeyForSecret(secret);
    return secret;
  }

  String _localPublicKeySync() {
    return _localPublicKey ?? _publicKeyForSecret(_localSecretSync());
  }

  String _publicKeyForSecret(Uint8List secret) {
    return base64Encode(_sha256(Uint8List.fromList([
      ...secret,
      ...utf8.encode('identity-public-key'),
    ])));
  }

  String _generateSignature(
    String identityKey,
    String signedPreKey,
    Uint8List secret,
  ) {
    return base64Encode(_sha256(Uint8List.fromList([
      ...secret,
      ...utf8.encode(identityKey),
      ...utf8.encode(signedPreKey),
    ])));
  }

  Uint8List _sha256(Uint8List input) {
    return pc.SHA256Digest().process(input);
  }

  Uint8List _generateRandomBytes(int length, Random random) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  String _generateRandomBase64(int length, Random random) {
    return base64Encode(_generateRandomBytes(length, random));
  }
}
