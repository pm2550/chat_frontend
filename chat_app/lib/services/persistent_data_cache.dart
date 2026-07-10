import 'dart:convert';

import 'persistent_cache_storage.dart';

class PersistentDataCache {
  PersistentDataCache._();

  static const int schemaVersion = 1;
  static const String _keyPrefix = 'v$schemaVersion:';

  static Future<Map<String, dynamic>?> read({
    required String userId,
    required String namespace,
  }) async {
    if (userId.isEmpty) return null;
    try {
      final encoded = await readPersistentCacheValue(
        _key(userId: userId, namespace: namespace),
      );
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != schemaVersion ||
          decoded['userId'] != userId ||
          decoded['payload'] is! Map<String, dynamic>) {
        return null;
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write({
    required String userId,
    required String namespace,
    required Map<String, dynamic> payload,
  }) async {
    if (userId.isEmpty) return;
    try {
      await writePersistentCacheValue(
        _key(userId: userId, namespace: namespace),
        jsonEncode({
          'schemaVersion': schemaVersion,
          'userId': userId,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'payload': payload,
        }),
      );
    } catch (_) {
      // Cache persistence is best-effort and never blocks the live response.
    }
  }

  static Future<void> clearUser(String userId) {
    if (userId.isEmpty) return Future<void>.value();
    return deletePersistentCachePrefix('$_keyPrefix$userId:');
  }

  static String _key({required String userId, required String namespace}) =>
      '$_keyPrefix$userId:$namespace';
}
