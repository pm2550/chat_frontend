import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/app_colors.dart';
import '../constants/api_constants.dart';
import '../design/design.dart';
import '../models/message.dart';
import '../models/poll.dart';
import '../services/auth_service.dart';

typedef ImageBytesLoader = Future<Uint8List> Function(String fileUrl);
typedef LinkPreviewLoader = Future<LinkPreview?> Function(String url);

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showAvatar;
  final Future<void> Function(Message message)? onOpenAttachment;
  final Future<void> Function(Message message)? onRetrySend;
  final VoidCallback? onOpenReply;
  final ValueChanged<String>? onMentionTap;
  final VoidCallback? onAvatarMention;
  final String? currentUserId;
  final Future<void> Function(Message message, String emoji, bool selected)?
      onToggleReaction;
  final Future<PollInfo> Function(int pollId)? pollLoader;
  final Future<PollInfo> Function(int pollId, List<int> optionIndexes)?
      onVotePoll;
  final int pollRefreshEpoch;
  final ImageBytesLoader? imageLoader;
  final LinkPreviewLoader? linkPreviewLoader;
  final String bubbleStylePreset;
  final String senderAvatarFramePreset;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showAvatar = false,
    this.onOpenAttachment,
    this.onRetrySend,
    this.onOpenReply,
    this.onMentionTap,
    this.onAvatarMention,
    this.currentUserId,
    this.onToggleReaction,
    this.pollLoader,
    this.onVotePoll,
    this.pollRefreshEpoch = 0,
    this.imageLoader,
    this.linkPreviewLoader,
    this.bubbleStylePreset = 'default_gradient',
    this.senderAvatarFramePreset = 'none',
  });

  @override
  Widget build(BuildContext context) {
    final anonymousColor =
        _parseColor(message.anonymousAvatar) ?? const Color(0xFF7C3AED);
    final bubbleVisual = PMBubbleStyles.resolve(
      preset: bubbleStylePreset,
      isMe: isMe,
      isAnonymous: message.isAnonymous,
      anonymousColor: anonymousColor,
    );
    final showSenderLabel =
        message.isAnonymous || message.isBotMessage || (!isMe && showAvatar);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showAvatar) ...[
            _buildAvatar(anonymousColor),
            const SizedBox(width: 8),
          ] else if (!isMe && !showAvatar) ...[
            const SizedBox(width: 40),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (showSenderLabel)
                  Padding(
                    padding: EdgeInsets.only(
                      left: isMe ? 0 : 2,
                      right: isMe ? 2 : 0,
                      bottom: 4,
                    ),
                    child: _buildSenderLabel(anonymousColor),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: bubbleVisual.decoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyToMessage != null ||
                          message.replyToId != null ||
                          message.replyToMessageId != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: _buildQuoteBlock(),
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
                                color: bubbleVisual.secondaryTextColor,
                                fontSize: 12,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                _getStatusIcon(message.status),
                                size: 16,
                                color: _statusIconColor(message.status),
                              ),
                            ],
                            if (message.isAnonymous) ...[
                              const SizedBox(width: 4),
                              Text(
                                '🎭',
                                style: TextStyle(
                                  color: anonymousColor,
                                  fontSize: 12,
                                  height: 1,
                                ),
                              ),
                            ],
                            if (message.status == MessageStatus.failed &&
                                onRetrySend != null) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => onRetrySend!(message),
                                borderRadius: BorderRadius.circular(999),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    '重发',
                                    style: TextStyle(
                                      color:
                                          isMe ? Colors.white : AppColors.error,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (message.reactions.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _buildReactionChips(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isMe && showAvatar) ...[
            const SizedBox(width: 8),
            _buildAvatar(anonymousColor),
          ] else if (isMe && !showAvatar) ...[
            const SizedBox(width: 40),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(Color anonymousColor) {
    if (!message.isAnonymous) {
      return PMUserAvatar.raw(
        imageUrl: _senderAvatarUrl == null
            ? null
            : ApiConstants.resolveFileUrl(_senderAvatarUrl!),
        fallbackText: _senderDisplayName,
        size: 24,
        framePreset: senderAvatarFramePreset,
        onSecondaryTap: onAvatarMention,
        onLongPress: onAvatarMention,
      );
    }

    final avatar = AnonymousAvatar(
      name: _anonymousDisplayName,
      color: anonymousColor,
      size: 24,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: anonymousColor.withValues(alpha: 0.45)),
            ),
            child: Center(
              child: Text(
                '🎭',
                style: TextStyle(
                  color: anonymousColor,
                  fontSize: 8,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSenderLabel(Color anonymousColor) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _senderDisplayName,
          style: TextStyle(
            color: message.isAnonymous
                ? anonymousColor
                : message.isBotMessage
                    ? AppColors.secondaryDark
                    : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (message.isBotMessage)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'BOT',
              style: TextStyle(
                color: AppColors.secondaryDark,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        if (message.isAnonymous)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: anonymousColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🎭',
                  style: TextStyle(
                    color: anonymousColor,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  '匿名',
                  style: TextStyle(
                    color: anonymousColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String get _anonymousDisplayName {
    final explicit = message.anonymousName?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final sender = message.senderName.trim();
    return sender.isEmpty ? '匿名用户' : sender;
  }

  String get _senderDisplayName {
    if (message.isAnonymous) return _anonymousDisplayName;
    if (message.isBotMessage) return message.effectiveBotName;
    return message.senderName;
  }

  String? get _senderAvatarUrl {
    if (message.isBotMessage && message.botAvatar?.trim().isNotEmpty == true) {
      return message.botAvatar;
    }
    return message.senderAvatar;
  }

  Widget _buildQuoteBlock() {
    final quoted = message.replyToMessage;
    final removed = quoted == null || quoted.isRemoved;
    final title = removed ? '原消息已删除' : quoted.senderName;
    final excerpt = removed ? '原消息已删除' : _quoteExcerpt(quoted);
    final foreground = _textColor;
    final muted = _secondaryTextColor;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: PMCard(
        elevated: false,
        interactive: onOpenReply != null && !removed,
        onTap: removed ? null : onOpenReply,
        radius: PMRadius.s,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        background: isMe
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.cloud.withValues(alpha: removed ? 0.72 : 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color:
                    removed ? muted.withValues(alpha: 0.48) : AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: removed ? muted : foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.25,
                      fontStyle: removed ? FontStyle.italic : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusIconColor(MessageStatus status) {
    if (status == MessageStatus.read) {
      return const Color(0xFF0FAE96);
    }
    if (status == MessageStatus.failed) {
      return AppColors.error;
    }
    return _secondaryTextColor;
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
    if (message.isStickerMessage) {
      return _buildStickerMessage();
    }
    if (message.isPollMessage) {
      return _buildPollMessage();
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
    final text = _buildMentionAwareText();
    final content = message.displayContent;
    final embeddedUrl = message.linkPreview?.url.isNotEmpty == true
        ? message.linkPreview!.url
        : _firstUrl(content);
    if (embeddedUrl == null && message.linkPreview == null) {
      return text;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        text,
        const SizedBox(height: 8),
        _buildLinkPreview(embeddedUrl, message.linkPreview),
      ],
    );
  }

  Widget _buildMentionAwareText() {
    final baseStyle = TextStyle(
      color: _textColor,
      fontSize: 16,
      height: 1.32,
    );
    final content = message.displayContent;
    if (!content.contains('@')) {
      return Text(content, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    final matcher = RegExp(r'@([\p{L}\p{N}_\-.]+)', unicode: true);
    var cursor = 0;
    for (final match in matcher.allMatches(content)) {
      final escaped = match.start > 0 && content[match.start - 1] == r'\';
      if (escaped) {
        continue;
      }
      if (match.start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, match.start)));
      }
      final label = match.group(1) ?? '';
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: onMentionTap == null ? null : () => onMentionTap!(label),
          child: Text(
            '@$label',
            style: baseStyle.copyWith(
              color: isMe ? Colors.white : AppColors.primary,
              fontWeight: FontWeight.w900,
              decoration:
                  onMentionTap == null ? null : TextDecoration.underline,
              decorationColor: isMe ? Colors.white : AppColors.primary,
            ),
          ),
        ),
      ));
      cursor = match.end;
    }
    if (cursor == 0) {
      return Text(content, style: baseStyle);
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    }
    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }

  Widget _buildImageAttachment() {
    final fileUrl = message.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      return _buildFileAttachment();
    }
    return _buildAttachmentCard(
      type: AttachmentType.image,
      forcePreview: true,
      preview: FutureBuilder<Uint8List>(
        future: _loadImageBytes(fileUrl),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _buildAttachmentFallback(Icons.broken_image_outlined),
                ),
                if (onOpenAttachment != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.46),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(
                        Icons.zoom_out_map,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            );
          }
          if (snapshot.hasError) {
            return _buildAttachmentFallback(Icons.broken_image_outlined);
          }
          return Center(
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
    );
  }

  Color get _anonymousColor =>
      _parseColor(message.anonymousAvatar) ?? const Color(0xFF7C3AED);

  PMBubbleStyleVisual get _resolvedBubbleVisual => PMBubbleStyles.resolve(
        preset: bubbleStylePreset,
        isMe: isMe,
        isAnonymous: message.isAnonymous,
        anonymousColor: _anonymousColor,
      );

  Color get _textColor => _resolvedBubbleVisual.textColor;

  Color get _secondaryTextColor => _resolvedBubbleVisual.secondaryTextColor;

  Widget _buildStickerMessage() {
    final fileUrl = message.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      return SizedBox(
        width: 96,
        height: 96,
        child: Center(
          child: Text(
            message.fileName?.isNotEmpty == true ? message.fileName! : '😀',
            style: const TextStyle(fontSize: 54),
          ),
        ),
      );
    }
    return SizedBox(
      width: 112,
      height: 112,
      child: FutureBuilder<Uint8List>(
        future: _loadImageBytes(fileUrl),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  _buildAttachmentFallback(Icons.broken_image_outlined),
            );
          }
          if (snapshot.hasError) {
            return _buildAttachmentFallback(Icons.broken_image_outlined);
          }
          return Center(
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
    );
  }

  Widget _buildPollMessage() {
    final title = message.content.replaceFirst(RegExp(r'^\[投票\]\s*'), '');
    if (message.pollId != null && pollLoader != null) {
      return _PollMessageCard(
        pollId: message.pollId!,
        fallbackTitle: title.isEmpty ? '未命名投票' : title,
        isMe: isMe,
        loader: pollLoader!,
        onVote: onVotePoll,
        refreshEpoch: pollRefreshEpoch,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: PMCard(
        elevated: false,
        background: isMe
            ? Colors.white.withValues(alpha: 0.12)
            : AppColors.pixelBlue.withValues(alpha: 0.6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '投票',
              style: TextStyle(
                color: isMe ? Colors.white : AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title.isEmpty ? '未命名投票' : title,
              style: TextStyle(
                color: isMe ? Colors.white : AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final reaction in message.reactions)
          _ReactionChip(
            emoji: reaction.emoji,
            count: reaction.count,
            selected: reaction.currentUserReacted ||
                reaction.userIds.contains(currentUserId),
            onTap: onToggleReaction == null
                ? null
                : () => onToggleReaction!(
                      message,
                      reaction.emoji,
                      reaction.currentUserReacted ||
                          reaction.userIds.contains(currentUserId),
                    ),
          ),
      ],
    );
  }

  Widget _buildAttachmentCard({
    required AttachmentType type,
    Widget? preview,
    bool forcePreview = false,
  }) {
    final label = message.fileName?.isNotEmpty == true
        ? message.isImageMessage
            ? message.fileName!
            : message.resolvedFileLabel
        : message.resolvedFileLabel;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: PMAttachmentCard(
        type: type,
        name: label,
        sizeText: message.fileSize == null
            ? null
            : _formatFileSize(message.fileSize!),
        failed: message.status == MessageStatus.failed,
        forcePreview: forcePreview,
        preview: preview,
        onTap: message.fileUrl == null || onOpenAttachment == null
            ? null
            : () => onOpenAttachment!(message),
        onRetry: onRetrySend == null ? null : () => onRetrySend!(message),
      ),
    );
  }

  Widget _buildAttachmentFallback(IconData icon) {
    return ColoredBox(
      color: isMe ? Colors.white.withValues(alpha: 0.12) : AppColors.background,
      child: Center(
        child: Icon(
          icon,
          color: isMe ? Colors.white70 : AppColors.textSecondary,
          size: 42,
        ),
      ),
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

  Widget _buildLinkPreview(String? url, LinkPreview? preview) {
    if (preview != null) {
      return _buildLinkPreviewCard(preview);
    }
    if (url == null || url.isEmpty || linkPreviewLoader == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<LinkPreview?>(
      future: linkPreviewLoader!(url),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const SizedBox.shrink();
        }
        return _buildLinkPreviewCard(data);
      },
    );
  }

  Widget _buildLinkPreviewCard(LinkPreview preview) {
    final resolvedUrl = preview.url.isNotEmpty ? preview.url : message.content;
    final host = _hostFromUrl(resolvedUrl);
    final title = preview.title?.isNotEmpty == true
        ? preview.title!
        : host ?? resolvedUrl;
    final subtitle = preview.description;
    final siteName = preview.siteName?.isNotEmpty == true
        ? preview.siteName!
        : host ?? resolvedUrl;
    final foreground = isMe ? Colors.white : AppColors.textPrimary;
    final muted =
        isMe ? Colors.white.withValues(alpha: 0.76) : AppColors.textSecondary;
    final cardBackground =
        isMe ? Colors.white.withValues(alpha: 0.15) : Colors.white;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        decoration: BoxDecoration(
          color: cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isMe
                ? Colors.white.withValues(alpha: 0.20)
                : AppColors.borderLight,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLinkPreviewMedia(preview.imageUrl),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        height: 1.22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      siteName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkPreviewMedia(String? imageUrl) {
    final fallback = Container(
      width: 72,
      height: 92,
      color: isMe
          ? Colors.white.withValues(alpha: 0.12)
          : AppColors.pixelMint.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: PMSymbolIcon(
        PMSymbol.link,
        color: isMe ? Colors.white70 : AppColors.secondaryDark,
        size: 24,
      ),
    );
    if (imageUrl == null || imageUrl.isEmpty) {
      return fallback;
    }
    return SizedBox(
      width: 72,
      height: 92,
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _buildFileAttachment() {
    return _buildAttachmentCard(type: AttachmentType.file);
  }

  Widget _buildMediaAttachment({
    required IconData icon,
    required String label,
  }) {
    final type = message.isVoiceMessage
        ? AttachmentType.voice
        : message.isVideoMessage
            ? AttachmentType.video
            : AttachmentType.file;
    return _buildAttachmentCard(
      type: type,
      forcePreview: message.isVoiceMessage || message.isVideoMessage,
      preview: message.isVoiceMessage
          ? const ColoredBox(
              color: AppColors.pixelMint,
              child: Center(
                child: _WaveformBars(color: AppColors.secondaryDark),
              ),
            )
          : message.isVideoMessage
              ? _buildAttachmentFallback(Icons.movie_outlined)
              : null,
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

  Color? _parseColor(String? value) {
    if (value == null || !value.startsWith('#')) {
      return null;
    }
    final hex = value.substring(1);
    if (hex.length != 6 && hex.length != 8) {
      return null;
    }
    final parsed = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  String? _firstUrl(String value) {
    final match = RegExp(
      r'https?://[^\s<>()\[\]{}"]+',
      caseSensitive: false,
    ).firstMatch(value);
    final url = match?.group(0)?.trim();
    if (url == null || url.isEmpty) {
      return null;
    }
    return url.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
  }

  String? _hostFromUrl(String value) {
    try {
      return Uri.parse(value).host;
    } catch (_) {
      return null;
    }
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.selected,
    this.onTap,
  });

  final String emoji;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            '$emoji $count',
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _PollMessageCard extends StatefulWidget {
  const _PollMessageCard({
    required this.pollId,
    required this.fallbackTitle,
    required this.isMe,
    required this.loader,
    required this.refreshEpoch,
    this.onVote,
  });

  final int pollId;
  final String fallbackTitle;
  final bool isMe;
  final Future<PollInfo> Function(int pollId) loader;
  final int refreshEpoch;
  final Future<PollInfo> Function(int pollId, List<int> optionIndexes)? onVote;

  @override
  State<_PollMessageCard> createState() => _PollMessageCardState();
}

class _PollMessageCardState extends State<_PollMessageCard> {
  late Future<PollInfo> _future = widget.loader(widget.pollId);
  PollInfo? _poll;
  final Set<int> _selected = {};
  bool _submitting = false;

  @override
  void didUpdateWidget(covariant _PollMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pollId != widget.pollId ||
        oldWidget.refreshEpoch != widget.refreshEpoch) {
      _future = widget.loader(widget.pollId);
      _poll = null;
      _selected.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PollInfo>(
      future: _future,
      builder: (context, snapshot) {
        final poll = _poll ?? snapshot.data;
        if (poll == null) {
          return _shell(
            child: SizedBox(
              width: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _label('投票'),
                  const SizedBox(height: 8),
                  Text(
                    widget.fallbackTitle,
                    style: _titleStyle(),
                  ),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 3),
                ],
              ),
            ),
          );
        }

        return _shell(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _label(poll.isExpired ? '投票 · 已截止' : '投票'),
                    if (poll.anonymous) ...[
                      const SizedBox(width: 8),
                      _miniBadge('匿名'),
                    ],
                    if (poll.multiSelect) ...[
                      const SizedBox(width: 8),
                      _miniBadge('多选'),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(poll.question, style: _titleStyle()),
                const SizedBox(height: 12),
                for (final option in poll.options)
                  _PollOptionRow(
                    option: option,
                    totalVotes: poll.totalVotes,
                    selected: _selected.contains(option.index),
                    disabled: poll.isExpired || _submitting,
                    onTap: () => _toggleOption(poll, option.index),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${poll.totalVotes} 人参与'
                        '${poll.expiresAt == null ? '' : ' · 截止 ${_shortDate(poll.expiresAt!)}'}',
                        style: TextStyle(
                          color: widget.isMe
                              ? Colors.white.withValues(alpha: 0.78)
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showDetails(context, poll),
                      child: const Text('详情'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: _selected.isEmpty ||
                              poll.isExpired ||
                              _submitting ||
                              widget.onVote == null
                          ? null
                          : () => _submitVote(poll),
                      child: _submitting
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('投票'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shell({required Widget child}) {
    return PMCard(
      elevated: false,
      background: widget.isMe
          ? Colors.white.withValues(alpha: 0.12)
          : AppColors.pixelBlue.withValues(alpha: 0.6),
      child: child,
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        color: widget.isMe ? Colors.white : AppColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _miniBadge(String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  TextStyle _titleStyle() {
    return TextStyle(
      color: widget.isMe ? Colors.white : AppColors.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    );
  }

  void _toggleOption(PollInfo poll, int index) {
    setState(() {
      if (poll.multiSelect) {
        if (!_selected.remove(index)) {
          _selected.add(index);
        }
      } else {
        _selected
          ..clear()
          ..add(index);
      }
    });
  }

  Future<void> _submitVote(PollInfo poll) async {
    final vote = widget.onVote;
    if (vote == null) return;
    setState(() => _submitting = true);
    try {
      final next = await vote(poll.id, _selected.toList()..sort());
      if (mounted) {
        setState(() {
          _poll = next;
          _future = Future.value(next);
          _selected.clear();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showDetails(BuildContext context, PollInfo poll) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                poll.question,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              for (final option in poll.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    poll.anonymous
                        ? '${option.text}: ${option.votes} 票'
                        : '${option.text}: ${option.voterIds.isEmpty ? '暂无' : option.voterIds.map((id) => '#$id').join(', ')}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortDate(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.option,
    required this.totalVotes,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final PollOption option;
  final int totalVotes;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = totalVotes <= 0 ? 0.0 : option.votes / totalVotes;
    final percent = (ratio * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: disabled ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderLight,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      option.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${option.votes} · $percent%',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0).toDouble(),
                  minHeight: 6,
                  backgroundColor: AppColors.borderLight,
                  color: selected ? AppColors.primary : AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
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

String _quoteExcerpt(Message message, {int maxLength = 80}) {
  if (message.isRemoved) {
    return '原消息已删除';
  }
  final raw = message.type == MessageType.text
      ? message.displayContent
      : message.resolvedFileLabel;
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) {
    return message.type.description;
  }
  if (text.length <= maxLength) {
    return text;
  }
  return '${text.substring(0, maxLength)}...';
}
