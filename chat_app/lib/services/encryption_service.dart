import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'auth_service.dart';

/// Simplified E2EE key management service.
/// In production, integrate libsignal_protocol_dart for full Signal Protocol.
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final AuthService _authService = AuthService();
  bool _keysUploaded = false;

  bool get keysUploaded => _keysUploaded;

  /// Generate and upload key bundle to server
  Future<bool> generateAndUploadKeys() async {
    try {
      // Generate placeholder keys (replace with real Signal Protocol keys)
      final random = Random.secure();
      final identityKey = _generateRandomBase64(32, random);
      final signedPreKey = _generateRandomBase64(32, random);
      final signature = _generateRandomBase64(64, random);
      final oneTimeKeys = List.generate(10, (_) => _generateRandomBase64(32, random)).join(',');

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
        // Save locally
        final prefs = await SharedPreferences.getInstance();
        prefs.setBool('e2ee_keys_uploaded', true);
        return true;
      }
    } catch (e) {
      print('Key upload error: $e');
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
      print('Get key bundle error: $e');
    }
    return null;
  }

  /// Check if we have keys uploaded
  Future<bool> checkKeysExist() async {
    final prefs = await SharedPreferences.getInstance();
    _keysUploaded = prefs.getBool('e2ee_keys_uploaded') ?? false;
    return _keysUploaded;
  }

  /// Encrypt a message (placeholder - replace with Signal Protocol)
  String encryptMessage(String plaintext, String recipientPublicKey) {
    // TODO: Implement real Signal Protocol encryption
    // For now, return base64 encoded content as placeholder
    return base64Encode(utf8.encode(plaintext));
  }

  /// Decrypt a message (placeholder - replace with Signal Protocol)
  String decryptMessage(String ciphertext) {
    // TODO: Implement real Signal Protocol decryption
    try {
      return utf8.decode(base64Decode(ciphertext));
    } catch (e) {
      return ciphertext;
    }
  }

  String _generateRandomBase64(int length, Random random) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Encode(bytes);
  }
}
