import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// 原生端播放语音消息：先把下载到的字节写成临时文件再播（各平台都支持本地文件源）。
class VoicePlayback {
  AudioPlayer? _player;
  StreamSubscription<void>? _completeSub;
  File? _file;

  bool get isSupported => true;

  Future<void> play(
    List<int> bytes, {
    String? mimeType,
    void Function()? onEnded,
  }) async {
    stop();
    final dir = await getTemporaryDirectory();
    final extension = _extensionFor(mimeType);
    final file = File(
        '${dir.path}/voice_play_${DateTime.now().microsecondsSinceEpoch}.$extension');
    await file.writeAsBytes(bytes, flush: true);
    final player = AudioPlayer();
    _player = player;
    _file = file;
    _completeSub = player.onPlayerComplete.listen((_) {
      stop();
      onEnded?.call();
    });
    await player.play(DeviceFileSource(file.path));
  }

  void stop() {
    _completeSub?.cancel();
    _completeSub = null;
    final player = _player;
    _player = null;
    if (player != null) {
      unawaited(player.stop().catchError((_) {}));
      unawaited(player.dispose().catchError((_) {}));
    }
    final file = _file;
    _file = null;
    if (file != null) {
      unawaited(file.delete().then((_) {}).catchError((_) {}));
    }
  }

  void dispose() => stop();

  String _extensionFor(String? mimeType) {
    final lower = (mimeType ?? '').toLowerCase();
    if (lower.contains('mpeg') || lower.contains('mp3')) return 'mp3';
    if (lower.contains('mp4') || lower.contains('m4a') || lower.contains('aac')) {
      return 'm4a';
    }
    if (lower.contains('ogg')) return 'ogg';
    if (lower.contains('webm')) return 'webm';
    if (lower.contains('wav')) return 'wav';
    return 'mp3';
  }
}
