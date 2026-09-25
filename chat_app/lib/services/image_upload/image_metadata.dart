import 'dart:typed_data';

import 'image_inspector.dart';

/// 不重新编码、只删元数据：像素数据一个字节都不动。
///
/// 删掉的是会泄露隐私的东西——EXIF（含 GPS 定位、拍摄时间、机型序列号）、XMP、IPTC、注释、
/// 内嵌预览图、JPEG 后面挂的附加数据（多图 MPF、动态照片视频、厂商尾巴）、PNG 的文本块；
/// 保留显示需要的：JFIF、ICC 色彩配置、Adobe 色彩变换、PNG 的伽马/色彩/透明块、APNG 帧。
/// [orientation] 不是 1 时补一个只含方向的最小 EXIF，否则竖拍照片会躺着显示。
///
/// 支持 JPEG、PNG、WebP；其他格式（GIF、HEIC）或文件损坏返回 null，调用方决定怎么办。
Uint8List? stripImageMetadata(
  Uint8List bytes, {
  ImageFormat? format,
  int orientation = 1,
}) {
  try {
    switch (format ?? inspectImage(bytes).format) {
      case ImageFormat.jpeg:
        return _stripJpeg(bytes, orientation);
      case ImageFormat.png:
        return _stripPng(bytes);
      case ImageFormat.webp:
        return _stripWebp(bytes);
      default:
        return null;
    }
  } on RangeError {
    return null;
  }
}

/// JPEG 的熵编码数据（第一个 SOS 起到 EOI），测试用来确认像素数据原样保留。
Uint8List? jpegScanData(Uint8List bytes) {
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return null;
    final marker = bytes[offset + 1];
    if (marker == 0xDA) {
      final end = _jpegScanEnd(bytes, offset);
      return end == null ? null : Uint8List.sublistView(bytes, offset, end);
    }
    offset += 2 + _u16be(bytes, offset + 2);
  }
  return null;
}

Uint8List? _stripJpeg(Uint8List b, int orientation) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var needsOrientation = orientation >= 2 && orientation <= 8;
  var offset = 2;
  while (offset + 4 <= b.length) {
    if (b[offset] != 0xFF) return null;
    final marker = b[offset + 1];
    if (marker == 0xFF) {
      offset++;
      continue;
    }
    // EXIF 放在 JFIF（APP0）之后、其他段之前。
    if (needsOrientation && marker != 0xE0) {
      out.add(_orientationExif(orientation));
      needsOrientation = false;
    }
    if (marker == 0xDA) {
      return _jpegScanEnd(b, offset, keep: out) == null
          ? null
          : out.takeBytes();
    }
    if (marker == 0xD9) return null; // 还没到图像数据就结束了
    final length = _u16be(b, offset + 2);
    final segmentEnd = offset + 2 + length;
    if (length < 2 || segmentEnd > b.length) return null;
    final segment = Uint8List.sublistView(b, offset, segmentEnd);
    if (_keepJpegSegment(marker, segment)) out.add(segment);
    offset = segmentEnd;
  }
  return null;
}

/// 从 SOS 段开始往后走到 EOI（渐进式 JPEG 有多个扫描段，中间夹着 DHT 等表），返回 EOI 之后的位置。
/// 给了 [keep] 就把保留的内容写进去（扫描之间的 APPn/注释同样过滤）。EOI 之后的附加数据全部丢掉。
int? _jpegScanEnd(Uint8List b, int sosOffset, {BytesBuilder? keep}) {
  var offset = sosOffset;
  while (true) {
    // 当前位置是一个带长度的段（第一次是 SOS）。
    if (offset + 4 > b.length) return null;
    final marker = b[offset + 1];
    final length = _u16be(b, offset + 2);
    final segmentEnd = offset + 2 + length;
    if (length < 2 || segmentEnd > b.length) return null;
    final segment = Uint8List.sublistView(b, offset, segmentEnd);
    if (keep != null && _keepJpegSegment(marker, segment)) keep.add(segment);
    offset = segmentEnd;
    if (marker != 0xDA) {
      // 扫描之间的表段，后面紧跟下一个标记。
      if (offset + 2 > b.length || b[offset] != 0xFF) return null;
      if (b[offset + 1] == 0xD9) {
        keep?.add(const [0xFF, 0xD9]);
        return offset + 2;
      }
      continue;
    }
    // 熵编码数据：0xFF 后面跟 0x00（转义）或 RST0–7 仍是数据，其他才是下一个标记。
    final dataStart = offset;
    while (true) {
      if (offset + 1 >= b.length) return null;
      if (b[offset] == 0xFF) {
        final next = b[offset + 1];
        if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
          offset += 2;
          continue;
        }
        if (next == 0xFF) {
          offset++;
          continue;
        }
        break;
      }
      offset++;
    }
    keep?.add(Uint8List.sublistView(b, dataStart, offset));
    if (b[offset + 1] == 0xD9) {
      keep?.add(const [0xFF, 0xD9]);
      return offset + 2;
    }
  }
}

bool _keepJpegSegment(int marker, Uint8List segment) {
  if (marker == 0xFE) return false; // 注释
  if (marker < 0xE0 || marker > 0xEF) return true; // 量化表、霍夫曼表、帧头等
  final body = String.fromCharCodes(
    segment,
    4,
    segment.length < 18 ? segment.length : 18,
  );
  switch (marker) {
    case 0xE0:
      return body.startsWith('JFIF\u0000'); // JFXX 是内嵌缩略图
    case 0xE2:
      return body.startsWith('ICC_PROFILE\u0000'); // MPF（多图）、FPXR 丢掉
    case 0xEE:
      return body.startsWith('Adobe'); // CMYK/YCCK 解码需要
    default:
      return false; // APP1 EXIF/XMP、APP13 IPTC、各厂商私有段
  }
}

/// 只含 Orientation 一个标签的 EXIF APP1 段（大端 TIFF）。
Uint8List _orientationExif(int orientation) => Uint8List.fromList([
      0xFF, 0xE1, 0x00, 0x22, //
      0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
      0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // "MM", 42, IFD0 在偏移 8
      0x00, 0x01, // 1 个条目
      0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, 1 个
      0x00, orientation, 0x00, 0x00, //
      0x00, 0x00, 0x00, 0x00, // 没有下一个 IFD
    ]);

const Set<String> _keptPngChunks = {
  'IHDR', 'PLTE', 'IDAT', 'IEND', // 关键块
  'tRNS', 'cHRM', 'gAMA', 'iCCP', 'sBIT', 'sRGB', 'cICP', 'mDCv', 'cLLi', // 显示
  'bKGD', 'hIST', 'pHYs', 'sPLT',
  'acTL', 'fcTL', 'fdAT', // APNG
};

/// PNG：丢掉 tEXt/zTXt/iTXt（常带软件、作者、截图来源）、eXIf、tIME 和各家私有块。
Uint8List? _stripPng(Uint8List b) {
  if (b.length < 8) return null;
  final out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  var offset = 8;
  while (offset + 12 <= b.length) {
    final length = _u32be(b, offset);
    final end = offset + 12 + length;
    if (end > b.length) return null;
    final type = String.fromCharCodes(b, offset + 4, offset + 8);
    if (_keptPngChunks.contains(type)) {
      out.add(Uint8List.sublistView(b, offset, end));
    }
    offset = end;
    if (type == 'IEND') return out.takeBytes();
  }
  return null;
}

/// WebP：扩展格式（VP8X）里删掉 EXIF、XMP 块并清掉对应标志位；简单格式本来就没有元数据。
Uint8List? _stripWebp(Uint8List b) {
  if (b.length < 20) return null;
  if (String.fromCharCodes(b, 12, 16) != 'VP8X') return b;
  final out = BytesBuilder(copy: false);
  final declared = 8 + _u32le(b, 4);
  final limit = declared < b.length ? declared : b.length;
  var offset = 12;
  while (offset + 8 <= limit) {
    final type = String.fromCharCodes(b, offset, offset + 4);
    final size = _u32le(b, offset + 4);
    final end = offset + 8 + size + (size.isOdd ? 1 : 0);
    if (end > limit) return null;
    if (type == 'VP8X') {
      final chunk = Uint8List.fromList(Uint8List.sublistView(b, offset, end));
      chunk[8] &= ~(0x08 | 0x04); // EXIF、XMP 标志
      out.add(chunk);
    } else if (type != 'EXIF' && type != 'XMP ') {
      out.add(Uint8List.sublistView(b, offset, end));
    }
    offset = end;
  }
  final body = out.takeBytes();
  final riffSize = body.length + 4;
  return (BytesBuilder(copy: false)
        ..add(const [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        ..add([
          riffSize & 0xFF,
          (riffSize >> 8) & 0xFF,
          (riffSize >> 16) & 0xFF,
          (riffSize >> 24) & 0xFF,
        ])
        ..add(const [0x57, 0x45, 0x42, 0x50]) // "WEBP"
        ..add(body))
      .takeBytes();
}

int _u16be(Uint8List b, int at) => (b[at] << 8) | b[at + 1];
int _u32be(Uint8List b, int at) =>
    b[at] * 0x1000000 + ((b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]);
int _u32le(Uint8List b, int at) =>
    b[at + 3] * 0x1000000 + ((b[at + 2] << 16) | (b[at + 1] << 8) | b[at]);
