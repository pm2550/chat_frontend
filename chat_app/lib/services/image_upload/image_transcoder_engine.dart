import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_transcoder.dart';

ImageTranscoder createPlatformImageTranscoder() => EngineImageTranscoder();

/// 原生平台（Android / iOS / 桌面）：
/// 解码交给 Flutter 引擎（Skia/平台解码器，Android 上还能解 HEIF），解码时直接缩到目标尺寸，
/// 大照片不用先整张解到内存里；拿到像素后在后台 isolate 里摆正、编码，界面不卡。
class EngineImageTranscoder implements ImageTranscoder {
  @override
  Future<TranscodedImage?> transcode(TranscodeRequest request) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(request.bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final (width, height) = fitLongEdge(
        descriptor.width,
        descriptor.height,
        request.maxLongEdge,
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: width,
        targetHeight: height,
      );
      image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (pixels == null) return null;
      final job = EncodeJob(
        pixels: TransferableTypedData.fromList([pixels.buffer.asUint8List()]),
        width: image.width,
        height: image.height,
        orientation: request.orientation,
        policy: request.policy,
        quality: request.quality,
        thumbnailLongEdge: request.thumbnailLongEdge,
        thumbnailQuality: request.thumbnailQuality,
      );
      return await compute(encodeRgbaJob, job);
    } catch (error) {
      debugPrint('图片压缩：解码失败，原样发送: $error');
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

/// 交给后台 isolate 的编码任务：非预乘 RGBA 像素 + 怎么摆正、怎么编码。
class EncodeJob {
  const EncodeJob({
    required this.pixels,
    required this.width,
    required this.height,
    required this.orientation,
    required this.policy,
    required this.quality,
    this.thumbnailLongEdge,
    this.thumbnailQuality = 75,
  });

  final TransferableTypedData pixels;
  final int width;
  final int height;
  final int orientation;
  final TranscodeFormatPolicy policy;
  final int quality;
  final int? thumbnailLongEdge;
  final int thumbnailQuality;
}

/// 在后台 isolate 里跑：摆正方向、选格式、编码；输出不写任何元数据。
TranscodedImage encodeRgbaJob(EncodeJob job) {
  final rgba = job.pixels.materialize().asUint8List();
  final traits = analyzePixels(rgba, job.width, job.height);
  final png = choosePng(job.policy, traits);
  var image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  if (job.orientation >= 2 && job.orientation <= 8) {
    image.exif.imageIfd.orientation = job.orientation;
    image = img.bakeOrientation(image);
  }
  // 从像素新建的图本来就没有 EXIF/ICC/文本，这里再清一遍，保证输出不带任何元数据。
  image
    ..exif = img.ExifData()
    ..iccProfile = null
    ..textData = null;

  final bytes = _encode(image,
      png: png, transparent: traits.hasTransparency, quality: job.quality);
  Uint8List? thumbnail;
  final thumbEdge = job.thumbnailLongEdge;
  if (thumbEdge != null) {
    final (tw, th) = fitLongEdge(image.width, image.height, thumbEdge);
    final small = tw == image.width && th == image.height
        ? image
        : img.copyResize(
            image,
            width: tw,
            height: th,
            interpolation: img.Interpolation.average,
          );
    thumbnail = _encode(
      small,
      png: traits.hasTransparency,
      transparent: traits.hasTransparency,
      quality: job.thumbnailQuality,
    );
  }
  return TranscodedImage(
    bytes: bytes,
    mimeType: png ? 'image/png' : 'image/jpeg',
    width: image.width,
    height: image.height,
    thumbnail: thumbnail,
  );
}

Uint8List _encode(
  img.Image image, {
  required bool png,
  required bool transparent,
  required int quality,
}) {
  if (png) {
    final source = transparent ? image : image.convert(numChannels: 3);
    return img.encodePng(source, level: 6);
  }
  final opaque =
      transparent ? _flattenOnWhite(image) : image.convert(numChannels: 3);
  return img.encodeJpg(opaque, quality: quality, chroma: img.JpegChroma.yuv420);
}

/// JPEG 没有透明：铺白底（不然透明处会变黑）。
img.Image _flattenOnWhite(img.Image image) {
  final out =
      img.Image(width: image.width, height: image.height, numChannels: 3);
  for (final pixel in image) {
    final a = pixel.a / 255.0;
    out.setPixelRgb(
      pixel.x,
      pixel.y,
      (pixel.r * a + 255 * (1 - a)).round(),
      (pixel.g * a + 255 * (1 - a)).round(),
      (pixel.b * a + 255 * (1 - a)).round(),
    );
  }
  return out;
}
