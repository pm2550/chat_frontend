import 'dart:io';

import 'package:chat_app/services/os_dropped_files.dart';
import 'package:chat_app/widgets/desktop_drop_paste_region.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeClipboard implements DesktopClipboardReader {
  List<String> paths = const [];
  Uint8List? imageBytes;
  String text = '';

  @override
  Future<List<String>> filePaths() async => paths;

  @override
  Future<Uint8List?> image() async => imageBytes;

  @override
  Future<String> plainText() async => text;
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('pmchat-paste'));
  tearDown(() => temp.deleteSync(recursive: true));

  testWidgets('Ctrl+V with copied files queues them instead of pasting paths',
      (tester) async {
    final clipboard = _FakeClipboard();
    final doc = File(p.join(temp.path, 'report.pdf'))..writeAsStringSync('pdf!');
    final photo = File(p.join(temp.path, 'photo.png'))
      ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    Directory(p.join(temp.path, 'folder')).createSync();
    clipboard
      ..paths = [doc.path, photo.path, p.join(temp.path, 'folder')]
      ..text = doc.path;
    final batches = <DroppedFileBatch>[];
    final controller = TextEditingController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DesktopDropPasteRegion(
          forceEnabled: true,
          clipboard: clipboard,
          onDragActiveChanged: (_) {},
          onFiles: batches.add,
          onPasteImage: (_) {},
          child: TextField(controller: controller, autofocus: true),
        ),
      ),
    ));
    await tester.pump();

    final action = DesktopPasteAction(
      clipboard: clipboard,
      onFiles: batches.add,
      onPasteImage: (_) {},
    );
    // 直接调用（焦点不在输入框时的路径）同样只处理文件。
    await tester.runAsync(() async {
      action.invoke(const PasteTextIntent(SelectionChangedCause.keyboard));
      await action.lastPaste;
    });

    expect(batches, hasLength(1));
    final batch = batches.single;
    expect(batch.files.map((f) => f.name), ['report.pdf', 'photo.png']);
    expect(batch.files.first.path, doc.path);
    expect(batch.files.first.bytes, isNull, reason: '普通文件按路径上传');
    expect(batch.files.last.mimeType, 'image/png');
    expect(batch.files.last.bytes, isNotNull, reason: '图片要画缩略图');
    expect(batch.skippedFolders, 1);
    expect(batch.skippedMessage, contains('1 个文件夹'));
    expect(controller.text, isEmpty);
  });

  test('dropped folders are skipped and reported', () async {
    final file = File(p.join(temp.path, 'a.txt'))..writeAsStringSync('abc');
    final batch = await readDroppedItems(
      [
        DropItemFile(file.path),
        DropItemDirectory(temp.path, const []),
      ],
      web: false,
    );
    expect(batch.files.single.name, 'a.txt');
    expect(batch.files.single.size, 3);
    expect(batch.files.single.mimeType, 'text/plain');
    expect(batch.skippedFolders, 1);
  });
}
