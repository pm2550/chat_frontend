import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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

/// 原生端录音（Android/iOS/桌面）：录成 AAC（m4a），服务端会再统一转成 MP3。
class VoiceRecorder {
  AudioRecorder? _recorder;
  DateTime? _startedAt;
  String? _path;
  bool _recording = false;

  bool get isRecording => _recording;

  Future<void> start() async {
    if (_recording) return;
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      throw StateError('没有麦克风权限，请在系统设置里允许 PM chat 使用麦克风');
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 64000,
        numChannels: 1,
      ),
      path: path,
    );
    _path = path;
    _startedAt = DateTime.now();
    _recording = true;
  }

  Future<RecordedVoiceFile?> stop() async {
    if (!_recording) return null;
    _recording = false;
    final startedAt = _startedAt;
    final path = await _recorder?.stop() ?? _path;
    _path = null;
    _startedAt = null;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return RecordedVoiceFile(
        name: file.uri.pathSegments.last,
        bytes: bytes,
        mimeType: 'audio/mp4',
        duration: startedAt == null
            ? Duration.zero
            : DateTime.now().difference(startedAt),
      );
    } finally {
      unawaited(file.delete().then((_) {}).catchError((_) {}));
    }
  }

  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    await _recorder?.cancel();
    _path = null;
    _startedAt = null;
  }

  void dispose() {
    final recorder = _recorder;
    _recorder = null;
    _recording = false;
    if (recorder != null) unawaited(recorder.dispose());
  }
}
