import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 原生端的通话画面登记表：通话服务把本地/远端视频放进渲染器并起个 viewId，
/// 界面层（CallMediaView）按 viewId 取出来画——和网页版用 DOM 元素的接法一致，
/// 这样上层的通话界面不用分平台改。
class CallMediaRegistry {
  CallMediaRegistry._();

  static final Map<String, RTCVideoRenderer> _renderers = {};
  static final Set<String> _mirrored = {};

  static RTCVideoRenderer? renderer(String viewId) => _renderers[viewId];

  static bool isMirrored(String viewId) => _mirrored.contains(viewId);

  static Future<void> register(
    String viewId,
    MediaStream stream, {
    bool mirror = false,
  }) async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    renderer.srcObject = stream;
    _renderers[viewId] = renderer;
    if (mirror) _mirrored.add(viewId);
  }

  static Future<void> release(String? viewId) async {
    if (viewId == null) return;
    _mirrored.remove(viewId);
    final renderer = _renderers.remove(viewId);
    if (renderer == null) return;
    renderer.srcObject = null;
    await renderer.dispose();
  }
}
