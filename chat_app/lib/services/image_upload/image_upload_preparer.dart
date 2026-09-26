import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../chat_data_service.dart';
import 'image_inspector.dart';
import 'image_metadata.dart';
import 'image_transcoder.dart';

/// 发图前的处理规则（和微信的"压缩 / 原图"一致）。
class ImageUploadPolicy {
  const ImageUploadPolicy._();

  /// 压缩后长边不超过这么多像素。
  static const int maxLongEdge = 2048;
  static const int jpegQuality = 82;

  /// 小于这么大、长边也不超过 [maxLongEdge] 的图直接发原图（只删元数据）。
  static const int smallOriginalBytes = 300 * 1024;

  /// 压缩结果至少要比原图小这么多（比例）才用，不然发原图。
  static const double minSaving = 0.10;

  /// 端到端加密时发送端自己做的小预览图（明文会话由服务器生成，尺寸质量一致）。
  /// 720px：气泡里只轻微放大，首屏也够快（照片四五十 KB）。1.1.51 是 400px，糊。
  static const int thumbnailLongEdge = 720;
  static const int thumbnailQuality = 82;

  /// 端到端加密的大原图（超过 Message.sharpOriginalMaxBytes）另做的中图，和服务器的一致。
  static const int previewLongEdge = 1280;
  static const int previewQuality = 82;

  /// 比这还小的图不另做预览图，对方直接加载原图（和服务器的规则一致）。
  static const int thumbnailMinBytes = 100 * 1024;

  /// "原图"模式下 iPhone 的 HEIC 转成 JPEG（很多设备放不了 HEIC）：高质量、长边上限更大。
  /// 4096 也是 iOS Safari canvas 能处理的安全尺寸。
  static const int originalHeicLongEdge = 4096;
  static const int originalHeicQuality = 92;

  /// 解码/编码卡住时不能让发送一直停在"正在压缩"：超时就发原图。
  static const Duration transcodeTimeout = Duration(seconds: 60);
}

enum ImagePrepareOutcome {
  /// 缩小/重新编码过。
  compressed,

  /// 原图像素原样发出，只删了元数据（EXIF/GPS 等）。
  metadataStripped,

  /// 完全原样（动图、不认识的格式、删不了元数据的格式）。
  untouched,
}

/// 处理好的待上传图片。
class PreparedImageUpload {
  const PreparedImageUpload({
    required this.file,
    required this.originalSize,
    required this.outcome,
    this.elapsed = Duration.zero,
  });

  /// 要上传的文件（字节在内存里）；图片的小预览图挂在 [PickedChatFile.thumbnail] 上。
  final PickedChatFile file;
  final int originalSize;
  final ImagePrepareOutcome outcome;
  final Duration elapsed;

  int get uploadSize => file.size;
}

typedef PickedFileBytesReader = Future<Uint8List> Function(PickedChatFile file);

/// 发图前在本机处理图片：摆正方向、缩到长边 2048、重新编码、删掉全部元数据（含 GPS）；
/// "原图"模式只删元数据、像素原样。所有发图入口（相册、相机、粘贴、拖放、发送栏）都经过这里，
/// 端到端加密的私聊在加密之前处理。
///
/// 同时最多处理 [maxConcurrent] 张：一次拖进来十张照片时不至于同时解十张大图把内存撑爆。
class ImageUploadPreparer {
  ImageUploadPreparer({
    ImageTranscoder? transcoder,
    PickedFileBytesReader? readBytes,
    this.maxConcurrent = 2,
  })  : _transcoder = transcoder,
        _readBytes = readBytes ?? readPickedChatFileBytes;

  static final ImageUploadPreparer shared = ImageUploadPreparer();

  ImageTranscoder? _transcoder;
  final PickedFileBytesReader _readBytes;
  final int maxConcurrent;
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  ImageTranscoder get _codec =>
      _transcoder ??= ImageTranscoder.platformDefault();

  /// 看文件名/类型像不像图片（决定要不要走 [prepare]；最终以文件头为准）。
  static bool looksLikeImage(PickedChatFile file) {
    final mime = file.mimeType?.toLowerCase();
    if (mime != null && mime.startsWith('image/')) return true;
    return RegExp(r'\.(jpe?g|png|webp|heic|heif|avif|bmp|gif)$',
            caseSensitive: false)
        .hasMatch(file.name);
  }

  /// 处理一张图。[original] = 用户勾了"原图"。出错时退回原样发送，不会抛异常。
  Future<PreparedImageUpload> prepare(
    PickedChatFile file, {
    bool original = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final Uint8List bytes;
    try {
      bytes = await _readBytes(file);
    } catch (error) {
      debugPrint('图片压缩：读取文件失败，原样发送: $error');
      return PreparedImageUpload(
        file: file,
        originalSize: file.size,
        outcome: ImagePrepareOutcome.untouched,
      );
    }
    final result = await _prepareBytes(file, bytes, original: original);
    return PreparedImageUpload(
      file: result.file,
      originalSize: bytes.length,
      outcome: result.outcome,
      elapsed: stopwatch.elapsed,
    );
  }

  /// 给一张图做长边 720 的小预览图（转发到加密私聊等没有现成预览图的场合）。做不了返回 null。
  Future<Uint8List?> thumbnailFor(Uint8List bytes) => _rendition(
        bytes,
        longEdge: ImageUploadPolicy.thumbnailLongEdge,
        quality: ImageUploadPolicy.thumbnailQuality,
      );

  /// 给端到端加密的大原图做长边 1280 的中图。做不了、或者没比原图小一半，返回 null
  /// （对方停在缩略图，点开再下原图）。
  Future<Uint8List?> previewFor(Uint8List bytes) async {
    final preview = await _rendition(
      bytes,
      longEdge: ImageUploadPolicy.previewLongEdge,
      quality: ImageUploadPolicy.previewQuality,
    );
    if (preview == null || preview.length > bytes.length / 2) return null;
    return preview;
  }

  Future<Uint8List?> _rendition(
    Uint8List bytes, {
    required int longEdge,
    required int quality,
  }) async {
    final info = inspectImage(bytes);
    if (!_decodable(info) || info.animated) return null;
    final bare = info.format == ImageFormat.jpeg
        ? stripImageMetadata(bytes, format: info.format)
        : null;
    final result = await _transcode(TranscodeRequest(
      bytes: bare ?? bytes,
      sourceMimeType: info.mimeType,
      orientation: bare != null ? info.orientation : 1,
      maxLongEdge: longEdge,
      policy: TranscodeFormatPolicy.pngForTransparency,
      quality: quality,
    ));
    return result?.bytes;
  }

  Future<({PickedChatFile file, ImagePrepareOutcome outcome})> _prepareBytes(
    PickedChatFile file,
    Uint8List bytes, {
    required bool original,
  }) async {
    final info = inspectImage(bytes);
    ({PickedChatFile file, ImagePrepareOutcome outcome}) untouched() => (
          file:
              _withBytes(file, bytes, mimeType: file.mimeType ?? info.mimeType),
          outcome: ImagePrepareOutcome.untouched,
        );

    // 动图原样发：重新编码只剩第一帧。不认识的格式也原样发。
    if (info.format == ImageFormat.unknown ||
        info.format == ImageFormat.gif ||
        info.animated) {
      return untouched();
    }

    // HEIC/AVIF 删不了元数据，很多设备也放不了：能解就转成 JPEG（输出不带元数据），解不了原样发。
    if (info.format == ImageFormat.heic || info.format == ImageFormat.avif) {
      final result = await _transcode(TranscodeRequest(
        bytes: bytes,
        sourceMimeType: info.mimeType,
        maxLongEdge: original
            ? ImageUploadPolicy.originalHeicLongEdge
            : ImageUploadPolicy.maxLongEdge,
        policy: TranscodeFormatPolicy.jpeg,
        quality: original
            ? ImageUploadPolicy.originalHeicQuality
            : ImageUploadPolicy.jpegQuality,
        thumbnailLongEdge: ImageUploadPolicy.thumbnailLongEdge,
        thumbnailQuality: ImageUploadPolicy.thumbnailQuality,
      ));
      if (result == null) return untouched();
      return (
        file: _transcodedFile(file, result),
        outcome: ImagePrepareOutcome.compressed,
      );
    }

    // JPEG / PNG / WebP：先无损删元数据。bare 不带任何 EXIF（给解码器用，方向由我们摆正）；
    // kept 是发原图时用的：补回只含方向的最小 EXIF，竖拍照片才不会躺着。
    final bare = stripImageMetadata(bytes, format: info.format);
    final orientation = bare != null ? info.orientation : 1;
    final kept = bare == null
        ? bytes
        : (orientation == 1
            ? bare
            : stripImageMetadata(bytes,
                    format: info.format, orientation: orientation) ??
                bare);
    final keptOutcome = bare == null
        ? ImagePrepareOutcome.untouched
        : ImagePrepareOutcome.metadataStripped;
    PickedChatFile keptFile({Future<Uint8List?> Function()? thumbnail}) =>
        _withBytes(file, kept,
            mimeType: file.mimeType ?? info.mimeType, thumbnail: thumbnail);

    if (original) {
      return (
        file: keptFile(
          thumbnail: kept.length < ImageUploadPolicy.thumbnailMinBytes
              ? null
              : () => thumbnailFor(kept),
        ),
        outcome: keptOutcome,
      );
    }

    final longEdge = info.longEdge;
    final small = bytes.length < ImageUploadPolicy.smallOriginalBytes &&
        longEdge != null &&
        longEdge <= ImageUploadPolicy.maxLongEdge;
    if (small) {
      // 本来就小：原图发出去也快，对方直接看原图，不用另做预览图。
      return (file: keptFile(), outcome: keptOutcome);
    }

    final lossless = info.format != ImageFormat.jpeg;
    final result = await _transcode(TranscodeRequest(
      bytes: bare ?? bytes,
      sourceMimeType: info.mimeType,
      orientation: orientation,
      maxLongEdge: ImageUploadPolicy.maxLongEdge,
      policy:
          lossless ? TranscodeFormatPolicy.auto : TranscodeFormatPolicy.jpeg,
      quality: ImageUploadPolicy.jpegQuality,
      thumbnailLongEdge: ImageUploadPolicy.thumbnailLongEdge,
      thumbnailQuality: ImageUploadPolicy.thumbnailQuality,
    ));
    if (result == null) return (file: keptFile(), outcome: keptOutcome);
    final thumbnail = result.thumbnail;
    final Future<Uint8List?> Function()? thumbnailLoader =
        thumbnail == null ? null : () async => thumbnail;
    if (result.bytes.length > kept.length * (1 - ImageUploadPolicy.minSaving)) {
      // 没省下多少：发原图（已删元数据），预览图照用。
      return (file: keptFile(thumbnail: thumbnailLoader), outcome: keptOutcome);
    }
    return (
      file: _transcodedFile(file, result),
      outcome: ImagePrepareOutcome.compressed,
    );
  }

  bool _decodable(ImageHeaderInfo info) =>
      info.format != ImageFormat.unknown && info.format != ImageFormat.gif;

  Future<TranscodedImage?> _transcode(TranscodeRequest request) async {
    await _acquire();
    try {
      return await _codec
          .transcode(request)
          .timeout(ImageUploadPolicy.transcodeTimeout, onTimeout: () => null);
    } catch (error) {
      debugPrint('图片压缩失败，原样发送: $error');
      return null;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final ticket = Completer<void>();
    _waiting.add(ticket);
    await ticket.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  PickedChatFile _transcodedFile(PickedChatFile file, TranscodedImage result) {
    final extension = result.mimeType == 'image/png' ? 'png' : 'jpg';
    final thumbnail = result.bytes.length < ImageUploadPolicy.thumbnailMinBytes
        ? null
        : result.thumbnail;
    return PickedChatFile(
      name: _renameExtension(file.name, extension),
      size: result.bytes.length,
      mimeType: result.mimeType,
      bytes: result.bytes,
      thumbnail: thumbnail == null ? null : () async => thumbnail,
    );
  }

  static PickedChatFile _withBytes(
    PickedChatFile file,
    Uint8List bytes, {
    String? mimeType,
    Future<Uint8List?> Function()? thumbnail,
  }) {
    return PickedChatFile(
      name: file.name,
      size: bytes.length,
      mimeType: mimeType,
      bytes: bytes,
      thumbnail: thumbnail,
    );
  }

  static String _renameExtension(String name, String extension) {
    final dot = name.lastIndexOf('.');
    final base =
        dot > 0 ? name.substring(0, dot) : (name.isEmpty ? 'image' : name);
    return '$base.$extension';
  }
}

/// 取文件字节：web 选的文件本来就在内存里，原生平台按路径读（借 http 的 fromPath，
/// 这样不用直接依赖 dart:io，web 照样能编译）。
Future<Uint8List> readPickedChatFileBytes(PickedChatFile file) async {
  final bytes = file.bytes;
  if (bytes != null) {
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }
  final path = file.path;
  if (path == null || path.isEmpty) {
    throw const ChatDataException('请选择有效文件');
  }
  final part = await http.MultipartFile.fromPath('file', path);
  return part.finalize().toBytes();
}
