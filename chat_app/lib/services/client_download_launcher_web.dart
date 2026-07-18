import 'package:web/web.dart' as web;

Future<bool> launchClientDownload(
  String url, {
  required String filename,
}) async {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return true;
}
