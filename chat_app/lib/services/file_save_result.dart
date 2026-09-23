/// Outcome of handing a downloaded file to the platform's "save" flow.
///
/// Failures are thrown (see [FileSaveException]); this only distinguishes
/// the non-error outcomes so callers never claim a save that did not happen.
enum FileSaveStatus {
  /// The file was written somewhere the user can find it again.
  saved,

  /// The user dismissed the save dialog / share sheet.
  cancelled,

  /// This platform has no way to save files from the app.
  unsupported,
}

enum FileSaveDestination {
  /// The system photo library (Android/iOS).
  gallery,

  /// A location the user picked in a save dialog.
  pickedLocation,

  /// The browser's download folder.
  browserDownloads,

  /// The system share sheet (iOS web: "存储图像" puts it in Photos).
  shareSheet,
}

class FileSaveResult {
  const FileSaveResult.saved(this.destination, {this.path})
      : status = FileSaveStatus.saved;

  const FileSaveResult.cancelled()
      : status = FileSaveStatus.cancelled,
        destination = null,
        path = null;

  const FileSaveResult.unsupported()
      : status = FileSaveStatus.unsupported,
        destination = null,
        path = null;

  final FileSaveStatus status;
  final FileSaveDestination? destination;

  /// Where the file ended up, when the platform tells us (desktop dialogs).
  final String? path;

  bool get isSaved => status == FileSaveStatus.saved;

  /// Snackbar text for this outcome, or null when nothing should be shown
  /// (the user cancelled on purpose).
  String? describe(String fileName) {
    switch (status) {
      case FileSaveStatus.cancelled:
        return null;
      case FileSaveStatus.unsupported:
        return '当前平台不支持保存文件';
      case FileSaveStatus.saved:
        switch (destination) {
          case FileSaveDestination.gallery:
            return '已保存到相册';
          case FileSaveDestination.pickedLocation:
            final location = path;
            return location == null || location.isEmpty
                ? '已保存 $fileName'
                : '已保存到 $location';
          case FileSaveDestination.browserDownloads:
            return '已下载 $fileName';
          case FileSaveDestination.shareSheet:
            return '已保存 $fileName';
          case null:
            return '已保存 $fileName';
        }
    }
  }
}

/// Signature of `saveBytesAsFile`, injectable so screens can be tested
/// without touching real dialogs or the photo library.
typedef FileSaver = Future<FileSaveResult> Function({
  required List<int> bytes,
  required String name,
  String? mimeType,
});

class FileSaveException implements Exception {
  const FileSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Media kind used to decide whether a file belongs in the photo library.
enum SaveMediaKind { image, video, other }

SaveMediaKind saveMediaKindFor(String name, String? mimeType) {
  final mime = mimeType?.toLowerCase().split(';').first.trim() ?? '';
  if (mime.startsWith('image/') && mime != 'image/svg+xml') {
    return SaveMediaKind.image;
  }
  if (mime.startsWith('video/')) return SaveMediaKind.video;
  final ext = fileExtensionOf(name);
  const imageExts = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'bmp'
  };
  const videoExts = {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv'};
  if (imageExts.contains(ext)) return SaveMediaKind.image;
  if (videoExts.contains(ext)) return SaveMediaKind.video;
  return SaveMediaKind.other;
}

/// Lower-case extension without the dot, or '' when there is none.
String fileExtensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  final ext = name.substring(dot + 1).toLowerCase();
  return ext.contains('/') || ext.contains('\\') ? '' : ext;
}

/// Strip path separators and characters Windows/Android refuse in names.
String sanitizeSaveFileName(String name, {String fallback = 'attachment'}) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .trim()
      .replaceAll(RegExp(r'^\.+'), '');
  return cleaned.isEmpty ? fallback : cleaned;
}
