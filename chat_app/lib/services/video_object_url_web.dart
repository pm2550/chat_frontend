import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String?> createVideoObjectUrl({
  required List<int> bytes,
  String? mimeType,
}) async {
  final typedBytes = Uint8List.fromList(bytes).toJS;
  final blob = web.Blob(
    [typedBytes].toJS,
    web.BlobPropertyBag(type: mimeType ?? 'video/mp4'),
  );
  return web.URL.createObjectURL(blob);
}

void revokeVideoObjectUrl(String? url) {
  if (url == null || url.isEmpty) return;
  web.URL.revokeObjectURL(url);
}
