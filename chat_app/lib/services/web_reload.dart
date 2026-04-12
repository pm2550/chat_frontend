/// Conditional import: uses the real web implementation on web,
/// and a no-op stub on native platforms.
export 'web_reload_stub.dart'
    if (dart.library.js_interop) 'web_reload_web.dart';
