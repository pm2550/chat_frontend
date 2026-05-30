import 'package:file_picker/file_picker.dart';

import 'chat_data_service.dart';

Future<List<PickedChatFile>> pickStickerFilesForCurrentPlatform({
  required bool allowMultiple,
  required List<String> allowedExtensions,
}) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: allowMultiple,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    withData: true,
  );
  if (result == null || result.files.isEmpty) {
    return const [];
  }
  return result.files
      .map((file) => PickedChatFile(
            name: file.name,
            path: file.path,
            bytes: file.bytes,
            size: file.size,
            mimeType: _mimeType(file.name),
          ))
      .toList(growable: false);
}

String _mimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/png';
}
