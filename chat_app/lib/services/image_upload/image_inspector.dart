import 'dart:typed_data';

/// 按文件头认出来的图片格式（不看扩展名和 mimeType：粘贴、拖放来的文件常常标错）。
enum ImageFormat { jpeg, png, gif, webp, heic, avif, bmp, unknown }

/// 只读文件头得到的图片信息，不解码像素。
class ImageHeaderInfo {
  const ImageHeaderInfo({
    required this.format,
    this.width,
    this.height,
    this.animated = false,
    this.orientation = 1,
  });

  static const unknown = ImageHeaderInfo(format: ImageFormat.unknown);

  final ImageFormat format;

  /// 像素按存储方向的宽高（JPEG 还没按 EXIF 方向摆正）；读不到时为 null。
  final int? width;
  final int? height;

  /// 动图（GIF 一律算，APNG、动态 WebP）：发出去原样不动。
  final bool animated;

  /// JPEG 的 EXIF 方向（1–8），其他格式为 1。
  final int orientation;

  int? get longEdge => width == null || height == null
      ? null
      : (width! > height! ? width : height);

  String get mimeType => switch (format) {
        ImageFormat.jpeg => 'image/jpeg',
        ImageFormat.png => 'image/png',
        ImageFormat.gif => 'image/gif',
        ImageFormat.webp => 'image/webp',
        ImageFormat.heic => 'image/heic',
        ImageFormat.avif => 'image/avif',
        ImageFormat.bmp => 'image/bmp',
        ImageFormat.unknown => 'application/octet-stream',
      };
}

ImageHeaderInfo inspectImage(Uint8List bytes) {
  try {
    if (_isJpeg(bytes)) return _inspectJpeg(bytes);
    if (_startsWith(
        bytes, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return _inspectPng(bytes);
    }
    if (_ascii(bytes, 0, 4) == 'GIF8') {
      return ImageHeaderInfo(
        format: ImageFormat.gif,
        width: bytes.length >= 10 ? _u16le(bytes, 6) : null,
        height: bytes.length >= 10 ? _u16le(bytes, 8) : null,
        animated: true,
      );
    }
    if (_ascii(bytes, 0, 4) == 'RIFF' && _ascii(bytes, 8, 4) == 'WEBP') {
      return _inspectWebp(bytes);
    }
    if (_ascii(bytes, 4, 4) == 'ftyp') {
      final format = _isoBrandFormat(bytes);
      if (format != null) return ImageHeaderInfo(format: format);
    }
    if (_ascii(bytes, 0, 2) == 'BM' && bytes.length >= 26) {
      return ImageHeaderInfo(
        format: ImageFormat.bmp,
        width: _u32le(bytes, 18).toSigned(32).abs(),
        height: _u32le(bytes, 22).toSigned(32).abs(),
      );
    }
  } on RangeError {
    // 文件头被截断：当成不认识的文件原样发。
  }
  return ImageHeaderInfo.unknown;
}

bool _isJpeg(Uint8List b) =>
    b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

ImageHeaderInfo _inspectJpeg(Uint8List b) {
  int? width;
  int? height;
  var orientation = 1;
  var offset = 2;
  while (offset + 4 <= b.length) {
    if (b[offset] != 0xFF) break;
    final marker = b[offset + 1];
    if (marker == 0xFF) {
      offset++; // 填充字节
      continue;
    }
    if (marker == 0xD8 ||
        (marker >= 0xD0 && marker <= 0xD7) ||
        marker == 0x01) {
      offset += 2;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) break;
    final length = _u16be(b, offset + 2);
    if (length < 2 || offset + 2 + length > b.length) break;
    if (marker == 0xE1 && orientation == 1) {
      orientation =
          readExifOrientation(b, offset + 4, offset + 2 + length) ?? 1;
    }
    if (isJpegStartOfFrame(marker) && length >= 7) {
      height = _u16be(b, offset + 5);
      width = _u16be(b, offset + 7);
    }
    offset += 2 + length;
  }
  return ImageHeaderInfo(
    format: ImageFormat.jpeg,
    width: width,
    height: height,
    orientation: orientation,
  );
}

bool isJpegStartOfFrame(int marker) =>
    marker >= 0xC0 &&
    marker <= 0xCF &&
    marker != 0xC4 &&
    marker != 0xC8 &&
    marker != 0xCC;

/// APP1 段内容（[start] 指向 "Exif\0\0"）里第 0 个 IFD 的 Orientation；不是 EXIF 段或没有该标签返回 null。
int? readExifOrientation(Uint8List b, int start, int end) {
  if (end - start < 14 || _ascii(b, start, 6) != 'Exif\u0000\u0000') {
    return null;
  }
  final tiff = start + 6;
  final little = b[tiff] == 0x49 && b[tiff + 1] == 0x49;
  final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D;
  if (!little && !big) return null;
  int u16(int at) => little ? _u16le(b, at) : _u16be(b, at);
  int u32(int at) => little ? _u32le(b, at) : _u32be(b, at);
  final ifd = tiff + u32(tiff + 4);
  if (ifd + 2 > end) return null;
  final count = u16(ifd);
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > end) break;
    if (u16(entry) == 0x0112) {
      final value = u16(entry + 8);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}

ImageHeaderInfo _inspectPng(Uint8List b) {
  final width = b.length >= 24 ? _u32be(b, 16) : null;
  final height = b.length >= 24 ? _u32be(b, 20) : null;
  var animated = false;
  var offset = 8;
  while (offset + 8 <= b.length) {
    final length = _u32be(b, offset);
    final type = _ascii(b, offset + 4, 4);
    if (type == 'acTL') {
      animated = true;
      break;
    }
    if (type == 'IDAT' || type == 'IEND') break;
    offset += 12 + length;
  }
  return ImageHeaderInfo(
    format: ImageFormat.png,
    width: width,
    height: height,
    animated: animated,
  );
}

ImageHeaderInfo _inspectWebp(Uint8List b) {
  final chunk = _ascii(b, 12, 4);
  switch (chunk) {
    case 'VP8X':
      return ImageHeaderInfo(
        format: ImageFormat.webp,
        width: _u24le(b, 24) + 1,
        height: _u24le(b, 27) + 1,
        animated: b[20] & 0x02 != 0,
      );
    case 'VP8 ':
      return ImageHeaderInfo(
        format: ImageFormat.webp,
        width: _u16le(b, 26) & 0x3FFF,
        height: _u16le(b, 28) & 0x3FFF,
      );
    case 'VP8L':
      final bits = _u32le(b, 21);
      return ImageHeaderInfo(
        format: ImageFormat.webp,
        width: (bits & 0x3FFF) + 1,
        height: ((bits >> 14) & 0x3FFF) + 1,
      );
  }
  return const ImageHeaderInfo(format: ImageFormat.webp);
}

/// iPhone 的 HEIC / HEIF 和 AVIF 都是 ISO BMFF 容器，按 ftyp 里的品牌区分。
ImageFormat? _isoBrandFormat(Uint8List b) {
  final boxSize = _u32be(b, 0);
  final end = boxSize >= 16 && boxSize <= b.length
      ? boxSize
      : (b.length < 64 ? b.length : 64);
  final brands = <String>[_ascii(b, 8, 4)];
  for (var at = 16; at + 4 <= end; at += 4) {
    brands.add(_ascii(b, at, 4));
  }
  if (brands.contains('avif') || brands.contains('avis')) {
    return ImageFormat.avif;
  }
  const heif = {'heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'mif1', 'msf1'};
  if (brands.any(heif.contains)) return ImageFormat.heic;
  return null;
}

bool _startsWith(Uint8List b, List<int> prefix) {
  if (b.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (b[i] != prefix[i]) return false;
  }
  return true;
}

String _ascii(Uint8List b, int offset, int length) {
  if (offset < 0 || offset + length > b.length) return '';
  return String.fromCharCodes(b, offset, offset + length);
}

int _u16be(Uint8List b, int at) => (b[at] << 8) | b[at + 1];
int _u16le(Uint8List b, int at) => b[at] | (b[at + 1] << 8);
int _u24le(Uint8List b, int at) => b[at] | (b[at + 1] << 8) | (b[at + 2] << 16);
// 最高字节用乘法：编译成 JS 时位运算是 32 位有符号的，`<< 24` 会变成负数。
int _u32be(Uint8List b, int at) =>
    b[at] * 0x1000000 + ((b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]);
int _u32le(Uint8List b, int at) =>
    b[at + 3] * 0x1000000 + ((b[at + 2] << 16) | (b[at + 1] << 8) | b[at]);
