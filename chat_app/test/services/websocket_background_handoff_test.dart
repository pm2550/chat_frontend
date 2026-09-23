import 'package:chat_app/services/websocket_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool handsOff({required bool isWeb, required TargetPlatform platform}) =>
      WebSocketService.shouldHandOffToPushInBackground(
        isWeb: isWeb,
        platform: platform,
      );

  test('phone browsers and PWAs hand off to system push in background', () {
    expect(handsOff(isWeb: true, platform: TargetPlatform.iOS), isTrue);
    expect(handsOff(isWeb: true, platform: TargetPlatform.android), isTrue);
  });

  test('desktop browsers keep the socket so background tabs still get messages',
      () {
    expect(handsOff(isWeb: true, platform: TargetPlatform.windows), isFalse);
    expect(handsOff(isWeb: true, platform: TargetPlatform.macOS), isFalse);
    expect(handsOff(isWeb: true, platform: TargetPlatform.linux), isFalse);
  });

  test('native apps keep the socket because they notify from it in background',
      () {
    expect(handsOff(isWeb: false, platform: TargetPlatform.android), isFalse);
    expect(handsOff(isWeb: false, platform: TargetPlatform.iOS), isFalse);
  });
}
