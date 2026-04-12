import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Force-reload the web page to pick up the latest service worker + assets.
void reloadWebPage() {
  web.window.location.reload();
}
