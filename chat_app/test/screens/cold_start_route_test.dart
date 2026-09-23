import 'package:chat_app/screens/splash_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat deep links survive cold start', () {
    expect(ColdStartRoute.resolve('/chat/591'), '/chat/591');
    expect(ColdStartRoute.resolve('chat/591'), '/chat/591');
    expect(ColdStartRoute.resolve('/chat/591?call=1'), '/chat/591?call=1');
  });

  test('home and a few settings pages are allowed', () {
    expect(ColdStartRoute.resolve('/home'), '/home');
    expect(ColdStartRoute.resolve('/settings'), '/settings');
    expect(ColdStartRoute.resolve('/register'), '/register');
  });

  test('empty or unknown fragments fall back to the default flow', () {
    expect(ColdStartRoute.resolve(''), isNull);
    expect(ColdStartRoute.resolve('/'), isNull);
    expect(ColdStartRoute.resolve('/admin/secret'), isNull);
  });
}
