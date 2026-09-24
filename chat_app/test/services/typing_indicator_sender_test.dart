import 'package:chat_app/services/typing_indicator_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<bool> sent;
  late DateTime now;
  late TypingIndicatorSender sender;

  setUp(() {
    sent = [];
    now = DateTime(2026, 9, 24, 10);
    sender = TypingIndicatorSender(send: sent.add, clock: () => now);
  });

  test('first keystroke announces typing, later ones are throttled', () {
    sender.onTextChanged('h');
    sender.onTextChanged('he');
    now = now.add(const Duration(milliseconds: 1500));
    sender.onTextChanged('hel');

    expect(sent, [true]);
  });

  test('keeps refreshing while typing so the server does not expire it', () {
    sender.onTextChanged('h');
    now = now.add(const Duration(seconds: 2));
    sender.onTextChanged('he');

    expect(sent, [true, true]);
  });

  test('clearing the composer (send or delete all) stops typing once', () {
    sender.onTextChanged('hello');
    sender.onTextChanged('');
    sender.onTextChanged('   ');
    sender.stop();

    expect(sent, [true, false]);
  });

  test('moving the cursor without changing text is not typing', () {
    sender.onTextChanged('hello');
    sender.stop();
    sender.onTextChanged('hello');

    expect(sent, [true, false]);
  });

  test('stop without having typed sends nothing', () {
    sender.stop();
    sender.onTextChanged('');

    expect(sent, isEmpty);
  });
}
