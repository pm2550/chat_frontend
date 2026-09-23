import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 网页端用浏览器自带的 <audio> 播放语音消息。
///
/// 语音文件要带登录态下载，不能直接把地址交给 <audio>，所以先取回字节再转成
/// blob 地址播放。服务端已把语音统一转成 MP3，各浏览器（含 iPhone Safari）都能放。
class VoicePlayback {
  web.HTMLAudioElement? _audio;
  String? _objectUrl;

  bool get isSupported => true;

  Future<void> play(
    List<int> bytes, {
    String? mimeType,
    void Function()? onEnded,
  }) async {
    stop();
    final blob = web.Blob(
      [Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(type: mimeType ?? 'audio/mpeg'),
    );
    final url = web.URL.createObjectURL(blob);
    final audio = web.HTMLAudioElement()..src = url;
    audio.onended = ((web.Event _) {
      stop();
      onEnded?.call();
    }).toJS;
    _audio = audio;
    _objectUrl = url;
    await audio.play().toDart;
  }

  void stop() {
    final audio = _audio;
    if (audio != null) {
      audio.pause();
      audio.onended = null;
      audio.removeAttribute('src');
    }
    final url = _objectUrl;
    if (url != null) web.URL.revokeObjectURL(url);
    _audio = null;
    _objectUrl = null;
  }

  void dispose() => stop();
}
