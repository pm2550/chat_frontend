import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/sticker.dart';
import '../services/auth_service.dart';
import 'authenticated_image.dart';

/// 贴纸面板里的一格。贴纸图在受保护的 /api/files/ 下，必须带登录态加载。
class StickerTile extends StatelessWidget {
  const StickerTile({
    super.key,
    required this.sticker,
    required this.onTap,
    this.loader,
    this.authService,
  });

  final StickerItem sticker;
  final VoidCallback onTap;
  final AuthenticatedImageLoader? loader;
  final AuthService? authService;

  @override
  Widget build(BuildContext context) {
    final url = sticker.url;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.pixelBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Center(
          child: url == null || url.isEmpty
              ? Text(
                  sticker.keyword ?? '😀',
                  style: const TextStyle(fontSize: 34),
                )
              : Padding(
                  padding: const EdgeInsets.all(6),
                  child: AuthenticatedImage(
                    url: url,
                    fit: BoxFit.contain,
                    loader: loader,
                    authService: authService,
                    placeholder: (_) => const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorBuilder: (_) => Semantics(
                      label: '贴纸加载失败',
                      child: Text(
                        sticker.keyword?.isNotEmpty == true
                            ? sticker.keyword!
                            : '贴纸',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
