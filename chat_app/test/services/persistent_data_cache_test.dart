import 'package:chat_app/services/persistent_data_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('isolates snapshots by user and clears only the logged out user',
      () async {
    await PersistentDataCache.write(
      userId: 'alice',
      namespace: 'rooms',
      payload: {'name': 'Alice room'},
    );
    await PersistentDataCache.write(
      userId: 'bob',
      namespace: 'rooms',
      payload: {'name': 'Bob room'},
    );

    expect(
      (await PersistentDataCache.read(
        userId: 'alice',
        namespace: 'rooms',
      ))?['payload'],
      {'name': 'Alice room'},
    );
    await PersistentDataCache.clearUser('alice');
    expect(
      await PersistentDataCache.read(userId: 'alice', namespace: 'rooms'),
      isNull,
    );
    expect(
      (await PersistentDataCache.read(
          userId: 'bob', namespace: 'rooms'))?['payload'],
      {'name': 'Bob room'},
    );
  });
}
