import 'dart:async';

/// Shares identical in-flight reads so cache warmers and visible pages do not
/// compete for the same endpoint on a slow connection.
class RequestCoordinator {
  RequestCoordinator._();

  static final Map<String, Future<dynamic>> _inFlight =
      <String, Future<dynamic>>{};

  static Future<T> run<T>(String key, Future<T> Function() loader) {
    final existing = _inFlight[key];
    if (existing != null) {
      return existing.then((value) => value as T);
    }

    final future = loader();
    _inFlight[key] = future;
    future.then<void>(
      (_) => _removeIfCurrent(key, future),
      onError: (Object _, StackTrace __) => _removeIfCurrent(key, future),
    );
    return future;
  }

  static void _removeIfCurrent(String key, Future<dynamic> future) {
    if (identical(_inFlight[key], future)) {
      _inFlight.remove(key);
    }
  }

  static void clearForTesting() => _inFlight.clear();
}
