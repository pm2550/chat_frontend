import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../constants/api_constants.dart';
import '../../constants/app_brand.dart';
import '../../constants/app_colors.dart';
import '../../design/design.dart';
import '../../utils/link_utils.dart';
import '../../widgets/pm_brand.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();

/// 构建时通过 `--dart-define=BUILD_COMMIT=<sha>` 注入的提交号；没注入时为空，
/// 关于页就不显示这一行。
const String _buildCommit = String.fromEnvironment('BUILD_COMMIT');

/// “关于”对话框：应用名、版本号（来自安装包本身）、构建提交号和常用链接。
Future<void> showAboutAppDialog(
  BuildContext context, {
  PackageInfoLoader? packageInfoLoader,
  String buildCommit = _buildCommit,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AboutAppDialog(
      packageInfoLoader: packageInfoLoader ?? PackageInfo.fromPlatform,
      buildCommit: buildCommit,
    ),
  );
}

class AboutAppDialog extends StatelessWidget {
  const AboutAppDialog({
    super.key,
    required this.packageInfoLoader,
    this.buildCommit = '',
  });

  final PackageInfoLoader packageInfoLoader;
  final String buildCommit;

  @override
  Widget build(BuildContext context) {
    final commit = buildCommit.trim();
    return AlertDialog(
      title: const PMDialogHeader(title: '关于', showHandle: false),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<PackageInfo>(
          future: packageInfoLoader(),
          builder: (context, snapshot) {
            final info = snapshot.data;
            final version = info == null
                ? (snapshot.hasError ? '未知' : '读取中…')
                : info.buildNumber.isEmpty
                    ? info.version
                    : '${info.version}（构建 ${info.buildNumber}）';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PMChatLogo(size: 44),
                const SizedBox(height: PMSpacing.m),
                const Text(
                  AppBrand.description,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: PMSpacing.l),
                _AboutRow(label: '版本', value: version),
                if (commit.isNotEmpty)
                  _AboutRow(
                    label: '提交',
                    value:
                        commit.length > 12 ? commit.substring(0, 12) : commit,
                  ),
                _AboutRow(
                  label: '服务器',
                  value: Uri.tryParse(ApiConstants.baseUrl)?.host ??
                      ApiConstants.baseUrl,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: AppBrand.name,
          ),
          child: const Text('开源许可'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed('/downloads');
          },
          child: const Text('下载客户端'),
        ),
        if (!kIsWeb)
          TextButton(
            onPressed: () => LinkUtils.openExternal(ApiConstants.webAppUrl),
            child: const Text('网页版'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
