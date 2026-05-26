import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> saveBytesAsFile({
  required List<int> bytes,
  required String name,
  String? mimeType,
}) async {
  final url = _createObjectUrl(bytes, mimeType);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
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

String _createObjectUrl(List<int> bytes, String? mimeType) {
  final typedBytes = Uint8List.fromList(bytes).toJS;
  final blob = web.Blob(
    [typedBytes].toJS,
    web.BlobPropertyBag(type: mimeType ?? 'application/octet-stream'),
  );
  return web.URL.createObjectURL(blob);
}
