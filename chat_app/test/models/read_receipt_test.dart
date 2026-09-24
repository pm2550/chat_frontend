import 'package:chat_app/models/read_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readAt is server UTC and may be missing for read-all readers', () {
    final timed = ReadReceipt.fromJson({
      'userId': 2,
      'username': 'bob',
      'readAt': '2026-09-24T08:00:00',
    });
    expect(timed.readAt!.toUtc(), DateTime.utc(2026, 9, 24, 8));
    expect(timed.displayName, 'bob');

    final untimed = ReadReceipt.fromJson({'userId': 3, 'displayName': '卡罗尔'});
    expect(untimed.readAt, isNull);
  });
}
