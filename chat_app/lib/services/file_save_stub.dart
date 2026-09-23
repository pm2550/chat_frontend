import 'file_save_result.dart';

export 'file_save_result.dart';

Future<FileSaveResult> saveBytesAsFile({
  required List<int> bytes,
  required String name,
  String? mimeType,
}) async {
  return const FileSaveResult.unsupported();
}

Future<bool> openBytesInNewTab({
  required List<int> bytes,
  required String name,
  String? mimeType,
}) async {
  return false;
}
