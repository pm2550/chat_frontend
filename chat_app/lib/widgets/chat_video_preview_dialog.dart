import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../constants/api_constants.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/chat_data_service.dart';
import '../services/video_object_url.dart';

class ChatVideoPreviewDialog extends StatelessWidget {
  const ChatVideoPreviewDialog({
    super.key,
    required this.message,
    required this.fileFuture,
    required this.onDownload,
    this.onForward,
  });

  final Message message;
  final Future<DownloadedChatFile> fileFuture;
  final Future<void> Function(DownloadedChatFile file) onDownload;
  final Future<void> Function(DownloadedChatFile file)? onForward;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: FutureBuilder<DownloadedChatFile>(
          future: fileFuture,
          builder: (context, snapshot) {
            final file = snapshot.data;
            return Stack(
              children: [
                Positioned.fill(child: _buildBody(snapshot)),
                Positioned(
                  left: 16,
                  top: 12,
                  right: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          file?.name ??
                              message.fileName ??
                              message.resolvedFileLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _VideoPreviewButton(
                        tooltip: '保存视频',
                        icon: Icons.download,
                        onPressed: file == null
                            ? null
                            : () => unawaited(onDownload(file)),
                      ),
                      if (onForward != null) ...[
                        const SizedBox(width: 8),
                        _VideoPreviewButton(
                          tooltip: '转发视频',
                          icon: Icons.forward,
                          onPressed: file == null
                              ? null
                              : () => unawaited(onForward!(file)),
                        ),
                      ],
                      const SizedBox(width: 8),
                      _VideoPreviewButton(
                        tooltip: '关闭',
                        icon: Icons.close,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(AsyncSnapshot<DownloadedChatFile> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (snapshot.hasError || !snapshot.hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.movie_outlined,
                color: Colors.white70,
                size: 52,
              ),
              const SizedBox(height: 14),
              const Text(
                '视频加载失败',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.error?.toString() ?? '无法读取视频文件',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return _DownloadedVideoPlayer(
      message: message,
      file: snapshot.data!,
    );
  }
}

class _DownloadedVideoPlayer extends StatefulWidget {
  const _DownloadedVideoPlayer({
    required this.message,
    required this.file,
  });

  final Message message;
  final DownloadedChatFile file;

  @override
  State<_DownloadedVideoPlayer> createState() => _DownloadedVideoPlayerState();
}

class _DownloadedVideoPlayerState extends State<_DownloadedVideoPlayer> {
  VideoPlayerController? _controller;
  late final Future<void> _initializeFuture;
  String? _objectUrl;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _initialize();
  }

  Future<void> _initialize() async {
    _objectUrl = await createVideoObjectUrl(
      bytes: widget.file.bytes,
      mimeType: widget.file.mimeType ?? widget.message.fileType,
    );

    final sourceUrl =
        _objectUrl ?? ApiConstants.resolveFileUrl(widget.message.fileUrl ?? '');
    final authToken = AuthService().accessToken;
    final headers = _objectUrl == null &&
            widget.message.fileUrl != null &&
            ApiConstants.requiresAuthHeaderForFile(widget.message.fileUrl!) &&
            authToken != null &&
            authToken.isNotEmpty
        ? <String, String>{'Authorization': 'Bearer $authToken'}
        : const <String, String>{};

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(sourceUrl),
      httpHeaders: headers,
    );
    _controller = controller;
    await controller.initialize();
    if (!mounted) return;
    setState(() {});
    unawaited(controller.play());
  }

  @override
  void dispose() {
    _controller?.dispose();
    revokeVideoObjectUrl(_objectUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (snapshot.hasError ||
            _controller == null ||
            !_controller!.value.isInitialized) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.movie_outlined,
                    color: Colors.white70,
                    size: 52,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '视频无法播放',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error?.toString() ?? '浏览器不支持此视频格式',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        }

        final controller = _controller!;
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final aspect = value.aspectRatio <= 0 ? 16 / 9 : value.aspectRatio;
            final duration = value.duration;
            final position = value.position;
            final progress = duration.inMilliseconds <= 0
                ? 0.0
                : (position.inMilliseconds / duration.inMilliseconds)
                    .clamp(0.0, 1.0);

            return Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: () => _togglePlayback(controller),
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
                if (!value.isPlaying)
                  _PlaybackOverlay(onTap: () => _togglePlayback(controller)),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: _VideoProgressBar(
                    progress: progress,
                    position: position,
                    duration: duration,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _togglePlayback(VideoPlayerController controller) {
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }
}

class _PlaybackOverlay extends StatelessWidget {
  const _PlaybackOverlay({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '播放视频',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: 42,
          ),
        ),
      ),
    );
  }
}

class _VideoProgressBar extends StatelessWidget {
  const _VideoProgressBar({
    required this.progress,
    required this.position,
    required this.duration,
  });

  final double progress;
  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${_formatDuration(position)} / ${_formatDuration(duration)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (value.inHours > 0) {
      return '${value.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _VideoPreviewButton extends StatelessWidget {
  const _VideoPreviewButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: Colors.white,
        disabledColor: Colors.white38,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.14),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.07),
        ),
      ),
    );
  }
}
