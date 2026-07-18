import 'client_download_launcher_stub.dart'
    if (dart.library.js_interop) 'client_download_launcher_web.dart' as platform;

Future<bool> launchClientDownload(
  String url, {
  required String filename,
}) {
  return platform.launchClientDownload(url, filename: filename);
}
