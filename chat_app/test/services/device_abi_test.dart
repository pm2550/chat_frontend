import 'dart:async';
import 'dart:convert';

import 'package:chat_app/models/app_version.dart';
import 'package:chat_app/services/device_abi.dart';
import 'package:chat_app/services/update_service.dart';
import 'package:chat_app/services/websocket_service.dart';
import 'package:chat_app/widgets/app_update_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fake_web_socket_channel.dart';

void main() {
  group('DeviceAbi.pick', () {
    test('64-bit phones get the arm64 APK', () {
      expect(
        DeviceAbi.pick(['arm64-v8a', 'armeabi-v7a', 'armeabi']),
        'arm64-v8a',
      );
      // 只支持 64 位的新手机（不再带 32 位运行库）。
      expect(DeviceAbi.pick(['arm64-v8a']), 'arm64-v8a');
    });

    test('32-bit-only phones get the armeabi-v7a APK', () {
      expect(DeviceAbi.pick(['armeabi-v7a', 'armeabi']), 'armeabi-v7a');
    });

    test('emulators with ARM translation still pick an ARM build', () {
      expect(DeviceAbi.pick(['x86_64', 'arm64-v8a']), 'arm64-v8a');
    });

    test('devices with no published ABI report none', () {
      expect(DeviceAbi.pick(['x86_64', 'x86']), isNull);
      expect(DeviceAbi.pick(const []), isNull);
    });
  });

  group('UpdateService.checkForUpdate', () {
    test('asks for the APK of this phone\'s ABI and returns its URL/size/sha',
        () async {
      Uri? requested;
      final client = _FakeClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'updateAvailable': true,
            'latestVersion': '1.1.52',
            'latestVersionCode': 11052,
            'downloadUrl':
                '/api/v1/app/download/android/pm-chat-android-armeabi-v7a-v1.1.52-11052.apk',
            'fileSize': 49000000,
            'sha256': 'ab' * 32,
            'abi': 'armeabi-v7a',
          }),
          200,
        );
      });

      final check = await UpdateService.checkForUpdate(
        client: client,
        platform: 'ANDROID',
        currentVersionCode: () async => 11051,
        deviceAbi: () async => 'armeabi-v7a',
      );

      expect(requested!.queryParameters, {
        'platform': 'ANDROID',
        'currentVersionCode': '11051',
        'abi': 'armeabi-v7a',
      });
      // 更新对话框下载、校验、安装都用这几个字段。
      expect(check.updateAvailable, isTrue);
      expect(
        check.downloadUrl,
        '/api/v1/app/download/android/pm-chat-android-armeabi-v7a-v1.1.52-11052.apk',
      );
      expect(check.fileSize, 49000000);
      expect(check.sha256, 'ab' * 32);
      expect(check.abi, 'armeabi-v7a');
    });

    test('without a detected ABI the request falls back to the server default',
        () async {
      Uri? requested;
      final client = _FakeClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode({'updateAvailable': false}), 200);
      });

      await UpdateService.checkForUpdate(
        client: client,
        platform: 'ANDROID',
        currentVersionCode: () async => 11052,
        deviceAbi: () async => null,
      );

      expect(requested!.queryParameters.containsKey('abi'), isFalse);
    });

    test('non-Android platforms never send an ABI', () async {
      Uri? requested;
      final client = _FakeClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode({'updateAvailable': false}), 200);
      });

      await UpdateService.checkForUpdate(
        client: client,
        platform: 'WINDOWS',
        currentVersionCode: () async => 11052,
        deviceAbi: () async => fail('desktop must not look up an ABI'),
      );

      expect(requested!.queryParameters['platform'], 'WINDOWS');
      expect(requested!.queryParameters.containsKey('abi'), isFalse);
    });
  });

  group('update push ABI filter', () {
    test('only a known mismatch is ignored', () {
      expect(
        UpdateService.shouldHandleUpdateForAbi('arm64-v8a', 'armeabi-v7a'),
        isFalse,
      );
      expect(
        UpdateService.shouldHandleUpdateForAbi('armeabi-v7a', 'armeabi-v7a'),
        isTrue,
      );
      // 整包 / 旧服务器没有 abi 字段；非 Android 不知道自己的 abi。
      expect(UpdateService.shouldHandleUpdateForAbi(null, 'armeabi-v7a'),
          isTrue);
      expect(UpdateService.shouldHandleUpdateForAbi('arm64-v8a', null), isTrue);
    });

    testWidgets('a 32-bit phone does not prompt for the 64-bit APK',
        (tester) async {
      final events = StreamController<Map<String, dynamic>>();
      final shown = <AppVersionCheck>[];

      await tester.pumpWidget(MaterialApp(
        home: AppUpdateListener(
          updateEvents: events.stream,
          currentPlatform: 'ANDROID',
          deviceAbi: () async => 'armeabi-v7a',
          showUpdate: (context, check) async => shown.add(check),
          child: const Scaffold(body: Text('home')),
        ),
      ));

      Map<String, dynamic> push(String abi) => {
            'type': 'app_update_available',
            'platform': 'ANDROID',
            'versionName': '1.1.52',
            'versionCode': 11052,
            'abi': abi,
            'downloadUrl':
                '/api/v1/app/download/android/pm-chat-android-$abi-v1.1.52-11052.apk',
          };

      events.add(push('arm64-v8a'));
      await tester.pumpAndSettle();
      expect(shown, isEmpty);

      events.add(push('armeabi-v7a'));
      await tester.pumpAndSettle();
      expect(shown, hasLength(1));
      expect(shown.single.abi, 'armeabi-v7a');
      expect(shown.single.downloadUrl, contains('armeabi-v7a'));

      await events.close();
    });
  });

  group('WebSocket handshake', () {
    tearDown(() => DeviceAbi.debugOverride = null);

    Future<Uri> connectAndCaptureUri() async {
      Uri? uri;
      final service = WebSocketService.forTesting(
        authService: SocketAuthService(),
        channelFactory: (value) {
          uri = value;
          return FakeWebSocketChannel();
        },
      );
      await service.connect();
      service.disconnect();
      return uri!;
    }

    test('reports the phone ABI so update pushes carry the right APK',
        () async {
      DeviceAbi.debugOverride = () async => 'armeabi-v7a';

      final uri = await connectAndCaptureUri();

      expect(uri.queryParameters['abi'], 'armeabi-v7a');
      expect(uri.queryParameters['token'], 'test-access-token');
    });

    test('clients without an ABI (web, desktop) connect as before', () async {
      DeviceAbi.debugOverride = () async => null;

      final uri = await connectAndCaptureUri();

      expect(uri.queryParameters.containsKey('abi'), isFalse);
    });
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}
