import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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
  web.MediaRecorder? _recorder;
  web.MediaStream? _stream;
  final List<web.Blob> _chunks = [];
  Completer<RecordedVoiceFile?>? _stopCompleter;
  DateTime? _startedAt;
  String _mimeType = 'audio/webm';

  bool get isRecording => _recorder?.state == 'recording';

  Future<void> start() async {
    if (isRecording) return;
    _chunks.clear();
    _stopCompleter = Completer<RecordedVoiceFile?>();
    _startedAt = DateTime.now();

    final stream = await web.window.navigator.mediaDevices
        .getUserMedia(web.MediaStreamConstraints(
          audio: true.toJS,
          video: false.toJS,
        ))
        .toDart;
    _stream = stream;

    final selectedMimeType = _selectMimeType();
    _mimeType = selectedMimeType.isEmpty ? 'audio/webm' : selectedMimeType;
    final recorder = selectedMimeType.isEmpty
        ? web.MediaRecorder(stream)
        : web.MediaRecorder(
            stream,
            web.MediaRecorderOptions(mimeType: selectedMimeType),
          );
    _recorder = recorder;

    recorder.addEventListener(
      'dataavailable',
      ((web.Event event) {
        if (!event.isA<web.BlobEvent>()) return;
        final data = (event as web.BlobEvent).data;
        if (data.size > 0) {
          _chunks.add(data);
        }
      }).toJS,
    );

    recorder.addEventListener(
      'stop',
      ((web.Event _) {
        unawaited(_completeStop());
      }).toJS,
    );

    recorder.start();
  }

  Future<RecordedVoiceFile?> stop() async {
    final recorder = _recorder;
    final completer = _stopCompleter;
    if (recorder == null || completer == null) return null;
    if (recorder.state == 'recording') {
      recorder.requestData();
      recorder.stop();
    }
    return completer.future;
  }

  Future<void> cancel() async {
    final recorder = _recorder;
    if (recorder != null && recorder.state == 'recording') {
      recorder.stop();
    }
    _chunks.clear();
    _stopCompleter?.complete(null);
    _stopCompleter = null;
    _cleanup();
  }

  void dispose() {
    if (isRecording) {
      _recorder?.stop();
    }
    _cleanup();
  }

  Future<void> _completeStop() async {
    final completer = _stopCompleter;
    if (completer == null || completer.isCompleted) {
      _cleanup();
      return;
    }

    try {
      final bytes = await _readChunks();
      if (bytes.isEmpty) {
        completer.complete(null);
        return;
      }
      final duration = DateTime.now().difference(_startedAt ?? DateTime.now());
      final extension = _extensionForMimeType(_mimeType);
      completer.complete(
        RecordedVoiceFile(
          name: 'voice_${DateTime.now().millisecondsSinceEpoch}.$extension',
          bytes: bytes,
          mimeType: _mimeType,
          duration: duration,
        ),
      );
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _stopCompleter = null;
      _cleanup();
    }
  }

  Future<Uint8List> _readChunks() async {
    final parts = <Uint8List>[];
    var totalLength = 0;
    for (final chunk in _chunks) {
      final buffer = await chunk.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      parts.add(bytes);
      totalLength += bytes.length;
    }
    final output = Uint8List(totalLength);
    var offset = 0;
    for (final part in parts) {
      output.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return output;
  }

  void _cleanup() {
    final stream = _stream;
    if (stream != null) {
      final tracks = stream.getTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
    }
    _chunks.clear();
    _recorder = null;
    _stream = null;
    _startedAt = null;
  }

  String _selectMimeType() {
    const candidates = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/mp4',
      'audio/aac',
      'audio/ogg;codecs=opus',
    ];
    for (final candidate in candidates) {
      if (web.MediaRecorder.isTypeSupported(candidate)) {
        return candidate;
      }
    }
    return '';
  }

  String _extensionForMimeType(String mimeType) {
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('mp4')) return 'm4a';
    if (normalized.contains('aac')) return 'aac';
    if (normalized.contains('ogg')) return 'ogg';
    return 'webm';
  }
}
