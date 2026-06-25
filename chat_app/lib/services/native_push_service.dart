import 'native_push_stub.dart' if (dart.library.io) 'native_push_io.dart'
    as platform;

class NativePushService {
  static final NativePushService _instance = NativePushService._internal();
  factory NativePushService() => _instance;
  NativePushService._internal();

  Future<void> initialize() => platform.initializeNativePush();
}
