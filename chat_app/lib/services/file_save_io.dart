import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'file_save_result.dart';

export 'file_save_result.dart';

/// Native save: photos and videos go to the system gallery on Android/iOS,
/// everything else goes through a save dialog the user can see.
Future<FileSaveResult> saveBytesAsFile({
  required List<int> bytes,
  required String name,
  String? mimeType,
}) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final safeName = sanitizeSaveFileName(name);

  if (Platform.isAndroid || Platform.isIOS) {
    switch (saveMediaKindFor(safeName, mimeType)) {
      case SaveMediaKind.image:
        await _ensureGalleryAccess();
        await _runGal(() => Gal.putImageBytes(
              data,
              name: p.basenameWithoutExtension(safeName),
            ));
        return const FileSaveResult.saved(FileSaveDestination.gallery);
      case SaveMediaKind.video:
        await _ensureGalleryAccess();
        final temp = await _writeTemp(
          data,
          _withExtension(safeName, fallbackExt: _videoExtFor(mimeType)),
        );
        try {
          await _runGal(() => Gal.putVideo(temp.path));
        } finally {
          await _deleteQuietly(temp);
        }
        return const FileSaveResult.saved(FileSaveDestination.gallery);
      case SaveMediaKind.other:
        // Android: SAF "create document"; iOS: document picker export.
        // file_picker writes the bytes itself on mobile.
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '保存文件',
          fileName: safeName,
          bytes: data,
        );
        return path == null
            ? const FileSaveResult.cancelled()
            : const FileSaveResult.saved(FileSaveDestination.pickedLocation);
    }
  }

  // Desktop: the dialog only returns a path; writing is our job.
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '保存文件',
    fileName: safeName,
  );
  if (path == null || path.isEmpty) return const FileSaveResult.cancelled();
  try {
    await File(path).writeAsBytes(data, flush: true);
  } on FileSystemException catch (error) {
    throw FileSaveException(
        '写入文件失败：${error.osError?.message ?? error.message}');
  }
  return FileSaveResult.saved(FileSaveDestination.pickedLocation, path: path);
}

/// Native counterpart of the web "open in new tab": hand the file to another
/// app (share sheet on phones, the default app on desktop).
Future<bool> openBytesInNewTab({
  required List<int> bytes,
  required String name,
  String? mimeType,
}) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final temp = await _writeTemp(data, sanitizeSaveFileName(name));
  if (Platform.isAndroid || Platform.isIOS) {
    final result = await Share.shareXFiles(
      [XFile(temp.path, mimeType: mimeType)],
    );
    return result.status != ShareResultStatus.unavailable;
  }
  return launchUrl(Uri.file(temp.path));
}

Future<void> _ensureGalleryAccess() async {
  if (await Gal.hasAccess()) return;
  if (await Gal.requestAccess()) return;
  throw const FileSaveException('没有相册权限，请在系统设置里允许 PM chat 保存照片');
}

Future<void> _runGal(Future<void> Function() action) async {
  try {
    await action();
  } on GalException catch (error) {
    throw FileSaveException(switch (error.type) {
      GalExceptionType.accessDenied => '没有相册权限，请在系统设置里允许 PM chat 保存照片',
      GalExceptionType.notEnoughSpace => '手机存储空间不足，保存失败',
      GalExceptionType.notSupportedFormat => '相册不支持这种格式，保存失败',
      GalExceptionType.unexpected =>
        '保存到相册失败：${error.platformException.message ?? error.type.name}',
    });
  }
}

Future<File> _writeTemp(Uint8List data, String name) async {
  final dir = await getTemporaryDirectory();
  final folder = Directory(p.join(
    dir.path,
    'pmchat-save-${DateTime.now().microsecondsSinceEpoch}',
  ));
  await folder.create(recursive: true);
  final file = File(p.join(folder.path, name));
  await file.writeAsBytes(data, flush: true);
  return file;
}

Future<void> _deleteQuietly(File file) async {
  try {
    await file.parent.delete(recursive: true);
  } catch (_) {}
}

String _videoExtFor(String? mimeType) {
  final mime = mimeType?.toLowerCase() ?? '';
  if (mime.contains('quicktime')) return 'mov';
  if (mime.contains('webm')) return 'webm';
  if (mime.contains('3gpp')) return '3gp';
  return 'mp4';
}

String _withExtension(String name, {required String fallbackExt}) =>
    fileExtensionOf(name).isEmpty ? '$name.$fallbackExt' : name;
