import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'chat_data_service.dart';

Future<PickedChatFile?> pickGenericFileForCurrentPlatform() {
  final completer = Completer<PickedChatFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..draggable = true
    ..multiple = false;
  input.style.display = 'none';

  web.document.querySelector('body')?.children.add(input);

  var changeEventTriggered = false;
  Timer? timeout;

  void completeOnce(PickedChatFile? file, [Object? error]) {
    if (completer.isCompleted) {
      return;
    }
    timeout?.cancel();
    input.remove();
    if (error != null) {
      completer.completeError(error);
    } else {
      completer.complete(file);
    }
  }

  void changeEventListener(web.Event _) {
    if (changeEventTriggered) {
      return;
    }
    changeEventTriggered = true;

    final files = input.files;
    if (files == null || files.length == 0) {
      completeOnce(null);
      return;
    }

    final file = files.item(0);
    if (file == null) {
      completeOnce(null);
      return;
    }

    final reader = web.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result != null && result.isA<JSArrayBuffer>()) {
        final bytes = (result as JSArrayBuffer).toDart.asUint8List();
        completeOnce(
          PickedChatFile(
            name: file.name,
            size: bytes.length,
            mimeType: file.type.isEmpty ? null : file.type,
            bytes: bytes,
          ),
        );
        return;
      }
      completeOnce(null, StateError('浏览器返回了无法识别的文件内容'));
    });
    reader.readAsArrayBuffer(file);
  }

  input.onChange.listen(changeEventListener);
  input.addEventListener('change', changeEventListener.toJS);

  timeout = Timer(const Duration(seconds: 60), () => completeOnce(null));
  input.click();
  return completer.future;
}
