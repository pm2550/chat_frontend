import 'package:shared_preferences/shared_preferences.dart';

const String _storagePrefix = 'pmchat.performance.cache.';

Future<String?> read(String key) async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.getString('$_storagePrefix$key');
}

Future<void> write(String key, String value) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString('$_storagePrefix$key', value);
}

Future<void> deletePrefix(String prefix) async {
  final preferences = await SharedPreferences.getInstance();
  final matchingKeys = preferences
      .getKeys()
      .where((key) => key.startsWith('$_storagePrefix$prefix'))
      .toList(growable: false);
  for (final key in matchingKeys) {
    await preferences.remove(key);
  }
}
