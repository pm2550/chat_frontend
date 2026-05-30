import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'chat_data_service.dart';

Future<List<PickedChatFile>> pickStickerFilesForCurrentPlatform({
  required bool allowMultiple,
  required List<String> allowedExtensions,
}) {
  final completer = Completer<List<PickedChatFile>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = allowMultiple
    ..accept = allowedExtensions.map((extension) => '.$extension').join(',');
  input.setAttribute('data-pmchat', 'sticker-file-input');
  input.style.position = 'fixed';
  input.style.left = '0';
  input.style.top = '0';
  input.style.width = '1px';
  input.style.height = '1px';
  input.style.opacity = '0';

  web.document.querySelector('body')?.children.add(input);

  var changeEventTriggered = false;
  Timer? timeout;

  void completeOnce(List<PickedChatFile> files, [Object? error]) {
    if (completer.isCompleted) {
      return;
    }
    timeout?.cancel();
    input.remove();
    if (error != null) {
      completer.completeError(error);
    } else {
      completer.complete(files);
    }
  }

  void changeEventListener(web.Event _) {
    if (changeEventTriggered) {
      return;
    }
    changeEventTriggered = true;

    final files = input.files;
    if (files == null || files.length == 0) {
      completeOnce(const []);
      return;
    }

    unawaited(() async {
      final picked = <PickedChatFile>[];
      for (var i = 0; i < files.length; i++) {
        final file = files.item(i);
        if (file == null) continue;
        picked.add(await _readFile(file));
      }
      completeOnce(picked);
    }()
        .catchError((Object error) {
      completeOnce(const [], error);
    }));
  }

  input.onChange.listen(changeEventListener);
  input.addEventListener('change', changeEventListener.toJS);
  timeout = Timer(const Duration(seconds: 60), () => completeOnce(const []));
  input.click();
  return completer.future;
}

Future<PickedChatFile> _readFile(web.File file) {
  final completer = Completer<PickedChatFile>();
  final reader = web.FileReader();
  reader.onLoadEnd.listen((_) {
    final result = reader.result;
    if (result != null && result.isA<JSArrayBuffer>()) {
      final bytes = (result as JSArrayBuffer).toDart.asUint8List();
      completer.complete(PickedChatFile(
        name: file.name,
        size: bytes.length,
        mimeType: file.type.isEmpty ? _mimeType(file.name) : file.type,
        bytes: bytes,
      ));
      return;
    }
    completer.completeError(StateError('浏览器返回了无法识别的文件内容'));
  });
  reader.readAsArrayBuffer(file);
  return completer.future;
}

String _mimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/png';
}
