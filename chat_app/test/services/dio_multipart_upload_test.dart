import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chat_app/services/chat_upload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';

/// 默认上传传输（dio）对着真实的本地 HTTP 服务器：进度、字段、取消都是真的。
/// 单独成文件：同文件里有 testWidgets 的话测试绑定会把真实 HttpClient 换掉。
void main() {
  group('dioMultipartUpload against a real HTTP server', () {
    late HttpServer server;
    late Completer<void> releaseResponse;
    final received = <String>[];

    setUp(() async {
      releaseResponse = Completer<void>();
      received.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decodeStream(request);
        received
          ..add(request.headers.value('authorization') ?? '')
          ..add(body);
        if (request.uri.path == '/slow') await releaseResponse.future;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'ok': true}));
        await request.response.close();
      });
    });

    tearDown(() async {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
      await server.close(force: true);
    });

    test('streams the multipart body with progress', () async {
      final progress = <int>[];
      var lastTotal = 0;
      final response = await dioMultipartUpload(
        'http://127.0.0.1:${server.port}/upload',
        headers: {'Authorization': 'Bearer t'},
        fields: {'chatRoomId': '42', 'clientMessageId': 'local-9'},
        fileField: 'file',
        fileName: 'a.bin',
        bytes: List<int>.filled(256 * 1024, 7),
        contentType: MediaType('application', 'octet-stream'),
        onSendProgress: (sent, total) {
          progress.add(sent);
          lastTotal = total;
        },
      );

      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), {'ok': true});
      expect(received[0], 'Bearer t');
      expect(received[1], contains('name="clientMessageId"'));
      expect(received[1], contains('filename="a.bin"'));
      expect(progress, isNotEmpty);
      expect(lastTotal, greaterThan(256 * 1024));
      expect(progress.last, lastTotal);
    });

    test('cancel aborts a request that is waiting on the server', () async {
      final cancel = UploadCancelToken();
      final future = dioMultipartUpload(
        'http://127.0.0.1:${server.port}/slow',
        headers: const {},
        fields: const {},
        fileField: 'file',
        fileName: 'a.bin',
        bytes: const [1, 2, 3],
        cancelToken: cancel,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      cancel.cancel();
      await expectLater(future, throwsA(isA<UploadCancelledException>()));
    });
  });
}
