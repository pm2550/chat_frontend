import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS standalone PWA locks outer scroll during keyboard focus', () {
    final html = File('web/index.html').readAsStringSync();

    expect(html, contains('overflow: hidden;'));
    expect(html, contains('position: fixed;'));
    expect(html, contains('installIosPwaKeyboardViewportGuard'));
    expect(html, contains("document.addEventListener('focusin'"));
    expect(html, contains("window.visualViewport.addEventListener('resize'"));
    expect(html, contains('window.scrollTo(0, 0)'));
  });
}
