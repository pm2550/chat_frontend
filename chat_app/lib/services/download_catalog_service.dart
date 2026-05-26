import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/app_version.dart';

enum ClientDownloadPlatform {
  web,
  android,
  ios,
  windows,
  macos,
  linux,
}

class ClientDownloadTarget {
  const ClientDownloadTarget({
    required this.platform,
    required this.apiPlatform,
    required this.label,
    required this.shortLabel,
    required this.packageLabel,
    required this.description,
    required this.primaryAction,
    this.isWeb = false,
  });

  final ClientDownloadPlatform platform;
  final String apiPlatform;
  final String label;
  final String shortLabel;
  final String packageLabel;
  final String description;
  final String primaryAction;
  final bool isWeb;
}

class ClientDownloadStatus {
  const ClientDownloadStatus({
    required this.target,
    this.latestVersion,
    this.downloadUrl,
    this.fileSize,
    this.releaseNotes,
    this.error,
  });

  final ClientDownloadTarget target;
  final String? latestVersion;
  final String? downloadUrl;
  final int? fileSize;
  final String? releaseNotes;
  final String? error;

  bool get hasDownloadUrl => downloadUrl != null && downloadUrl!.isNotEmpty;
  bool get isAvailable => target.isWeb || hasDownloadUrl;
  bool get hasError => error != null && error!.isNotEmpty;
}

class DownloadCatalogService {
  const DownloadCatalogService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const List<ClientDownloadTarget> defaultTargets = [
    ClientDownloadTarget(
      platform: ClientDownloadPlatform.web,
      apiPlatform: 'WEB',
      label: '网页版 / PWA',
      shortLabel: '网页',
      packageLabel: '浏览器访问',
      description: '适合临时登录、桌面浏览器和安装为 PWA。',
      primaryAction: '打开网页版',
      isWeb: true,
    ),
    ClientDownloadTarget(
      platform: ClientDownloadPlatform.windows,
      apiPlatform: 'WINDOWS',
      label: 'Windows',
      shortLabel: 'Windows',
      packageLabel: '.exe / .zip',
      description: '适合 Windows 10/11 桌面工作台。',
      primaryAction: '下载 Windows 版',
    ),
    ClientDownloadTarget(
      platform: ClientDownloadPlatform.macos,
      apiPlatform: 'MACOS',
      label: 'macOS',
      shortLabel: 'macOS',
      packageLabel: '.dmg / .zip',
      description: '适合 Mac 桌面端和 Apple Silicon/Intel 构建。',
      primaryAction: '下载 macOS 版',
    ),
    ClientDownloadTarget(
      platform: ClientDownloadPlatform.linux,
      apiPlatform: 'LINUX',
      label: 'Linux',
      shortLabel: 'Linux',
      packageLabel: '.AppImage / .tar.gz',
      description: '适合 Linux 桌面环境和内部工作站。',
      primaryAction: '下载 Linux 版',
    ),
    ClientDownloadTarget(
      platform: ClientDownloadPlatform.android,
      apiPlatform: 'ANDROID',
      label: 'Android',
      shortLabel: 'Android',
      packageLabel: '.apk',
      description: '适合 Android 手机和平板安装包分发。',
      primaryAction: '下载 Android APK',
    ),
    ClientDownloadTarget(
      platform: ClientDownloadPlatform.ios,
      apiPlatform: 'IOS',
      label: 'iPhone / iPad',
      shortLabel: 'iOS',
      packageLabel: 'TestFlight / App Store',
      description: '适合 iPhone 和 iPad，按发布通道跳转。',
      primaryAction: '前往 iOS 通道',
    ),
  ];

  List<ClientDownloadTarget> get targets => defaultTargets;

  ClientDownloadTarget recommendedTarget({TargetPlatform? platform}) {
    final current = platform ?? defaultTargetPlatform;
    return switch (current) {
      TargetPlatform.android => _target(ClientDownloadPlatform.android),
      TargetPlatform.iOS => _target(ClientDownloadPlatform.ios),
      TargetPlatform.macOS => _target(ClientDownloadPlatform.macos),
      TargetPlatform.windows => _target(ClientDownloadPlatform.windows),
      TargetPlatform.linux => _target(ClientDownloadPlatform.linux),
      TargetPlatform.fuchsia => _target(ClientDownloadPlatform.web),
    };
  }

  Future<List<ClientDownloadStatus>> fetchCatalog() async {
    final results = <ClientDownloadStatus>[];
    for (final target in targets) {
      results.add(await fetchStatus(target));
    }
    return results;
  }

  Future<ClientDownloadStatus> fetchRecommended() {
    return fetchStatus(recommendedTarget());
  }

  Future<ClientDownloadStatus> fetchStatus(ClientDownloadTarget target) async {
    if (target.isWeb) {
      return ClientDownloadStatus(
        target: target,
        downloadUrl: ApiConstants.webAppUrl,
      );
    }

    try {
      final uri = Uri.parse(ApiConstants.appVersionCheck).replace(
        queryParameters: {
          'platform': target.apiPlatform,
          'currentVersionCode': '0',
        },
      );
      final response = await (_client?.get(uri) ?? http.get(uri))
          .timeout(ApiConstants.requestTimeout);
      if (response.statusCode != 200) {
        return ClientDownloadStatus(
          target: target,
          error: '版本通道暂不可用 (${response.statusCode})',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final version = AppVersionCheck.fromJson(data);
      return ClientDownloadStatus(
        target: target,
        latestVersion: version.latestVersion,
        downloadUrl: version.downloadUrl,
        fileSize: version.fileSize,
        releaseNotes: version.releaseNotes,
      );
    } catch (e) {
      return ClientDownloadStatus(
        target: target,
        error: '版本通道暂不可用',
      );
    }
  }

  String resolveUrl(String url) {
    if (url.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      return url;
    }
    return '${ApiConstants.baseUrl}$url';
  }

  ClientDownloadTarget _target(ClientDownloadPlatform platform) {
    return targets.firstWhere((target) => target.platform == platform);
  }
}
