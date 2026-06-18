import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'chat_data_service.dart';
import 'chat_drop_paste.dart'
    show ChatDragStateChanged, ChatFilesDropped, ChatPasteImage;
import 'chat_paste_policy.dart';

typedef VoidCallbackLike = void Function();

class ChatDropPasteController {
  ChatDropPasteController._(this._listeners);

  final List<({String type, web.EventListener listener})> _listeners;

  void dispose() {
    for (final entry in _listeners) {
      web.document.removeEventListener(entry.type, entry.listener);
    }
    _listeners.clear();
  }
}

ChatDropPasteController attachChatDropPasteHandlers({
  required ChatDragStateChanged onDragEntered,
  required VoidCallbackLike onDragExited,
  required ChatFilesDropped onFilesDropped,
  required ChatPasteImage onPasteImage,
}) {
  var dragDepth = 0;
  final listeners = <({String type, web.EventListener listener})>[];

  void add(String type, void Function(web.Event event) handler) {
    final listener = handler.toJS;
    web.document.addEventListener(type, listener);
    listeners.add((type: type, listener: listener));
  }

  bool hasFileItems(web.DataTransfer? transfer) {
    if (transfer == null) return false;
    if (dataTransferTypesContainFiles(transfer)) return true;
    final items = transfer.items;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind == 'file') return true;
    }
    return false;
  }

  int fileItemCount(web.DataTransfer? transfer) {
    if (transfer == null) return 0;
    var count = 0;
    final items = transfer.items;
    for (var i = 0; i < items.length; i++) {
      if (items[i].kind == 'file') count++;
    }
    return count > 0 ? count : (dataTransferTypesContainFiles(transfer) ? 1 : 0);
  }

  add('dragenter', (event) {
    if (!event.isA<web.DragEvent>()) return;
    final dragEvent = event as web.DragEvent;
    if (!hasFileItems(dragEvent.dataTransfer)) return;
    dragDepth++;
    event.preventDefault();
    onDragEntered(fileItemCount(dragEvent.dataTransfer));
  });

  add('dragover', (event) {
    if (!event.isA<web.DragEvent>()) return;
    final dragEvent = event as web.DragEvent;
    if (!hasFileItems(dragEvent.dataTransfer)) return;
    event.preventDefault();
    dragEvent.dataTransfer?.dropEffect = 'copy';
    onDragEntered(fileItemCount(dragEvent.dataTransfer));
  });

  add('dragleave', (event) {
    if (!event.isA<web.DragEvent>()) return;
    if (dragDepth > 0) dragDepth--;
    if (dragDepth == 0) {
      onDragExited();
    }
  });

  add('drop', (event) {
    if (!event.isA<web.DragEvent>()) return;
    final dragEvent = event as web.DragEvent;
    final files = dragEvent.dataTransfer?.files;
    if (files == null || files.length == 0) return;
    event.preventDefault();
    dragDepth = 0;
    onDragExited();
    unawaited(_readFiles(files).then(onFilesDropped));
  });

  add('paste', (event) {
    if (!event.isA<web.ClipboardEvent>()) return;
    final pasteEvent = event as web.ClipboardEvent;
    final transfer = pasteEvent.clipboardData;
    if (transfer == null) return;
    final items = transfer.items;
    final describedItems = <ChatClipboardItemInfo>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      describedItems.add(ChatClipboardItemInfo(
        kind: item.kind,
        type: item.type,
      ));
    }
    final decision = decideChatPasteHandling(
      describedItems,
      textEditingFocused: _isTextEditingElement(web.document.activeElement),
    );
    if (decision != ChatPasteDecision.uploadImage) return;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind != 'file' ||
          !item.type.toLowerCase().startsWith('image/')) {
        continue;
      }
      final file = item.getAsFile();
      if (file == null) continue;
      event.preventDefault();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      unawaited(
          _readFile(file, forcedName: 'paste_$stamp.png').then(onPasteImage));
      return;
    }
  });

  return ChatDropPasteController._(listeners);
}

bool dataTransferTypesContainFiles(web.DataTransfer transfer) {
  final types = transfer.types.toDart;
  for (var i = 0; i < types.length; i++) {
    if (types[i].toDart.toLowerCase() == 'files') {
      return true;
    }
  }
  return false;
}

bool _isTextEditingElement(web.Element? element) {
  if (element == null) return false;
  if (element.isA<web.HTMLInputElement>() ||
      element.isA<web.HTMLTextAreaElement>()) {
    return true;
  }
  if (element.isA<web.HTMLElement>()) {
    return (element as web.HTMLElement).isContentEditable;
  }
  return false;
}

Future<List<PickedChatFile>> _readFiles(web.FileList files) async {
  final result = <PickedChatFile>[];
  for (var i = 0; i < files.length; i++) {
    final file = files.item(i);
    if (file == null) continue;
    result.add(await _readFile(file));
  }
  return result;
}

Future<PickedChatFile> _readFile(web.File file, {String? forcedName}) {
  final completer = Completer<PickedChatFile>();
  final reader = web.FileReader();
  reader.onLoadEnd.listen((_) {
    final result = reader.result;
    if (result != null && result.isA<JSArrayBuffer>()) {
      final bytes = (result as JSArrayBuffer).toDart.asUint8List();
      completer.complete(PickedChatFile(
        name: forcedName ?? file.name,
        size: bytes.length,
        mimeType: file.type.isEmpty ? null : file.type,
        bytes: bytes,
      ));
      return;
    }
    completer.completeError(StateError('浏览器返回了无法识别的文件内容'));
  });
  reader.readAsArrayBuffer(file);
  return completer.future;
}
