import 'dart:async';

import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// 上传进度：已经发出去的字节数 / 请求体总字节数（总数未知时为 -1 或 0）。
typedef UploadProgressCallback = void Function(int sentBytes, int totalBytes);

/// 取消一次上传。取消后正在进行的请求会被真正中止（web 上是 XHR.abort）。
class UploadCancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() => '已取消上传';
}

/// 整个上传超过了按文件大小算出的时限。继承 [TimeoutException]，
/// 调用方按超时统一处理。
class UploadTimeoutException extends TimeoutException {
  UploadTimeoutException(Duration duration) : super('网络超时', duration);

  @override
  String toString() => '网络超时';
}

/// 和主文件一起发的额外文件字段（例如加密图片的小预览图）。
class MultipartExtraFile {
  const MultipartExtraFile({
    required this.field,
    required this.fileName,
    required this.bytes,
    this.contentType,
  });

  final String field;
  final String fileName;
  final List<int> bytes;
  final MediaType? contentType;
}

/// 一次带进度、可取消的 multipart 上传。只负责把一个请求发出去，
/// 鉴权刷新、超时由调用方（ChatDataService）处理。
typedef MultipartUploadTransport = Future<http.Response> Function(
  String url, {
  required Map<String, String> headers,
  required Map<String, String> fields,
  required String fileField,
  required String fileName,
  List<int>? bytes,
  String? path,
  MediaType? contentType,
  List<MultipartExtraFile> extraFiles,
  UploadProgressCallback? onSendProgress,
  UploadCancelToken? cancelToken,
});

/// 上传的硬时限：至少 2 分钟，每 MB 再多给 20 秒（约按 50KB/s 的最差网速估）。
/// 固定 2 分钟会把慢网下的大文件必然判死；无限等又会让气泡永远转圈。
Duration uploadTimeoutForBytes(int bytes) {
  const base = Duration(minutes: 2);
  if (bytes <= 0) return base;
  final perMegabyteSeconds = (bytes * 20 / (1024 * 1024)).ceil();
  return base + Duration(seconds: perMegabyteSeconds);
}

final dio.Dio _uploadDio = dio.Dio();

/// 默认实现：dio 在 web 上走 XHR（有 upload.onprogress），原生走 HttpClient，
/// 两边都能报上传进度、都能中止。`http` 包的 BrowserClient 拿不到上传进度。
Future<http.Response> dioMultipartUpload(
  String url, {
  required Map<String, String> headers,
  required Map<String, String> fields,
  required String fileField,
  required String fileName,
  List<int>? bytes,
  String? path,
  MediaType? contentType,
  List<MultipartExtraFile> extraFiles = const [],
  UploadProgressCallback? onSendProgress,
  UploadCancelToken? cancelToken,
}) async {
  final dio.MultipartFile part;
  if (bytes != null) {
    part = dio.MultipartFile.fromBytes(
      bytes,
      filename: fileName,
      contentType: contentType,
    );
  } else if (path != null && path.isNotEmpty) {
    part = await dio.MultipartFile.fromFile(
      path,
      filename: fileName,
      contentType: contentType,
    );
  } else {
    throw ArgumentError('multipart upload needs bytes or path');
  }
  final form = dio.FormData.fromMap({
    ...fields,
    fileField: part,
    for (final extra in extraFiles)
      extra.field: dio.MultipartFile.fromBytes(
        extra.bytes,
        filename: extra.fileName,
        contentType: extra.contentType,
      ),
  });

  final dioCancel = dio.CancelToken();
  if (cancelToken != null) {
    if (cancelToken.isCancelled) throw const UploadCancelledException();
    unawaited(cancelToken.whenCancelled.then((_) {
      if (!dioCancel.isCancelled) dioCancel.cancel('upload cancelled');
    }));
  }

  try {
    final response = await _uploadDio.post<List<int>>(
      url,
      data: form,
      cancelToken: dioCancel,
      onSendProgress: onSendProgress,
      options: dio.Options(
        headers: headers,
        responseType: dio.ResponseType.bytes,
        // 非 2xx 也照常返回，由 ChatDataService 统一解析错误、处理 401 刷新。
        validateStatus: (_) => true,
      ),
    );
    final responseHeaders = <String, String>{
      for (final entry in response.headers.map.entries)
        entry.key.toLowerCase(): entry.value.join(','),
    };
    return http.Response.bytes(
      response.data ?? const <int>[],
      response.statusCode ?? 0,
      headers: responseHeaders,
    );
  } on dio.DioException catch (error) {
    if (dio.CancelToken.isCancel(error)) {
      throw const UploadCancelledException();
    }
    throw http.ClientException(
      error.message ?? error.error?.toString() ?? '网络错误',
      Uri.tryParse(url),
    );
  }
}
