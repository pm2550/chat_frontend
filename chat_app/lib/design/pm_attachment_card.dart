import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'pm_card.dart';
import 'tokens.dart';

enum AttachmentType { image, video, voice, file, location }

class PMAttachmentCard extends StatelessWidget {
  const PMAttachmentCard({
    super.key,
    required this.type,
    this.thumbnail,
    this.preview,
    required this.name,
    this.sizeText,
    this.duration,
    this.progress,
    this.failed = false,
    this.forcePreview = false,
    this.onTap,
    this.onRetry,
  });

  final AttachmentType type;
  final String? thumbnail;
  final Widget? preview;
  final String name;
  final String? sizeText;
  final Duration? duration;
  final double? progress;
  final bool failed;
  final bool forcePreview;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = _accentForType(type);
    final previewType =
        type == AttachmentType.image || type == AttachmentType.video;
    final hasThumbnail = thumbnail != null && thumbnail!.isNotEmpty;
    final showPreview =
        previewType && (preview != null || hasThumbnail || forcePreview);

    return PMCard(
      padding: EdgeInsets.zero,
      interactive: true,
      elevated: false,
      background: failed ? AppColors.pixelCoral : AppColors.surface,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PMRadius.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPreview)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (preview != null)
                      preview!
                    else if (hasThumbnail)
                      Image.network(
                        thumbnail!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _IconPreview(type: type, color: accent),
                      )
                    else
                      _IconPreview(type: type, color: accent),
                    if (type == AttachmentType.video)
                      Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(PMRadius.pill),
                          ),
                          child:
                              const Icon(Icons.play_arrow, color: Colors.white),
                        ),
                      ),
                    if (duration != null)
                      Positioned(
                        right: PMSpacing.s,
                        bottom: PMSpacing.s,
                        child: _DurationPill(duration: duration!),
                      ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(PMSpacing.m),
                child: Row(
                  children: [
                    _IconTile(type: type, color: accent),
                    const SizedBox(width: PMSpacing.m),
                    Expanded(
                        child: _LabelBlock(name: name, subtitle: _subtitle)),
                    if (failed && onRetry != null)
                      IconButton(
                        tooltip: '重试',
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh, color: AppColors.error),
                      ),
                    if (!failed && type == AttachmentType.file)
                      const Icon(
                        Icons.download,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                  ],
                ),
              ),
            if (showPreview)
              Padding(
                padding: const EdgeInsets.all(PMSpacing.m),
                child: _LabelBlock(name: name, subtitle: _subtitle),
              ),
            if (progress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PMSpacing.m,
                  0,
                  PMSpacing.m,
                  PMSpacing.m,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(PMRadius.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: AppColors.borderLight,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      failed ? AppColors.error : accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? get _subtitle {
    final parts = [
      if (sizeText != null && sizeText!.isNotEmpty) sizeText,
      if (duration != null) _formatDuration(duration!),
      if (failed) '发送失败',
    ];
    return parts.whereType<String>().join(' · ');
  }
}

class _LabelBlock extends StatelessWidget {
  const _LabelBlock({required this.name, this.subtitle});

  final String name;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: PMSpacing.xs),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.type, required this.color});

  final AttachmentType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(PMRadius.m),
      ),
      child: Icon(_iconForType(type), color: color),
    );
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.type, required this.color});

  final AttachmentType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color.withValues(alpha: 0.1),
      child: Center(
        child: Icon(_iconForType(type), color: color, size: 42),
      ),
    );
  }
}

class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PMSpacing.s,
        vertical: PMSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(PMRadius.pill),
      ),
      child: Text(
        _formatDuration(duration),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _accentForType(AttachmentType type) {
  return switch (type) {
    AttachmentType.image => AppColors.secondaryDark,
    AttachmentType.video => AppColors.accent,
    AttachmentType.voice => AppColors.primary,
    AttachmentType.file => AppColors.primaryDark,
    AttachmentType.location => AppColors.warning,
  };
}

IconData _iconForType(AttachmentType type) {
  return switch (type) {
    AttachmentType.image => Icons.image_outlined,
    AttachmentType.video => Icons.movie_outlined,
    AttachmentType.voice => Icons.graphic_eq,
    AttachmentType.file => Icons.insert_drive_file,
    AttachmentType.location => Icons.location_on_outlined,
  };
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
