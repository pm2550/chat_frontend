import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../models/message.dart';
import '../services/auth_service.dart';

typedef ImageBytesLoader = Future<Uint8List> Function(String fileUrl);

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showAvatar;
  final Future<void> Function(Message message)? onOpenAttachment;
  final ImageBytesLoader? imageLoader;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showAvatar = false,
    this.onOpenAttachment,
    this.imageLoader,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleDecoration = BoxDecoration(
      gradient: isMe ? AppColors.messageGradient : null,
      color: isMe ? null : AppColors.messageReceived,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
        bottomLeft: Radius.circular(isMe ? 18 : 6),
        bottomRight: Radius.circular(isMe ? 6 : 18),
      ),
      border: isMe ? null : Border.all(color: AppColors.borderLight),
      boxShadow: [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: isMe ? 0.12 : 0.07),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showAvatar) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              backgroundImage: message.senderAvatar != null
                  ? NetworkImage(
                      ApiConstants.resolveFileUrl(message.senderAvatar!))
                  : null,
              child: message.senderAvatar == null
                  ? Text(
                      message.senderName.isNotEmpty
                          ? message.senderName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 10),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ] else if (!isMe && !showAvatar) ...[
            const SizedBox(width: 40),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: bubbleDecoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 发送者名称（群聊中显示）
                  if (!isMe && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          color: message.isAnonymous
                              ? AppColors.accent
                              : AppColors.secondaryDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                  // 消息内容
                  _buildMessageContent(),

                  // 消息状态和时间
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(message.timestamp),
                          style: TextStyle(
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.7)
                                : AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            _getStatusIcon(message.status),
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent() {
    if (message.isRemoved) {
      return Text(
        message.isRecalled ? '[消息已撤回]' : '[消息已删除]',
        style: TextStyle(
          color: isMe ? Colors.white70 : AppColors.textSecondary,
          fontSize: 15,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (message.isImageMessage) {
      return _buildImageAttachment();
    }
    if (message.isVoiceMessage) {
      return _buildMediaAttachment(
        icon: Icons.mic,
        label: message.resolvedFileLabel,
      );
    }
    if (message.isVideoMessage) {
      return _buildMediaAttachment(
        icon: Icons.videocam,
        label: message.resolvedFileLabel,
      );
    }
    if (message.isLocationMessage) {
      return _buildLocationMessage();
    }
    if (message.isFileMessage) {
      return _buildFileAttachment();
    }
    return Text(
      message.content,
      style: TextStyle(
        color: isMe ? Colors.white : AppColors.textPrimary,
        fontSize: 16,
        height: 1.32,
      ),
    );
  }

  Widget _buildImageAttachment() {
    final fileUrl = message.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      return _buildFileAttachment();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FutureBuilder<Uint8List>(
            future: _loadImageBytes(fileUrl),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Image.memory(
                  snapshot.data!,
                  width: 220,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildFileAttachment(),
                );
              }
              if (snapshot.hasError) {
                return _buildFileAttachment();
              }
              return Container(
                width: 220,
                height: 160,
                alignment: Alignment.center,
                color: isMe
                    ? Colors.white.withValues(alpha: 0.12)
                    : AppColors.background,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isMe ? Colors.white : AppColors.primary,
                  ),
                ),
              );
            },
          ),
        ),
        if (message.fileName != null && message.fileName!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            message.fileName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isMe ? Colors.white70 : AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Future<Uint8List> _loadImageBytes(String fileUrl) async {
    if (imageLoader != null) {
      return imageLoader!(fileUrl);
    }

    final resolvedUrl = ApiConstants.resolveFileUrl(fileUrl);
    final response = ApiConstants.requiresAuthHeaderForFile(fileUrl)
        ? await AuthService().authenticatedRequest('GET', resolvedUrl)
        : await http
            .get(Uri.parse(resolvedUrl))
            .timeout(ApiConstants.requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Image load failed: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Widget _buildFileAttachment() {
    final foreground = isMe ? Colors.white : AppColors.textPrimary;
    final secondary = isMe ? Colors.white70 : AppColors.textSecondary;

    return InkWell(
      onTap: onOpenAttachment == null ? null : () => onOpenAttachment!(message),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.white.withValues(alpha: 0.13)
                : AppColors.pixelBlue,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.20)
                  : AppColors.borderLight,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AttachmentGlyph(
                icon: message.isImageMessage
                    ? Icons.image
                    : Icons.insert_drive_file,
                isMe: isMe,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.resolvedFileLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (message.fileSize != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatFileSize(message.fileSize!),
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.download,
                color: secondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaAttachment({
    required IconData icon,
    required String label,
  }) {
    final foreground = isMe ? Colors.white : AppColors.textPrimary;
    final secondary = isMe ? Colors.white70 : AppColors.textSecondary;

    return InkWell(
      onTap: message.fileUrl == null || onOpenAttachment == null
          ? null
          : () => onOpenAttachment!(message),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.white.withValues(alpha: 0.13)
                : AppColors.pixelMint,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.20)
                  : AppColors.borderLight,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AttachmentGlyph(icon: icon, isMe: isMe),
              const SizedBox(width: 10),
              if (message.isVoiceMessage) ...[
                _WaveformBars(color: foreground),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (message.fileSize != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatFileSize(message.fileSize!),
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              if (message.fileUrl != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.download, color: secondary, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationMessage() {
    final foreground = isMe ? Colors.white : AppColors.textPrimary;
    final secondary = isMe ? Colors.white70 : AppColors.textSecondary;
    final label = message.content.isNotEmpty ? message.content : '[位置]';
    return InkWell(
      onTap: null,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.white.withValues(alpha: 0.13)
                : AppColors.pixelCoral,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.20)
                  : AppColors.borderLight,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniMapGlyph(isMe: isMe),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '位置消息',
                      style: TextStyle(color: secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  IconData _getStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icons.access_time;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.delivered:
        return Icons.done_all;
      case MessageStatus.read:
        return Icons.done_all;
      case MessageStatus.failed:
        return Icons.error_outline;
    }
  }

  String _formatFileSize(int size) {
    if (size < 1024) {
      return '$size B';
    }
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _AttachmentGlyph extends StatelessWidget {
  const _AttachmentGlyph({required this.icon, required this.isMe});

  final IconData icon;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isMe ? Colors.white.withValues(alpha: 0.18) : Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: isMe ? Colors.white : AppColors.primary,
        size: 20,
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const heights = [10.0, 18.0, 14.0, 24.0, 12.0, 20.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final height in heights)
          Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

class _MiniMapGlyph extends StatelessWidget {
  const _MiniMapGlyph({required this.isMe});

  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final pinColor = isMe ? Colors.white : AppColors.accent;
    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color:
                    isMe ? Colors.white.withValues(alpha: 0.16) : Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomPaint(painter: _MiniMapPainter(isMe: isMe)),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Icon(Icons.location_on, color: pinColor, size: 22),
          ),
        ],
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({required this.isMe});

  final bool isMe;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isMe ? Colors.white : AppColors.primary)
          .withValues(alpha: isMe ? 0.16 : 0.12)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final offset = size.width * i / 4;
      canvas.drawLine(Offset(offset, 0), Offset(offset, size.height), paint);
      canvas.drawLine(Offset(0, offset), Offset(size.width, offset), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return oldDelegate.isMe != isMe;
  }
}
