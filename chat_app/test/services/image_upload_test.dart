import 'dart:math';
import 'dart:typed_data';

import 'package:chat_app/services/chat_data_service.dart';
import 'package:chat_app/services/image_upload/image_inspector.dart';
import 'package:chat_app/services/image_upload/image_metadata.dart';
import 'package:chat_app/services/image_upload/image_transcoder.dart';
import 'package:chat_app/services/image_upload/image_transcoder_engine.dart';
import 'package:chat_app/services/image_upload/image_upload_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 一张"手机照片"：噪点足够多，JPEG 压不小；带机型、拍摄方向和 GPS 定位。
Uint8List photoJpeg({
  int width = 3000,
  int height = 2000,
  int orientation = 1,
  bool gps = true,
  int quality = 92,
  bool redLeftBlueRight = false,
}) {
  final image = img.Image(width: width, height: height);
  final random = Random(7);
  for (final pixel in image) {
    final noise = random.nextInt(40) - 20;
    if (redLeftBlueRight) {
      final red = pixel.x < width ~/ 2;
      pixel
        ..r = (red ? 220 : 20) + noise ~/ 2
        ..g = 30 + noise ~/ 2
        ..b = (red ? 20 : 220) + noise ~/ 2;
    } else {
      pixel
        ..r = (pixel.x * 255 ~/ width + noise).clamp(0, 255)
        ..g = (120 + noise).clamp(0, 255)
        ..b = (255 - pixel.y * 255 ~/ height + noise).clamp(0, 255);
    }
  }
  image.exif.imageIfd['Make'] = img.IfdValueAscii('Apple');
  image.exif.imageIfd['Model'] = img.IfdValueAscii('iPhone 15 Pro');
  if (orientation != 1) image.exif.imageIfd.orientation = orientation;
  if (gps) image.exif.gpsIfd.setGpsLocation(latitude: 31.23, longitude: 121.47);
  return img.encodeJpg(image, quality: quality);
}

/// 像截图的 PNG：大块纯色 + 少量颜色的"文字"条纹。
Uint8List screenshotPng({int width = 2400, int height = 1500}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(246, 247, 250));
  img.fillRect(image,
      x1: 0, y1: 0, x2: width, y2: 80, color: img.ColorRgb8(30, 64, 175));
  for (var line = 0; line < 60; line++) {
    final y = 120 + line * 22;
    for (var x = 40; x < width - 200; x += 9) {
      if ((x ~/ 9 + line) % 5 == 0) continue;
      img.fillRect(image,
          x1: x,
          y1: y,
          x2: x + 6,
          y2: y + 12,
          color: img.ColorRgb8(33, 33, 33));
    }
  }
  image.textData = {'Software': 'Screenshot tool', 'Author': 'someone'};
  return img.encodePng(image);
}

Uint8List noisyPng(
    {int width = 1600, int height = 1200, bool transparentCorner = false}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  final random = Random(3);
  for (final pixel in image) {
    pixel
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256)
      ..a = transparentCorner && pixel.x < 100 && pixel.y < 100 ? 0 : 255;
  }
  return img.encodePng(image);
}

bool hasExifSegment(Uint8List jpeg) {
  var offset = 2;
  while (offset + 4 <= jpeg.length && jpeg[offset] == 0xFF) {
    final marker = jpeg[offset + 1];
    if (marker == 0xDA) return false;
    final length = (jpeg[offset + 2] << 8) | jpeg[offset + 3];
    if (marker == 0xE1) return true;
    offset += 2 + length;
  }
  return false;
}

bool containsAscii(Uint8List bytes, String text) {
  final needle = text.codeUnits;
  outer:
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

PickedChatFile picked(Uint8List bytes, String name, String mime) =>
    PickedChatFile(
        name: name, size: bytes.length, mimeType: mime, bytes: bytes);

/// 记录收到的请求，按测试给的结果返回，不真的解码。
class _RecordingTranscoder implements ImageTranscoder {
  _RecordingTranscoder(this.respond);

  final TranscodedImage? Function(TranscodeRequest request) respond;
  final List<TranscodeRequest> requests = [];

  @override
  Future<TranscodedImage?> transcode(TranscodeRequest request) async {
    requests.add(request);
    return respond(request);
  }
}

TranscodedImage fakeResult(int size,
        {String mime = 'image/jpeg', Uint8List? thumbnail}) =>
    TranscodedImage(
      bytes: Uint8List(size),
      mimeType: mime,
      width: 2048,
      height: 1365,
      thumbnail: thumbnail,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('inspectImage', () {
    test('reads JPEG size and EXIF orientation, PNG/GIF/WebP/HEIC signatures',
        () {
      final jpeg = photoJpeg(width: 64, height: 32, orientation: 6);
      final info = inspectImage(jpeg);
      expect(info.format, ImageFormat.jpeg);
      expect((info.width, info.height, info.orientation), (64, 32, 6));

      expect(
          inspectImage(img.encodePng(img.Image(width: 5, height: 7))).longEdge,
          7);
      expect(
          inspectImage(img.encodeGif(img.Image(width: 4, height: 4))).animated,
          isTrue);

      final heic = Uint8List.fromList([
        0,
        0,
        0,
        24,
        ...'ftypheic'.codeUnits,
        0,
        0,
        0,
        0,
        ...'mif1heic'.codeUnits,
      ]);
      expect(inspectImage(heic).format, ImageFormat.heic);
      expect(inspectImage(Uint8List.fromList([1, 2, 3])).format,
          ImageFormat.unknown);
    });

    test('APNG (acTL before IDAT) counts as animated', () {
      final frames = img.Image(width: 8, height: 8)
        ..addFrame(img.Image(width: 8, height: 8));
      final apng = img.encodePng(frames);
      expect(inspectImage(apng).animated, isTrue);
    });
  });

  group('stripImageMetadata (原图)', () {
    test('JPEG: GPS/机型全删、只留方向，熵编码数据一字节不变，EOI 后的附加数据丢掉', () {
      final source = photoJpeg(width: 640, height: 480, orientation: 6);
      final exif = img.decodeJpgExif(source)!;
      expect(exif.gpsIfd.hasGPSLatitude, isTrue, reason: '测试图要真带 GPS');
      // 模拟手机相机在 EOI 后面挂的多图/动态照片数据。
      final withTrailer =
          Uint8List.fromList([...source, ...'MotionPhotoVideo'.codeUnits]);

      final stripped = stripImageMetadata(withTrailer, orientation: 6)!;

      final after = img.decodeJpgExif(stripped)!;
      expect(after.gpsIfd.hasGPSLatitude, isFalse);
      expect(after.imageIfd['Make'], isNull);
      expect(after.imageIfd.orientation, 6, reason: '竖拍照片要保留方向');
      expect(containsAscii(stripped, 'Apple'), isFalse);
      expect(containsAscii(stripped, 'MotionPhotoVideo'), isFalse);
      expect(jpegScanData(stripped), jpegScanData(source), reason: '像素数据原样保留');
      expect(img.decodeJpg(stripped)!.width, isNotNull);

      final bare = stripImageMetadata(source)!;
      expect(hasExifSegment(bare), isFalse);
      expect(jpegScanData(bare), jpegScanData(source));
    });

    test('PNG: 文本块删掉，IDAT 原样', () {
      final source = screenshotPng(width: 200, height: 120);
      expect(containsAscii(source, 'Screenshot tool'), isTrue);

      final stripped = stripImageMetadata(source)!;

      expect(containsAscii(stripped, 'Screenshot tool'), isFalse);
      expect(containsAscii(stripped, 'tEXt'), isFalse);
      expect(img.decodePng(stripped)!.getPixel(10, 10),
          img.decodePng(source)!.getPixel(10, 10));
      expect(stripped.length, lessThan(source.length));
    });

    test('WebP: 删掉 EXIF/XMP 块并清掉标志位', () {
      List<int> chunk(String type, List<int> data) => [
            ...type.codeUnits,
            data.length & 0xFF,
            (data.length >> 8) & 0xFF,
            0,
            0,
            ...data,
            if (data.length.isOdd) 0,
          ];
      final vp8x = chunk('VP8X', [0x08 | 0x04, 0, 0, 0, 9, 0, 0, 9, 0, 0]);
      final body = [
        ...'WEBP'.codeUnits,
        ...vp8x,
        ...chunk('VP8L', List.filled(20, 1)),
        ...chunk('EXIF', 'GPS secret'.codeUnits),
        ...chunk('XMP ', 'xmp'.codeUnits),
      ];
      final webp = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        body.length & 0xFF,
        (body.length >> 8) & 0xFF,
        0,
        0,
        ...body,
      ]);

      final stripped = stripImageMetadata(webp)!;

      expect(containsAscii(stripped, 'GPS secret'), isFalse);
      expect(containsAscii(stripped, 'XMP '), isFalse);
      expect(stripped[20] & 0x0C, 0, reason: 'EXIF/XMP 标志位清掉');
      expect(stripped[4] | (stripped[5] << 8), stripped.length - 8,
          reason: 'RIFF 长度要改对');
    });

    test('GIF/HEIC 不能无损删，返回 null', () {
      expect(stripImageMetadata(img.encodeGif(img.Image(width: 2, height: 2))),
          isNull);
    });
  });

  group('ImageUploadPreparer decisions', () {
    test('大照片：去掉 EXIF 后交给解码器、按方向摆正、长边 2048、JPEG 82', () async {
      final photo = photoJpeg(orientation: 6);
      final transcoder = _RecordingTranscoder(
          (_) => fakeResult(400 * 1024, thumbnail: Uint8List(30 * 1024)));
      final preparer = ImageUploadPreparer(transcoder: transcoder);

      final prepared =
          await preparer.prepare(picked(photo, 'IMG_0001.JPG', 'image/jpeg'));

      final request = transcoder.requests.single;
      expect(request.maxLongEdge, 2048);
      expect(request.quality, 82);
      expect(request.policy, TranscodeFormatPolicy.jpeg);
      expect(request.orientation, 6);
      expect(hasExifSegment(request.bytes), isFalse,
          reason: '解码器拿到的是去掉 EXIF 的原图');
      expect(request.thumbnailLongEdge, 400);
      expect(prepared.outcome, ImagePrepareOutcome.compressed);
      expect(prepared.file.name, 'IMG_0001.jpg');
      expect(prepared.file.size, 400 * 1024);
      expect(prepared.originalSize, photo.length);
      expect((await prepared.file.thumbnail!())!.length, 30 * 1024);
    });

    test('小图（<300KB 且长边 ≤2048）不压缩，原图只删元数据', () async {
      final small = photoJpeg(width: 400, height: 300, quality: 80);
      expect(small.length, lessThan(300 * 1024));
      final transcoder = _RecordingTranscoder((_) => fail('小图不该重新编码'));

      final prepared = await ImageUploadPreparer(transcoder: transcoder)
          .prepare(picked(small, 'small.jpg', 'image/jpeg'));

      expect(transcoder.requests, isEmpty);
      expect(prepared.outcome, ImagePrepareOutcome.metadataStripped);
      final sent = Uint8List.fromList(prepared.file.bytes!);
      expect(hasExifSegment(sent), isFalse,
          reason: 'GPS 一样要删（方向是 1，EXIF 整段不要）');
      expect(containsAscii(sent, 'Apple'), isFalse);
      expect(jpegScanData(sent), jpegScanData(small));
      expect(prepared.file.thumbnail, isNull);
    });

    test('GIF 原样发，一个字节都不动', () async {
      final gif = img.encodeGif(img.Image(width: 300, height: 300));
      final transcoder = _RecordingTranscoder((_) => fail('动图不能重新编码'));

      final prepared = await ImageUploadPreparer(transcoder: transcoder)
          .prepare(picked(gif, 'funny.gif', 'image/gif'));

      expect(prepared.outcome, ImagePrepareOutcome.untouched);
      expect(prepared.file.bytes, gif);
      expect(prepared.file.name, 'funny.gif');
    });

    test('压缩后没省下 10% 就发原图（删了元数据），预览图照用', () async {
      final photo = photoJpeg(quality: 70);
      expect(photo.length, greaterThan(300 * 1024));
      final transcoder = _RecordingTranscoder(
          (_) => fakeResult(photo.length - 1000, thumbnail: Uint8List(9)));

      final prepared = await ImageUploadPreparer(transcoder: transcoder)
          .prepare(picked(photo, 'p.jpg', 'image/jpeg'));

      expect(prepared.outcome, ImagePrepareOutcome.metadataStripped);
      final sent = Uint8List.fromList(prepared.file.bytes!);
      expect(jpegScanData(sent), jpegScanData(photo));
      expect(hasExifSegment(sent), isFalse);
      expect(await prepared.file.thumbnail!(), Uint8List(9));
    });

    test('原图模式：不重新编码，像素数据不变、GPS 删掉、方向保留', () async {
      final photo = photoJpeg(orientation: 3);
      final transcoder = _RecordingTranscoder((_) => fakeResult(1000));

      final prepared = await ImageUploadPreparer(transcoder: transcoder)
          .prepare(picked(photo, 'IMG.jpg', 'image/jpeg'), original: true);

      expect(transcoder.requests, isEmpty, reason: '原图模式不重新编码');
      final sent = Uint8List.fromList(prepared.file.bytes!);
      expect(jpegScanData(sent), jpegScanData(photo));
      expect(img.decodeJpgExif(sent)!.gpsIfd.hasGPSLatitude, isFalse);
      expect(img.decodeJpgExif(sent)!.imageIfd.orientation, 3);
      expect(prepared.file.name, 'IMG.jpg');
      // 预览图只在加密私聊需要时才做。
      await prepared.file.thumbnail!();
      expect(transcoder.requests.single.maxLongEdge, 400);
    });

    test('PNG 来源允许按内容选 PNG；HEIC 解不了就原样发', () async {
      final transcoder = _RecordingTranscoder((request) =>
          request.sourceMimeType == 'image/heic'
              ? null
              : fakeResult(100 * 1024, mime: 'image/png'));
      final preparer = ImageUploadPreparer(transcoder: transcoder);

      final png = await preparer
          .prepare(picked(screenshotPng(), 'shot.png', 'image/png'));
      expect(transcoder.requests.last.policy, TranscodeFormatPolicy.auto);
      expect(png.file.name, 'shot.png');
      expect(png.file.mimeType, 'image/png');

      final heicBytes = Uint8List.fromList([
        0,
        0,
        0,
        24,
        ...'ftypheic'.codeUnits,
        0,
        0,
        0,
        0,
        ...'mif1heic'.codeUnits,
        ...List.filled(500 * 1024, 7),
      ]);
      final heic =
          await preparer.prepare(picked(heicBytes, 'IMG.HEIC', 'image/heic'));
      expect(transcoder.requests.last.orientation, 1, reason: 'HEIC 的方向交给解码器');
      expect(heic.outcome, ImagePrepareOutcome.untouched);
      expect(heic.file.bytes, heicBytes);
    });

    test('解码器出错时退回原图，不抛异常', () async {
      final photo = photoJpeg(width: 1600, height: 1200);
      final preparer = ImageUploadPreparer(
        transcoder: _RecordingTranscoder((_) => throw StateError('boom')),
      );

      final prepared =
          await preparer.prepare(picked(photo, 'p.jpg', 'image/jpeg'));

      expect(prepared.outcome, ImagePrepareOutcome.metadataStripped);
      expect(jpegScanData(Uint8List.fromList(prepared.file.bytes!)),
          jpegScanData(photo));
    });
  });

  group('EngineImageTranscoder (real decode + encode)', () {
    test('照片：长边 2048、按 EXIF 摆正、输出不带任何 EXIF/GPS、体积大减', () async {
      final photo = photoJpeg(orientation: 6, redLeftBlueRight: true);
      final preparer = ImageUploadPreparer(transcoder: EngineImageTranscoder());

      final prepared =
          await preparer.prepare(picked(photo, 'IMG_0002.jpg', 'image/jpeg'));

      expect(prepared.outcome, ImagePrepareOutcome.compressed);
      final out = Uint8List.fromList(prepared.file.bytes!);
      expect(inspectImage(out).format, ImageFormat.jpeg);
      expect(hasExifSegment(out), isFalse, reason: '输出不带 EXIF（含 GPS）');
      expect(containsAscii(out, 'Apple'), isFalse);
      final decoded = img.decodeJpg(out)!;
      // 原图 3000×2000 横存 + 方向 6 → 摆正后是竖图 1365×2048。
      expect((decoded.width, decoded.height), (1365, 2048));
      final top = decoded.getPixel(decoded.width ~/ 2, 100);
      final bottom = decoded.getPixel(decoded.width ~/ 2, decoded.height - 100);
      expect(top.r > 150 && top.b < 100, isTrue, reason: '原图左半边（红）应在上方: $top');
      expect(bottom.b > 150 && bottom.r < 100, isTrue,
          reason: '原图右半边（蓝）应在下方: $bottom');
      expect(out.length, lessThan(photo.length ~/ 2));

      final thumbnail = (await prepared.file.thumbnail!())!;
      final thumb = img.decodeJpg(thumbnail)!;
      expect(max(thumb.width, thumb.height), 400);
      expect(thumb.height, greaterThan(thumb.width));
    });

    test('截图类 PNG 保持 PNG（文字不糊），照片类 PNG 转 JPEG，透明 PNG 保留透明', () async {
      final preparer = ImageUploadPreparer(transcoder: EngineImageTranscoder());

      // 纯色块的截图原 PNG 本来就压得很小，缩小后边缘的过渡色反而让 PNG 变大：
      // 这时发原图（更清楚也更小），只删掉文本元数据。
      final source = screenshotPng();
      final shot =
          await preparer.prepare(picked(source, 'shot.png', 'image/png'));
      expect(shot.file.mimeType, 'image/png');
      expect(shot.file.size, lessThanOrEqualTo(source.length));
      expect(
          containsAscii(
              Uint8List.fromList(shot.file.bytes!), 'Screenshot tool'),
          isFalse);

      final photoPng =
          await preparer.prepare(picked(noisyPng(), 'photo.png', 'image/png'));
      expect(photoPng.file.mimeType, 'image/jpeg');
      expect(photoPng.file.name, 'photo.jpg');

      final transparent = await preparer.prepare(picked(
          noisyPng(width: 2600, transparentCorner: true),
          'logo.png',
          'image/png'));
      expect(transparent.file.mimeType, 'image/png');
      final decoded =
          img.decodePng(Uint8List.fromList(transparent.file.bytes!))!;
      expect(decoded.width, 2048);
      expect(decoded.getPixel(5, 5).a, 0, reason: '透明区域保留');
    });
  });
}
