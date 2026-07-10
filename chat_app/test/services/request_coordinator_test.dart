import 'dart:async';

import 'package:chat_app/services/request_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(RequestCoordinator.clearForTesting);

  test('shares an identical in-flight read and releases it on success',
      () async {
    final completer = Completer<int>();
    var calls = 0;

    Future<int> load() {
      calls += 1;
      return completer.future;
    }

    final first = RequestCoordinator.run<int>('room-list', load);
    final second = RequestCoordinator.run<int>('room-list', load);
    expect(calls, 1);

    completer.complete(7);
    expect(await Future.wait([first, second]), [7, 7]);
    await Future<void>.delayed(Duration.zero);

    expect(await RequestCoordinator.run<int>('room-list', () async => 8), 8);
    expect(calls, 1);
  });

  test('releases a failed read so retry can run', () async {
    var calls = 0;
    Future<int> load() async {
      calls += 1;
      if (calls == 1) throw StateError('offline');
      return 9;
    }

    await expectLater(
      RequestCoordinator.run<int>('contacts', load),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    expect(await RequestCoordinator.run<int>('contacts', load), 9);
    expect(calls, 2);
  });
}
