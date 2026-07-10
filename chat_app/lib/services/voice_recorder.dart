import 'dart:typed_data';

import 'chat_data_service.dart';

class RecordedVoiceFile {
  const RecordedVoiceFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
    required this.duration,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
  final Duration duration;

  PickedChatFile toPickedChatFile() => PickedChatFile(
        name: name,
        size: bytes.length,
        mimeType: mimeType,
        bytes: bytes,
      );
}

class VoiceRecorder {
  bool get isRecording => false;

  Future<void> start() {
    throw UnsupportedError('当前平台暂不支持直接录音，请从附件菜单上传语音文件。');
  }

  Future<RecordedVoiceFile?> stop() async => null;

  Future<void> cancel() async {}

  void dispose() {}
}
