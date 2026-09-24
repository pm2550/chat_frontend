import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/api_constants.dart';
import '../services/auth_service.dart';

typedef AuthenticatedImageLoader = Future<Uint8List> Function(String fileUrl);

/// 加载本站受保护图片（聊天附件、AI 画图、贴纸图）的图片组件。
///
/// 这些地址需要 `Authorization` 头，`Image.network` 带不上，会直接 401/403。
/// 本站地址统一通过 [AuthService.authenticatedRequest] 取字节再用内存图渲染；
/// 外站地址仍交给 `Image.network`（避免 Web 端跨域 fetch 被 CORS 拦下）。
/// 同一用户同一地址的请求会被复用，列表重建不会反复下载。
class AuthenticatedImage extends StatefulWidget {
  const AuthenticatedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.loader,
    this.authService,
    this.placeholder,
    this.errorBuilder,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// 自定义取图方法（测试或已有加载器时注入）；为空时本站地址走带鉴权的请求。
  final AuthenticatedImageLoader? loader;

  /// 为空时使用全局 [AuthService]。
  final AuthService? authService;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorBuilder;

  /// 取到字节之后、渲染之前的处理：端到端加密附件在这里解密（main 里由 EncryptionService 装上）。
  static Future<Uint8List> Function(String url, Uint8List bytes)?
      bytesTransformer;

  /// 本站文件取到的字节交给 [bytesTransformer]（没装就原样返回）。
  static Future<Uint8List> transformFetchedBytes(String url, Uint8List bytes) {
    final transform = bytesTransformer;
    return transform == null ? Future.value(bytes) : transform(url, bytes);
  }

  static const int _maxCachedImages = 96;
  static final Map<String, Future<Uint8List>> _cache = {};

  @visibleForTesting
  static void clearCacheForTesting() => _cache.clear();

  /// 是否需要带登录态去取：指向本站后端的地址都走鉴权请求。
  static bool needsAuthenticatedFetch(String url) =>
      url.isNotEmpty && ApiConstants.requiresAuthHeaderForFile(url);

  /// 默认取图：带上当前登录 token 请求本站地址。
  static Future<Uint8List> fetchWithAuth(
    String url, {
    AuthService? authService,
  }) async {
    final response = await (authService ?? AuthService()).authenticatedRequest(
      'GET',
      ApiConstants.resolveFileUrl(url),
      timeout: const Duration(seconds: 60),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthenticatedImageException(response.statusCode);
    }
    return transformFetchedBytes(url, response.bodyBytes);
  }

  static bool looksLikeSvg(String url, Uint8List bytes) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.svg')) return true;
    final head = utf8
        .decode(
          bytes.length > 256 ? bytes.sublist(0, 256) : bytes,
          allowMalformed: true,
        )
        .trimLeft()
        .toLowerCase();
    return head.startsWith('<svg') ||
        (head.startsWith('<?xml') && head.contains('<svg'));
  }

  @override
  State<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends State<AuthenticatedImage> {
  Future<Uint8List>? _future;

  bool get _usesLoader =>
      widget.loader != null ||
      AuthenticatedImage.needsAuthenticatedFetch(widget.url);

  @override
  void initState() {
    super.initState();
    _future = _usesLoader ? _load() : null;
  }

  @override
  void didUpdateWidget(covariant AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.loader != widget.loader ||
        oldWidget.authService != widget.authService) {
      _future = _usesLoader ? _load() : null;
    }
  }

  Future<Uint8List> _load() {
    final loader = widget.loader;
    final auth = widget.authService ?? AuthService();
    final owner = loader == null
        ? 'auth:${identityHashCode(auth)}:${auth.currentUser?.id ?? auth.accessToken ?? 'anonymous'}'
        : 'loader:${identityHashCode(loader)}';
    final cacheKey = '$owner|${widget.url}';
    final cached = AuthenticatedImage._cache[cacheKey];
    if (cached != null) return cached;

    late final Future<Uint8List> operation;
    operation = (loader != null
            ? loader(widget.url)
            : AuthenticatedImage.fetchWithAuth(widget.url, authService: auth))
        .catchError((Object error) {
      // 失败的请求不留在缓存里，下次重建还能重试。
      if (identical(AuthenticatedImage._cache[cacheKey], operation)) {
        AuthenticatedImage._cache.remove(cacheKey);
      }
      throw error;
    });
    AuthenticatedImage._cache[cacheKey] = operation;
    while (AuthenticatedImage._cache.length >
        AuthenticatedImage._maxCachedImages) {
      AuthenticatedImage._cache.remove(AuthenticatedImage._cache.keys.first);
    }
    return operation;
  }

  Widget _error(BuildContext context) =>
      widget.errorBuilder?.call(context) ??
      const Center(child: Icon(Icons.broken_image_outlined));

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return Image.network(
        ApiConstants.resolveFileUrl(widget.url),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, _, __) => _error(context),
      );
    }
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          if (AuthenticatedImage.looksLikeSvg(widget.url, bytes)) {
            return SvgPicture.memory(
              bytes,
              fit: widget.fit,
              width: widget.width,
              height: widget.height,
              placeholderBuilder: widget.placeholder,
            );
          }
          return Image.memory(
            bytes,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            gaplessPlayback: true,
            errorBuilder: (context, _, __) => _error(context),
          );
        }
        if (snapshot.hasError) {
          return _error(context);
        }
        return widget.placeholder?.call(context) ??
            SizedBox(width: widget.width, height: widget.height);
      },
    );
  }
}

class AuthenticatedImageException implements Exception {
  const AuthenticatedImageException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'Image load failed: $statusCode';
}
