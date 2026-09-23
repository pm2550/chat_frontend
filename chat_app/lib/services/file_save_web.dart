import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_save_result.dart';

export 'file_save_result.dart';

Future<FileSaveResult> saveBytesAsFile({
  required List<int> bytes,
  required String name,
  String? mimeType,
}) async {
  final safeName = sanitizeSaveFileName(name);
  // iPhone/iPad: an <a download> lands in the Files app (or does nothing in
  // a home-screen web app), never in Photos. The share sheet offers
  // "存储图像/存储视频", which is what people mean by saving a picture.
  if (_isAppleMobile() &&
      saveMediaKindFor(safeName, mimeType) != SaveMediaKind.other) {
    final shared = await _tryShareFile(bytes, safeName, mimeType);
    if (shared != null) return shared;
  }

  final url = _createObjectUrl(bytes, mimeType);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = safeName;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Revoking synchronously can cancel the download in Safari/Firefox.
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  return const FileSaveResult.saved(FileSaveDestination.browserDownloads);
}

Future<bool> openBytesInNewTab({
  required List<int> bytes,
  required String name,
  String? mimeType,
}) async {
  final url = _createObjectUrl(bytes, mimeType);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..target = '_blank'
    ..rel = 'noopener';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
  return true;
}

/// Returns null when sharing is unavailable or refused (e.g. the tap's user
/// activation already expired), so the caller falls back to a download.
Future<FileSaveResult?> _tryShareFile(
  List<int> bytes,
  String name,
  String? mimeType,
) async {
  try {
    final file = web.File(
      [Uint8List.fromList(bytes).toJS].toJS,
      name,
      web.FilePropertyBag(type: mimeType ?? 'application/octet-stream'),
    );
    final data = web.ShareData(files: [file].toJS);
    if (!web.window.navigator.canShare(data)) return null;
    // Read the rejection reason on the JS side: how a caught JS exception
    // surfaces in Dart differs between dart2js and wasm builds.
    final outcome = await web.window.navigator
        .share(data)
        ._settle(
          ((JSAny? _) => 'shared'.toJS).toJS,
          ((JSAny? reason) => _rejectionName(reason).toJS).toJS,
        )
        .toDart;
    switch (outcome.toDart) {
      case 'shared':
        return const FileSaveResult.saved(FileSaveDestination.shareSheet);
      case 'AbortError':
        return const FileSaveResult.cancelled();
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

extension on JSPromise<JSAny?> {
  @JS('then')
  external JSPromise<JSString> _settle(
    JSFunction onFulfilled,
    JSFunction onRejected,
  );
}

String _rejectionName(JSAny? reason) {
  if (reason != null && reason.isA<web.DOMException>()) {
    return (reason as web.DOMException).name;
  }
  return 'unknown';
}

bool _isAppleMobile() {
  final navigator = web.window.navigator;
  final ua = navigator.userAgent;
  if (RegExp('iPhone|iPad|iPod').hasMatch(ua)) return true;
  // iPadOS reports itself as a Mac; touch support gives it away.
  return navigator.platform == 'MacIntel' && navigator.maxTouchPoints > 1;
}

String _createObjectUrl(List<int> bytes, String? mimeType) {
  final typedBytes = Uint8List.fromList(bytes).toJS;
  final blob = web.Blob(
    [typedBytes].toJS,
    web.BlobPropertyBag(type: mimeType ?? 'application/octet-stream'),
  );
  return web.URL.createObjectURL(blob);
}
