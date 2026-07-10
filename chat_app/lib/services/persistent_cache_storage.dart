import 'persistent_cache_storage_prefs.dart'
    if (dart.library.html) 'persistent_cache_storage_web.dart' as platform;

Future<String?> readPersistentCacheValue(String key) => platform.read(key);

Future<void> writePersistentCacheValue(String key, String value) =>
    platform.write(key, value);

Future<void> deletePersistentCachePrefix(String prefix) =>
    platform.deletePrefix(prefix);
