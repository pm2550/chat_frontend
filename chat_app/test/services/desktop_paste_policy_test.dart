import 'package:chat_app/services/desktop_paste_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decideDesktopPaste', () {
    test('files copied in the file manager are attached even with path text', () {
      expect(
        decideDesktopPaste(
          fileCount: 2,
          hasImage: false,
          plainText: '/home/u/report final.pdf',
          textEditingFocused: true,
        ),
        DesktopPasteDecision.attachFiles,
      );
    });

    test('a screenshot is attached, not pasted as text', () {
      expect(
        decideDesktopPaste(
          fileCount: 0,
          hasImage: true,
          plainText: '',
          textEditingFocused: true,
        ),
        DesktopPasteDecision.attachImage,
      );
    });

    test('an image whose only text is its file name is still an image', () {
      expect(
        decideDesktopPaste(
          fileCount: 0,
          hasImage: true,
          plainText: 'IMG_2035.png',
          textEditingFocused: true,
        ),
        DesktopPasteDecision.attachImage,
      );
    });

    test('rich text with an embedded picture pastes as text in the composer', () {
      expect(
        decideDesktopPaste(
          fileCount: 0,
          hasImage: true,
          plainText: '会议纪要 第一条',
          textEditingFocused: true,
        ),
        DesktopPasteDecision.pasteText,
      );
    });

    test('plain text keeps the normal Ctrl+V behaviour', () {
      expect(
        decideDesktopPaste(
          fileCount: 0,
          hasImage: false,
          plainText: 'hello',
          textEditingFocused: true,
        ),
        DesktopPasteDecision.pasteText,
      );
      expect(
        decideDesktopPaste(
          fileCount: 0,
          hasImage: false,
          plainText: 'hello',
          textEditingFocused: false,
        ),
        DesktopPasteDecision.ignore,
      );
    });
  });

  test('sniffs clipboard image formats', () {
    expect(sniffImageMimeType([0x89, 0x50, 0x4E, 0x47, 0, 0]), 'image/png');
    expect(sniffImageMimeType([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
    expect(sniffImageMimeType([0x42, 0x4D, 0, 0]), 'image/bmp');
    expect(
      sniffImageMimeType(
          [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]),
      'image/webp',
    );
    expect(sniffImageMimeType([1, 2, 3]), isNull);
  });

  test('pasted images are named like on the web', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    expect(pastedImageFileName('image/png', now: now), 'paste_1700000000000.png');
    expect(pastedImageFileName('image/jpeg', now: now), 'paste_1700000000000.jpg');
  });
}
