/// 原生端暂时没有内置播放器，语音消息仍按附件打开。
class VoicePlayback {
  bool get isSupported => false;

  Future<void> play(
    List<int> bytes, {
    String? mimeType,
    void Function()? onEnded,
  }) async {}

  void stop() {}

  void dispose() {}
}
