import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../constants/api_constants.dart';
import '../constants/app_colors.dart';
import '../services/auth_service.dart';

class ChatVideoThumbnail extends StatefulWidget {
  const ChatVideoThumbnail({
    super.key,
    required this.fileUrl,
    this.mimeType,
    this.fallback,
  });

  final String? fileUrl;
  final String? mimeType;
  final Widget? fallback;

  @override
  State<ChatVideoThumbnail> createState() => _ChatVideoThumbnailState();
}

class _ChatVideoThumbnailState extends State<ChatVideoThumbnail> {
  VideoPlayerController? _controller;
  late final Future<void> _initializeFuture;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _initialize();
  }

  Future<void> _initialize() async {
    final fileUrl = widget.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      throw StateError('Missing video URL');
    }

    final resolvedUrl = ApiConstants.resolveFileUrl(fileUrl);
    final authToken = AuthService().accessToken;
    final headers = ApiConstants.requiresAuthHeaderForFile(fileUrl) &&
            authToken != null &&
            authToken.isNotEmpty
        ? <String, String>{'Authorization': 'Bearer $authToken'}
        : const <String, String>{};

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(resolvedUrl),
      httpHeaders: headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    await controller.initialize();
    await controller.setVolume(0);

    final seekPosition = _previewFramePosition(controller.value.duration);
    if (seekPosition > Duration.zero) {
      await controller.seekTo(seekPosition);
    }
    await controller.pause();
    if (mounted) setState(() {});
  }

  Duration _previewFramePosition(Duration duration) {
    if (duration <= const Duration(milliseconds: 900)) {
      return Duration.zero;
    }
    final targetMs =
        math.min(700, math.max(250, duration.inMilliseconds ~/ 12));
    return Duration(milliseconds: targetMs);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError ||
            controller == null ||
            !controller.value.isInitialized) {
          return widget.fallback ?? const _DefaultVideoThumbnailFallback();
        }

        return ColoredBox(
          key: const ValueKey('chat-video-thumbnail'),
          color: Colors.black,
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final size = value.size;
              if (size.width <= 0 || size.height <= 0) {
                return widget.fallback ??
                    const _DefaultVideoThumbnailFallback();
              }
              return ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DefaultVideoThumbnailFallback extends StatelessWidget {
  const _DefaultVideoThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      key: ValueKey('chat-video-thumbnail-fallback'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F1FF), Color(0xFFE9FFFA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_filter_outlined,
          color: AppColors.accent,
          size: 42,
        ),
      ),
    );
  }
}
