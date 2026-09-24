import 'dart:async';
import 'dart:io' show FileSystemEntity, FileSystemEntityType;
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pasteboard/pasteboard.dart';

import '../services/desktop_paste_policy.dart';
import '../services/os_dropped_files.dart';
import 'os_file_drop_target.dart';

/// 读系统剪贴板；测试里换成假的。
abstract class DesktopClipboardReader {
  Future<List<String>> filePaths();
  Future<Uint8List?> image();
  Future<String> plainText();
}

class PasteboardClipboardReader implements DesktopClipboardReader {
  const PasteboardClipboardReader();

  @override
  Future<List<String>> filePaths() => Pasteboard.files();

  @override
  Future<Uint8List?> image() => Pasteboard.image;

  @override
  Future<String> plainText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
}

/// 原生桌面端聊天页的拖放 + 粘贴：和网页版一样，拖进来的文件、粘贴的图片/文件
/// 都先进待发送栏；Ctrl/⌘+V 粘的是文字时照常进输入框。
///
/// 网页版由 chat_drop_paste_web.dart 在 document 上监听，手机端没有这两种操作，
/// 这两种情况下原样返回 [child]。
class DesktopDropPasteRegion extends StatelessWidget {
  const DesktopDropPasteRegion({
    super.key,
    required this.child,
    required this.onDragActiveChanged,
    required this.onFiles,
    required this.onPasteImage,
    this.clipboard = const PasteboardClipboardReader(),
    this.forceEnabled = false,
  });

  final Widget child;
  final ValueChanged<bool> onDragActiveChanged;

  /// 拖进来或粘贴进来的一批文件。
  final ValueChanged<DroppedFileBatch> onFiles;
  final ValueChanged<DroppedFile> onPasteImage;
  final DesktopClipboardReader clipboard;

  /// 测试用：在非桌面平台也启用粘贴处理。
  final bool forceEnabled;

  static bool get isNativeDesktop =>
      !kIsWeb &&
      OsFileDropTarget.supportedOn(web: false, platform: defaultTargetPlatform);

  @override
  Widget build(BuildContext context) {
    if (!forceEnabled && !isNativeDesktop) return child;
    return OsFileDropTarget(
      onDragActiveChanged: onDragActiveChanged,
      onFilesDropped: onFiles,
      child: Actions(
        actions: {
          PasteTextIntent: DesktopPasteAction(
            clipboard: clipboard,
            onFiles: onFiles,
            onPasteImage: onPasteImage,
          ),
        },
        child: child,
      ),
    );
  }
}

/// 接管 Ctrl/⌘+V（[PasteTextIntent]）。
///
/// 焦点在输入框里时，这个 Action 是 EditableText 默认粘贴动作的 override，
/// [callingAction] 就是输入框自己的粘贴；剪贴板里没有图片/文件时交还给它。
/// 焦点不在输入框里时直接被调用，只处理图片/文件。
class DesktopPasteAction extends Action<PasteTextIntent> {
  DesktopPasteAction({
    required this.clipboard,
    required this.onFiles,
    required this.onPasteImage,
  });

  final DesktopClipboardReader clipboard;
  final ValueChanged<DroppedFileBatch> onFiles;
  final ValueChanged<DroppedFile> onPasteImage;

  /// 最近一次粘贴处理完成（测试等它）。
  @visibleForTesting
  Future<void>? lastPaste;

  @override
  Object? invoke(PasteTextIntent intent) {
    final textPaste = callingAction;
    lastPaste = _handle(intent, textPaste);
    return null;
  }

  Future<void> _handle(PasteTextIntent intent, Action<Intent>? textPaste) async {
    var paths = const <String>[];
    Uint8List? image;
    var text = '';
    try {
      paths = await clipboard.filePaths();
      if (paths.isEmpty) image = await clipboard.image();
      text = await clipboard.plainText();
    } catch (error) {
      debugPrint('Desktop clipboard read failed: $error');
    }

    final existing = <String>[];
    var folders = 0;
    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.file) existing.add(path);
      if (type == FileSystemEntityType.directory) folders++;
    }

    final action = decideDesktopPaste(
      fileCount: existing.length + folders,
      hasImage: image != null && image.isNotEmpty,
      plainText: text,
      textEditingFocused: textPaste != null,
    );
    switch (action) {
      case DesktopPasteDecision.attachFiles:
        final batch = await readDroppedItems(
          [for (final path in existing) DropItemFile(path)],
          web: false,
        );
        onFiles(DroppedFileBatch(
          files: batch.files,
          skippedFolders: batch.skippedFolders + folders,
          unreadable: batch.unreadable,
        ));
      case DesktopPasteDecision.attachImage:
        final file = await pastedImageFile(image!);
        if (file != null) onPasteImage(file);
      case DesktopPasteDecision.pasteText:
        if (textPaste != null && textPaste.isActionEnabled) {
          textPaste.invoke(intent);
        }
      case DesktopPasteDecision.ignore:
        break;
    }
  }
}

/// 剪贴板图片 → 待发送附件。Windows 的剪贴板插件给的是 BMP，转成 PNG 再发。
Future<DroppedFile?> pastedImageFile(Uint8List bytes, {DateTime? now}) async {
  var data = bytes;
  var mimeType = sniffImageMimeType(data);
  if (mimeType == null || mimeType == 'image/bmp' || mimeType == 'image/tiff') {
    final png = await _encodePng(data);
    if (png == null) return null;
    data = png;
    mimeType = 'image/png';
  }
  return DroppedFile(
    name: pastedImageFileName(mimeType, now: now),
    size: data.length,
    mimeType: mimeType,
    bytes: data,
  );
}

Future<Uint8List?> _encodePng(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return png?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
