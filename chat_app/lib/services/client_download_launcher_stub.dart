import 'package:url_launcher/url_launcher.dart';

Future<bool> launchClientDownload(
  String url, {
  required String filename,
}) {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
