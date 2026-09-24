import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

/// 从系统拖进来（或从剪贴板粘贴进来）的一个文件。
///
/// 桌面端有真实路径，上传时按路径流式读取；只有图片会顺便读出字节，给待发送栏
/// 画缩略图。Web 端没有路径，只能带字节。
class DroppedFile {
  const DroppedFile({
    required this.name,
    required this.size,
    this.path,
    this.mimeType,
    this.bytes,
  });

  final String name;
  final int size;
  final String? path;
  final String? mimeType;
  final Uint8List? bytes;

  bool get isImage => mimeType?.startsWith('image/') ?? false;
}

class DroppedFileBatch {
  const DroppedFileBatch({
    this.files = const [],
    this.skippedFolders = 0,
    this.unreadable = 0,
  });

  final List<DroppedFile> files;

  /// 拖进来的文件夹（不支持整目录上传，跳过）。
  final int skippedFolders;

  /// 读不到的文件（被删了、没有权限……）。
  final int unreadable;

  /// 有东西被跳过时给用户的一句话提示。
  String? get skippedMessage {
    final parts = <String>[
      if (skippedFolders > 0) '$skippedFolders 个文件夹',
      if (unreadable > 0) '$unreadable 个读不到的文件',
    ];
    if (parts.isEmpty) return null;
    return '已跳过${parts.join('、')}，请直接拖文件';
  }
}

String? guessMimeType(String name, {List<int>? headerBytes}) {
  return lookupMimeType(name, headerBytes: headerBytes);
}

/// 把 desktop_drop 交来的条目读成 [DroppedFile]。
Future<DroppedFileBatch> readDroppedItems(
  List<DropItem> items, {
  bool web = kIsWeb,
}) async {
  final files = <DroppedFile>[];
  var folders = 0;
  var unreadable = 0;
  for (final item in items) {
    if (item is DropItemDirectory) {
      folders++;
      continue;
    }
    try {
      final bookmark = item.extraAppleBookmark;
      if (bookmark != null && bookmark.isNotEmpty) {
        // macOS 沙盒：拖进来的文件要先打开安全作用域才能读；
        // 上传在之后才发生，所以这里不关，随进程结束释放。
        await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
      }
      final name = item.name.isNotEmpty ? item.name : 'file';
      var mimeType = item.mimeType;
      if (mimeType == null || mimeType.isEmpty) {
        mimeType = guessMimeType(name);
      }
      final isImage = mimeType?.startsWith('image/') ?? false;
      Uint8List? bytes;
      if (web || isImage) {
        bytes = await item.readAsBytes();
      }
      files.add(DroppedFile(
        name: name,
        size: bytes?.length ?? await item.length(),
        path: web ? null : item.path,
        mimeType: mimeType,
        bytes: bytes,
      ));
    } catch (_) {
      unreadable++;
    }
  }
  return DroppedFileBatch(
    files: files,
    skippedFolders: folders,
    unreadable: unreadable,
  );
}
