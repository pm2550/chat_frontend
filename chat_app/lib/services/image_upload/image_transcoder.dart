import 'dart:math' as math;
import 'dart:typed_data';

import 'image_transcoder_engine.dart'
    if (dart.library.js_interop) 'image_transcoder_browser.dart' as platform;

/// 输出格式怎么选。
enum TranscodeFormatPolicy {
  /// 一律 JPEG（有透明就铺白底）。
  jpeg,

  /// 有透明区域或像截图/图表（颜色很少）就用 PNG，文字不糊；否则 JPEG。
  auto,

  /// 只有透明区域才用 PNG（缩略图用：小比清晰重要）。
  pngForTransparency,
}

class TranscodeRequest {
  const TranscodeRequest({
    required this.bytes,
    this.sourceMimeType,
    this.orientation = 1,
    this.maxLongEdge,
    this.policy = TranscodeFormatPolicy.jpeg,
    this.quality = 82,
    this.thumbnailLongEdge,
    this.thumbnailQuality = 75,
  });

  /// 要解码的文件。调用方先删掉了 EXIF，像素按存储方向，[orientation] 由这里负责摆正；
  /// 删不掉 EXIF 的格式传 1，让解码器自己按文件里的方向处理。
  final Uint8List bytes;
  final String? sourceMimeType;
  final int orientation;

  /// 长边上限；null 表示不缩小。从不放大。
  final int? maxLongEdge;
  final TranscodeFormatPolicy policy;

  /// JPEG 质量 1–100。
  final int quality;

  /// 顺带出一张长边这么大的小预览图（端到端加密时由发送端上传）；null 不要。
  final int? thumbnailLongEdge;
  final int thumbnailQuality;
}

class TranscodedImage {
  const TranscodedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    this.thumbnail,
  });

  final Uint8List bytes;
  final String mimeType;

  /// 摆正后的宽高。
  final int width;
  final int height;
  final Uint8List? thumbnail;
}

/// 解码 → 摆正 → 缩小 → 重新编码。输出不带任何元数据（EXIF、GPS、XMP、ICC 都不写）。
/// 解不开（格式不支持、文件坏了）返回 null，调用方原样发送。
abstract class ImageTranscoder {
  Future<TranscodedImage?> transcode(TranscodeRequest request);

  /// 原生平台用引擎解码 + 后台 isolate 编码；网页用浏览器自带的解码和 canvas 编码。
  static ImageTranscoder platformDefault() =>
      platform.createPlatformImageTranscoder();
}

/// 把 [width]×[height] 缩到长边不超过 [maxLongEdge]（保持比例、从不放大、至少 1 像素）。
(int, int) fitLongEdge(int width, int height, int? maxLongEdge) {
  final longest = math.max(width, height);
  if (maxLongEdge == null || longest <= maxLongEdge) return (width, height);
  final scale = maxLongEdge / longest;
  return (
    math.max(1, (width * scale).round()),
    math.max(1, (height * scale).round()),
  );
}

class PixelTraits {
  const PixelTraits({
    required this.hasTransparency,
    required this.looksLikeGraphic,
  });

  final bool hasTransparency;

  /// 颜色很少：截图、图表、带字的图。这种图用 JPEG 会在文字边缘起毛。
  final bool looksLikeGraphic;
}

/// 采样出来的不同颜色不超过这么多，就当成截图/图表。
const int kGraphicColorLimit = 4096;

/// 看一遍 RGBA（非预乘）像素：有没有透明、颜色多不多（按网格采样最多约 6.5 万个点）。
PixelTraits analyzePixels(Uint8List rgba, int width, int height) {
  var transparent = false;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0xFF) {
      transparent = true;
      break;
    }
  }
  const maxSamples = 1 << 16;
  final total = width * height;
  final step = total <= maxSamples ? 1 : math.sqrt(total / maxSamples).ceil();
  final colors = <int>{};
  var graphic = true;
  outer:
  for (var y = 0; y < height; y += step) {
    final row = y * width;
    for (var x = 0; x < width; x += step) {
      final i = (row + x) * 4;
      colors.add((rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2]);
      if (colors.length > kGraphicColorLimit) {
        graphic = false;
        break outer;
      }
    }
  }
  return PixelTraits(hasTransparency: transparent, looksLikeGraphic: graphic);
}

/// 按策略和像素特征定输出格式：true = PNG。
bool choosePng(TranscodeFormatPolicy policy, PixelTraits traits) {
  switch (policy) {
    case TranscodeFormatPolicy.jpeg:
      return false;
    case TranscodeFormatPolicy.pngForTransparency:
      return traits.hasTransparency;
    case TranscodeFormatPolicy.auto:
      return traits.hasTransparency || traits.looksLikeGraphic;
  }
}
