import 'dart:convert';

import 'package:chat_app/screens/chat/sticker_pack_upload_screen.dart';
import 'package:chat_app/services/chat_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  testWidgets('picked sticker files update counter and thumbnail grid',
      (tester) async {
    final files = [
      _pickedSticker('alpha.png'),
      _pickedSticker('beta.webp'),
      _pickedSticker('gamma.gif'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: StickerPackUploadScreen(
        filePicker: ({
          required allowMultiple,
          required allowedExtensions,
        }) async {
          expect(allowMultiple, isTrue);
          expect(allowedExtensions, containsAll(['png', 'webp', 'gif']));
          return files;
        },
      ),
    ));

    expect(find.text('0/24 张'), findsOneWidget);
    expect(find.text('还没有选择贴纸'), findsOneWidget);

    await tester.tap(find.text('添加贴纸图片'));
    await tester.pumpAndSettle();

    expect(find.text('3/24 张'), findsOneWidget);
    expect(find.text('还没有选择贴纸'), findsNothing);
    expect(find.text('alpha.png'), findsAtLeastNWidgets(1));
    expect(find.text('beta.webp'), findsOneWidget);
    expect(find.text('gamma.gif'), findsOneWidget);
  });

  testWidgets('upload submits selected sticker files through multipart service',
      (tester) async {
    Map<String, List<PickedChatFile>>? capturedFiles;
    final service = ChatDataService(
      multipartFilesRequest: (url, {required fields, required files}) async {
        capturedFiles = files;
        return http.Response(
          jsonEncode({
            'data': {'id': 42, 'name': fields['name']},
          }),
          200,
        );
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: StickerPackUploadScreen(
        chatService: service,
        filePicker: ({
          required allowMultiple,
          required allowedExtensions,
        }) async {
          return [_pickedSticker('upload.png')];
        },
      ),
    ));

    await tester.tap(find.text('添加贴纸图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上传贴纸包').last);
    await tester.pumpAndSettle();

    expect(capturedFiles, isNotNull);
    expect(capturedFiles!['files'], hasLength(1));
    expect(capturedFiles!['files']!.single.name, 'upload.png');
  });
}

PickedChatFile _pickedSticker(String name) {
  return PickedChatFile(
    name: name,
    size: _pngBytes.length,
    mimeType: name.endsWith('.gif')
        ? 'image/gif'
        : name.endsWith('.webp')
            ? 'image/webp'
            : 'image/png',
    bytes: _pngBytes,
  );
}

const _pngBytes = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  15,
  4,
  0,
  9,
  251,
  3,
  253,
  167,
  186,
  234,
  105,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
