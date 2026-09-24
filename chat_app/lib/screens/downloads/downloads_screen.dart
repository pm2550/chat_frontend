import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_brand.dart';
import '../../constants/app_colors.dart';
import '../../services/client_download_launcher.dart';
import '../../services/download_catalog_service.dart';
import '../../widgets/pm_brand.dart';
import '../../widgets/pm_responsive.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    this.downloadService = const DownloadCatalogService(),
    this.downloadOpener,
    this.linkOpener,
  });

  final DownloadCatalogService downloadService;
  final Future<bool> Function(String url, String filename)? downloadOpener;

  /// 打开外部链接（TestFlight / 网页版）；测试里替换。
  final Future<bool> Function(String url)? linkOpener;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late Future<List<ClientDownloadStatus>> _catalogFuture;

  @override
  void initState() {
    super.initState();
    _catalogFuture = widget.downloadService.fetchCatalog();
  }

  void _reload() {
    setState(() {
      _catalogFuture = widget.downloadService.fetchCatalog();
    });
  }

  Future<void> _open(ClientDownloadStatus status) async {
    if (status.target.isWeb) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      return;
    }

    if (status.target.showsPwaInstructions) {
      await _showPwaInstructions();
      return;
    }
    final externalUrl = status.target.externalUrl;
    if (externalUrl != null && externalUrl.isNotEmpty) {
      await _openExternal(externalUrl);
      return;
    }

    final rawUrl = status.downloadUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      _showMessage('${status.target.shortLabel} 客户端还没有发布包');
      return;
    }

    final url = widget.downloadService.resolveDownloadUrl(rawUrl);
    final filename = Uri.parse(url).pathSegments.last;
    final opened = await (widget.downloadOpener?.call(url, filename) ??
        launchClientDownload(url, filename: filename));
    if (!opened) {
      _showMessage('无法打开下载链接');
    }
  }

  Future<void> _openExternal(String url) async {
    var opened = false;
    try {
      opened = await (widget.linkOpener?.call(url) ??
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
    } catch (_) {}
    if (!opened) _showMessage('无法打开 $url');
  }

  /// iPhone/iPad 没有可装的安装包：讲清楚怎么把网页版添加到主屏幕。
  Future<void> _showPwaInstructions() async {
    final openWebApp = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('在 iPhone / iPad 上使用'),
        content: const Text(
          '暂时没有可以直接安装的 iOS 安装包。\n\n'
          '1. 用 Safari 打开 PM chat 网页版\n'
          '2. 点底部的「分享」按钮\n'
          '3. 选择「添加到主屏幕」\n\n'
          '之后从主屏幕图标打开，就和 App 一样使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('知道了'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('打开网页版'),
          ),
        ],
      ),
    );
    if (openWebApp != true || !mounted) return;
    if (kIsWeb) {
      // 已经在网页版里了，直接去登录页。
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      return;
    }
    await _openExternal(widget.downloadService.webAppUrl);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PMChatPattern(
        dense: true,
        child: SafeArea(
          child: FutureBuilder<List<ClientDownloadStatus>>(
            future: _catalogFuture,
            builder: (context, snapshot) {
              final statuses = snapshot.data ?? const <ClientDownloadStatus>[];
              final recommended = _recommendedStatus(statuses);

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: PMBreakpoints.isDesktop(context) ? 44 : 20,
                  vertical: PMBreakpoints.isDesktop(context) ? 36 : 22,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DownloadHeader(onReload: _reload),
                        const SizedBox(height: 26),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const _LoadingPanel()
                        else ...[
                          _RecommendedDownloadCard(
                            status: recommended,
                            onOpen: () => _open(recommended),
                          ),
                          const SizedBox(height: 20),
                          _AllClientsGrid(
                            statuses: statuses,
                            onOpen: _open,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  ClientDownloadStatus _recommendedStatus(List<ClientDownloadStatus> statuses) {
    final target = widget.downloadService.recommendedTarget();
    final detectedStatus = statuses.firstWhere(
      (status) => status.target.platform == target.platform,
      orElse: () => ClientDownloadStatus(target: target),
    );
    if (detectedStatus.isAvailable) {
      return detectedStatus;
    }
    return statuses.firstWhere(
      (status) => status.isAvailable,
      orElse: () => detectedStatus,
    );
  }
}

class _DownloadHeader extends StatelessWidget {
  const _DownloadHeader({required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final desktop = PMBreakpoints.isDesktop(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PMChatLogo(size: 50, showWordmark: false),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${AppBrand.name} 客户端下载',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                '自动识别当前设备，也可以手动选择其他平台。',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        if (desktop) ...[
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/login'),
            icon: const Icon(Icons.login),
            label: const Text('返回登录'),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: '刷新',
            onPressed: onReload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ],
    );
  }
}

class _RecommendedDownloadCard extends StatelessWidget {
  const _RecommendedDownloadCard({
    required this.status,
    required this.onOpen,
  });

  final ClientDownloadStatus status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final target = status.target;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final content = [
            _ClientIcon(platform: target.platform, large: true),
            const SizedBox(width: 18, height: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '推荐入口',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    target.label,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusLine(status),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ];

          final button = FilledButton.icon(
            onPressed: status.isAvailable ? onOpen : null,
            icon: Icon(target.isWeb ? Icons.open_in_browser : Icons.download),
            label: Text(target.primaryAction),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: content),
                const SizedBox(height: 18),
                button,
              ],
            );
          }

          return Row(
            children: [
              ...content,
              const SizedBox(width: 22),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _AllClientsGrid extends StatelessWidget {
  const _AllClientsGrid({
    required this.statuses,
    required this.onOpen,
  });

  final List<ClientDownloadStatus> statuses;
  final ValueChanged<ClientDownloadStatus> onOpen;

  @override
  Widget build(BuildContext context) {
    final desktop = PMBreakpoints.isDesktop(context);
    final columns = desktop ? 3 : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '全部客户端',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          itemCount: statuses.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 196,
          ),
          itemBuilder: (context, index) {
            final status = statuses[index];
            return _ClientDownloadTile(
              status: status,
              onOpen: () => onOpen(status),
            );
          },
        ),
      ],
    );
  }
}

class _ClientDownloadTile extends StatelessWidget {
  const _ClientDownloadTile({
    required this.status,
    required this.onOpen,
  });

  final ClientDownloadStatus status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final target = status.target;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: status.isAvailable ? AppColors.borderLight : AppColors.border,
        ),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ClientIcon(platform: target.platform),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      target.packageLabel,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            target.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  _statusLine(status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: status.isAvailable
                        ? AppColors.secondaryDark
                        : AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: target.primaryAction,
                onPressed: status.isAvailable ? onOpen : null,
                icon: Icon(target.isWeb ? Icons.open_in_new : Icons.download),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientIcon extends StatelessWidget {
  const _ClientIcon({
    required this.platform,
    this.large = false,
  });

  final ClientDownloadPlatform platform;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 58.0 : 44.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _iconBackground(platform),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          _iconText(platform),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _iconForeground(platform),
            fontSize: large ? 17 : 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: const CircularProgressIndicator(),
    );
  }
}

String _statusLine(ClientDownloadStatus status) {
  if (status.target.isWeb) {
    return '当前可用';
  }
  if (status.target.showsPwaInstructions) {
    return '暂无安装包，使用网页版';
  }
  if (status.target.externalUrl != null) {
    return '通过链接安装';
  }
  if (status.hasError) {
    return status.error!;
  }
  if (!status.hasDownloadUrl) {
    return '尚未发布构建包';
  }

  final version =
      status.latestVersion == null ? '' : 'v${status.latestVersion}';
  final size =
      status.fileSize == null ? '' : ' · ${_formatBytes(status.fileSize!)}';
  return [version, size].where((part) => part.isNotEmpty).join('');
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}

String _iconText(ClientDownloadPlatform platform) {
  return switch (platform) {
    ClientDownloadPlatform.web => 'WEB',
    ClientDownloadPlatform.android => 'APK',
    ClientDownloadPlatform.ios => 'iOS',
    ClientDownloadPlatform.windows => 'WIN',
    ClientDownloadPlatform.macos => 'mac',
    ClientDownloadPlatform.linux => 'LIN',
  };
}

Color _iconBackground(ClientDownloadPlatform platform) {
  return switch (platform) {
    ClientDownloadPlatform.web => AppColors.pixelBlue,
    ClientDownloadPlatform.android => AppColors.pixelMint,
    ClientDownloadPlatform.ios => AppColors.pixelBlue,
    ClientDownloadPlatform.windows => AppColors.pixelBlue,
    ClientDownloadPlatform.macos => AppColors.pixelCoral,
    ClientDownloadPlatform.linux => AppColors.mist,
  };
}

Color _iconForeground(ClientDownloadPlatform platform) {
  return switch (platform) {
    ClientDownloadPlatform.web => AppColors.primary,
    ClientDownloadPlatform.android => AppColors.secondaryDark,
    ClientDownloadPlatform.ios => AppColors.primaryDark,
    ClientDownloadPlatform.windows => AppColors.primary,
    ClientDownloadPlatform.macos => AppColors.accent,
    ClientDownloadPlatform.linux => AppColors.textPrimary,
  };
}
