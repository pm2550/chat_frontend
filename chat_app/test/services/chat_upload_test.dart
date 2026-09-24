import 'dart:async';
import 'dart:convert';

import 'package:chat_app/services/auth_service.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/chat_upload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class _TokenAuthService extends AuthService {
  _TokenAuthService() : super.test();

  String token = 'old-token';
  int refreshCount = 0;

  @override
  String? get accessToken => token;

  @override
  Future<bool> refreshAccessToken() async {
    refreshCount += 1;
    token = 'new-token';
    return true;
  }
}

/// 记录每次传输调用，由测试决定它何时、怎样结束。
class _TransportCall {
  _TransportCall(this.headers, this.fields, this.fileName, this.onSendProgress,
      this.cancelToken);

  final Map<String, String> headers;
  final Map<String, String> fields;
  final String fileName;
  final UploadProgressCallback? onSendProgress;
  final UploadCancelToken? cancelToken;
  final Completer<http.Response> response = Completer<http.Response>();
}

class _FakeTransport {
  final List<_TransportCall> calls = [];

  Future<http.Response> call(
    String url, {
    required Map<String, String> headers,
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    List<int>? bytes,
    String? path,
    MediaType? contentType,
    UploadProgressCallback? onSendProgress,
    UploadCancelToken? cancelToken,
  }) {
    final call =
        _TransportCall(headers, fields, fileName, onSendProgress, cancelToken);
    calls.add(call);
    cancelToken?.whenCancelled.then((_) {
      if (!call.response.isCompleted) {
        call.response.completeError(const UploadCancelledException());
      }
    });
    return call.response.future;
  }
}

http.Response _fileMessageResponse({int statusCode = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(statusCode == 200
          ? {
              'data': {
                'id': 900,
                'content': 'big.zip',
                'messageType': 'FILE',
                'messageStatus': 'SENT',
                'fileName': 'big.zip',
                'createdAt': '2026-09-24T10:00:00',
                'sender': {'id': 1, 'displayName': '我'},
              },
            }
          : {'error': 'JWT expired'})),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _file = PickedChatFile(
  name: 'big.zip',
  size: 3,
  mimeType: 'application/zip',
  bytes: [1, 2, 3],
);

void main() {
  test('upload timeout grows with file size and never drops below 2 minutes',
      () {
    expect(uploadTimeoutForBytes(0), const Duration(minutes: 2));
    expect(uploadTimeoutForBytes(200 * 1024),
        const Duration(minutes: 2, seconds: 4));
    expect(uploadTimeoutForBytes(10 * 1024 * 1024),
        const Duration(minutes: 2, seconds: 200));
  });

  test('sendFileMessage reports real byte progress and sends clientMessageId',
      () async {
    final transport = _FakeTransport();
    final auth = _TokenAuthService();
    final service = ChatDataService(
      authService: auth,
      authenticatedRequest: (method, url, {headers, body}) async =>
          throw UnimplementedError(),
      uploadTransport: transport.call,
    );
    final progress = <String>[];

    final future = service.sendFileMessage(
      '42',
      _file,
      clientMessageId: 'local-1',
      onProgress: (sent, total) => progress.add('$sent/$total'),
    );
    await Future<void>.delayed(Duration.zero);
    final call = transport.calls.single;
    expect(call.headers['Authorization'], 'Bearer old-token');
    expect(call.fields, {'chatRoomId': '42', 'clientMessageId': 'local-1'});
    expect(call.fileName, 'big.zip');
    call.onSendProgress!(1, 3);
    call.onSendProgress!(3, 3);
    call.response.complete(_fileMessageResponse());

    final message = await future;
    expect(progress, ['1/3', '3/3']);
    expect(message.id, '900');
  });

  test('401 refreshes the token and re-sends the upload once', () async {
    final transport = _FakeTransport();
    final auth = _TokenAuthService();
    final service = ChatDataService(
      authService: auth,
      authenticatedRequest: (method, url, {headers, body}) async =>
          throw UnimplementedError(),
      uploadTransport: transport.call,
    );

    final future = service.sendFileMessage('42', _file);
    await Future<void>.delayed(Duration.zero);
    transport.calls[0].response.complete(_fileMessageResponse(statusCode: 401));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(auth.refreshCount, 1);
    expect(transport.calls, hasLength(2));
    expect(transport.calls[1].headers['Authorization'], 'Bearer new-token');
    transport.calls[1].response.complete(_fileMessageResponse());
    expect((await future).id, '900');
  });

  test('cancel aborts the in-flight request', () async {
    final transport = _FakeTransport();
    final service = ChatDataService(
      authService: _TokenAuthService(),
      authenticatedRequest: (method, url, {headers, body}) async =>
          throw UnimplementedError(),
      uploadTransport: transport.call,
    );
    final cancel = UploadCancelToken();

    final future = service.sendFileMessage('42', _file, cancelToken: cancel);
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();

    await expectLater(future, throwsA(isA<UploadCancelledException>()));
    expect(transport.calls.single.cancelToken!.isCancelled, isTrue);
  });

  testWidgets('hitting the size-scaled deadline aborts and reports a timeout',
      (tester) async {
    final transport = _FakeTransport();
    final service = ChatDataService(
      authService: _TokenAuthService(),
      authenticatedRequest: (method, url, {headers, body}) async =>
          throw UnimplementedError(),
      uploadTransport: transport.call,
    );
    Object? failure;
    unawaited(service
        .sendFileMessage('42', _file)
        .then<void>((_) {}, onError: (Object error) => failure = error));
    await tester.pump();
    final call = transport.calls.single;

    // 时限（按大小算，这里是 2 分钟）之前一直等；到了就中止，不会永远挂着。
    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(failure, isNull);
    expect(call.cancelToken!.isCancelled, isFalse);

    await tester.pump(const Duration(seconds: 2));
    expect(call.cancelToken!.isCancelled, isTrue, reason: '超时要真的中止请求');
    expect(failure, isA<UploadTimeoutException>());
    expect(failure, isA<TimeoutException>());
  });
}
