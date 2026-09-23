import 'package:chat_app/services/file_save_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('saveMediaKindFor', () {
    test('uses the MIME type first', () {
      expect(saveMediaKindFor('x.bin', 'image/jpeg'), SaveMediaKind.image);
      expect(saveMediaKindFor('x', 'video/mp4; codecs=avc1'),
          SaveMediaKind.video);
      expect(saveMediaKindFor('a.pdf', 'application/pdf'),
          SaveMediaKind.other);
    });

    test('SVG is not a photo', () {
      expect(saveMediaKindFor('logo.svg', 'image/svg+xml'),
          SaveMediaKind.other);
    });

    test('falls back to the extension when the server says octet-stream', () {
      expect(saveMediaKindFor('IMG_1.HEIC', 'application/octet-stream'),
          SaveMediaKind.image);
      expect(saveMediaKindFor('clip.MOV', null), SaveMediaKind.video);
      expect(saveMediaKindFor('notes', null), SaveMediaKind.other);
    });
  });

  test('sanitizeSaveFileName strips separators and reserved characters', () {
    expect(sanitizeSaveFileName('a/b\\c:d*e?.png'), 'a_b_c_d_e_.png');
    expect(sanitizeSaveFileName('..hidden'), 'hidden');
    expect(sanitizeSaveFileName('   '), 'attachment');
    expect(sanitizeSaveFileName('照片 1.jpg'), '照片 1.jpg');
  });

  test('describe never claims a save that did not happen', () {
    expect(const FileSaveResult.cancelled().describe('a.png'), isNull);
    expect(const FileSaveResult.unsupported().describe('a.png'),
        '当前平台不支持保存文件');
    expect(
        const FileSaveResult.saved(FileSaveDestination.gallery)
            .describe('a.png'),
        '已保存到相册');
    expect(
        const FileSaveResult.saved(FileSaveDestination.browserDownloads)
            .describe('a.png'),
        '已下载 a.png');
  });
}
