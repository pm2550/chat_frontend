import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'image_transcoder.dart';

ImageTranscoder createPlatformImageTranscoder() => BrowserImageTranscoder();

/// 网页版：解码、缩放、编码全用浏览器自带的（createImageBitmap + canvas.toBlob），
/// 都是原生代码、编码在浏览器后台线程做，界面不卡；纯 Dart 在网页上只能在主线程跑，
/// 一张 1200 万像素的照片要卡好几秒。canvas 导出的 JPEG/PNG 不带任何元数据。
class BrowserImageTranscoder implements ImageTranscoder {
  @override
  Future<TranscodedImage?> transcode(TranscodeRequest request) async {
    web.ImageBitmap? bitmap;
    final scratch = <web.HTMLCanvasElement>[];
    try {
      final blob = web.Blob(
        [request.bytes.toJS].toJS,
        web.BlobPropertyBag(type: request.sourceMimeType ?? ''),
      );
      bitmap = await web.window.createImageBitmap(blob).toDart;
      final rawWidth = bitmap.width;
      final rawHeight = bitmap.height;
      if (rawWidth <= 0 || rawHeight <= 0) return null;
      final orientation = request.orientation;
      final transposed = orientation >= 5 && orientation <= 8;
      final (outWidth, outHeight) = fitLongEdge(
        transposed ? rawHeight : rawWidth,
        transposed ? rawWidth : rawHeight,
        request.maxLongEdge,
      );
      // 按存储方向的目标尺寸：先逐级减半缩到它的两倍以内，最后一步再摆正。
      final drawWidth = transposed ? outHeight : outWidth;
      final drawHeight = transposed ? outWidth : outHeight;
      final (source, sourceWidth, sourceHeight) = _halveDown(
        bitmap,
        rawWidth,
        rawHeight,
        drawWidth,
        drawHeight,
        scratch,
      );

      final output = _canvas(outWidth, outHeight);
      scratch.add(output);
      final context = _context(output);
      if (request.policy == TranscodeFormatPolicy.jpeg) {
        context.fillStyle = 'white'.toJS;
        context.fillRect(0, 0, outWidth, outHeight);
      }
      _applyOrientation(context, orientation, drawWidth, drawHeight);
      context.drawImage(
        source,
        0,
        0,
        sourceWidth,
        sourceHeight,
        0,
        0,
        drawWidth,
        drawHeight,
      );
      context.setTransform(1.toJS, 0, 0, 1, 0, 0);

      var traits =
          const PixelTraits(hasTransparency: false, looksLikeGraphic: false);
      if (request.policy != TranscodeFormatPolicy.jpeg) {
        final data =
            context.getImageData(0, 0, outWidth, outHeight).data.toDart;
        traits = analyzePixels(
          Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
          outWidth,
          outHeight,
        );
      }
      final png = choosePng(request.policy, traits);
      if (!png && traits.hasTransparency) {
        _flattenOnWhite(output);
      }
      final bytes = await _encode(output, png: png, quality: request.quality);
      if (bytes == null) return null;

      Uint8List? thumbnail;
      final thumbEdge = request.thumbnailLongEdge;
      if (thumbEdge != null) {
        final (thumbWidth, thumbHeight) =
            fitLongEdge(outWidth, outHeight, thumbEdge);
        final (thumbSource, tsWidth, tsHeight) = _halveDown(
            output, outWidth, outHeight, thumbWidth, thumbHeight, scratch);
        final small = _canvas(thumbWidth, thumbHeight);
        scratch.add(small);
        final smallContext = _context(small);
        if (!traits.hasTransparency) {
          smallContext.fillStyle = 'white'.toJS;
          smallContext.fillRect(0, 0, thumbWidth, thumbHeight);
        }
        smallContext.drawImage(thumbSource, 0, 0, tsWidth, tsHeight, 0, 0,
            thumbWidth, thumbHeight);
        thumbnail = await _encode(
          small,
          png: traits.hasTransparency,
          quality: request.thumbnailQuality,
        );
      }
      return TranscodedImage(
        bytes: bytes,
        mimeType: png ? 'image/png' : 'image/jpeg',
        width: outWidth,
        height: outHeight,
        thumbnail: thumbnail,
      );
    } catch (error) {
      // 浏览器解不了（例如 Chrome 里的 HEIC）：原样发送。
      debugPrint('图片压缩：浏览器解码失败，原样发送: $error');
      return null;
    } finally {
      bitmap?.close();
      scratch.forEach(_release);
    }
  }

  /// 一步缩得太多会严重锯齿：每次减半，直到不到目标的两倍。
  (web.CanvasImageSource, int, int) _halveDown(
    web.CanvasImageSource source,
    int width,
    int height,
    int targetWidth,
    int targetHeight,
    List<web.HTMLCanvasElement> scratch,
  ) {
    var current = source;
    var w = width;
    var h = height;
    while (w >= targetWidth * 2 && h >= targetHeight * 2) {
      final nw = (w / 2).round();
      final nh = (h / 2).round();
      final canvas = _canvas(nw, nh);
      scratch.add(canvas);
      _context(canvas).drawImage(current, 0, 0, w, h, 0, 0, nw, nh);
      current = canvas;
      w = nw;
      h = nh;
    }
    return (current, w, h);
  }

  web.HTMLCanvasElement _canvas(int width, int height) {
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = width;
    canvas.height = height;
    return canvas;
  }

  web.CanvasRenderingContext2D _context(web.HTMLCanvasElement canvas) {
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = 'high';
    return context;
  }

  /// iOS Safari 对 canvas 总内存有上限：用完的画布立刻缩成 0 释放。
  void _release(web.HTMLCanvasElement canvas) {
    canvas.width = 0;
    canvas.height = 0;
  }

  /// EXIF 方向 → canvas 变换（[width]/[height] 是按存储方向的绘制尺寸）。
  void _applyOrientation(
    web.CanvasRenderingContext2D context,
    int orientation,
    int width,
    int height,
  ) {
    switch (orientation) {
      case 2:
        context.transform(-1, 0, 0, 1, width, 0);
      case 3:
        context.transform(-1, 0, 0, -1, width, height);
      case 4:
        context.transform(1, 0, 0, -1, 0, height);
      case 5:
        context.transform(0, 1, 1, 0, 0, 0);
      case 6:
        context.transform(0, 1, -1, 0, height, 0);
      case 7:
        context.transform(0, -1, -1, 0, height, width);
      case 8:
        context.transform(0, -1, 1, 0, 0, width);
    }
  }

  void _flattenOnWhite(web.HTMLCanvasElement canvas) {
    final context = _context(canvas);
    context.globalCompositeOperation = 'destination-over';
    context.fillStyle = 'white'.toJS;
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.globalCompositeOperation = 'source-over';
  }

  Future<Uint8List?> _encode(
    web.HTMLCanvasElement canvas, {
    required bool png,
    required int quality,
  }) async {
    final done = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? blob) => done.complete(blob)).toJS,
      png ? 'image/png' : 'image/jpeg',
      (quality / 100).toJS,
    );
    final blob = await done.future;
    if (blob == null) return null;
    final buffer = (await blob.arrayBuffer().toDart).toDart;
    // 拷成普通的 Dart 字节数组：后面加密、上传都在 Dart 这边按字节处理。
    return Uint8List.fromList(buffer.asUint8List());
  }
}
