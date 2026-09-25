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
    this.externalUrl,
    this.showsPwaInstructions = false,
    this.abi,
    this.secondary,
  });

  final ClientDownloadPlatform platform;
  final String apiPlatform;
  final String label;
  final String shortLabel;
  final String packageLabel;
  final String description;
  final String primaryAction;
  final bool isWeb;

  /// 不是下载安装包而是打开一个链接（TestFlight、网页版）。
  final String? externalUrl;

  /// 点了先讲清楚怎么在 iPhone/iPad 上把网页版添加到主屏幕。
  final bool showsPwaInstructions;

  /// Android 分架构安装包：查版本时带上的 ABI（arm64-v8a / armeabi-v7a）。
  final String? abi;

  /// 同一平台的次要下载（Android 的 32 位旧手机包），卡片上显示成一个小链接。
  final ClientDownloadTarget? secondary;
}

class ClientDownloadStatus {
  const ClientDownloadStatus({
    required this.target,
    this.latestVersion,
    this.downloadUrl,
    this.fileSize,
    this.releaseNotes,
    this.error,
    this.secondary,
  });

  final ClientDownloadTarget target;
  final String? latestVersion;
  final String? downloadUrl;
  final int? fileSize;
  final String? releaseNotes;
  final String? error;

  /// 次要下载（Android 32 位包）；没发布、或者和主下载是同一个文件（拆包前的整包）时为 null。
  final ClientDownloadStatus? secondary;

  bool get hasDownloadUrl => downloadUrl != null && downloadUrl!.isNotEmpty;
  bool get isAvailable => target.isWeb || hasDownloadUrl;
  bool get hasError => error != null && error!.isNotEmpty;

  ClientDownloadStatus withSecondary(ClientDownloadStatus? value) =>
      ClientDownloadStatus(
        target: target,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        fileSize: fileSize,
        releaseNotes: releaseNotes,
        error: error,
        secondary: value,
      );
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
      packageLabel: '.zip（解压即用）',
      description: '适合 Windows 10/11 桌面工作台，解压后运行 chat_app.exe。',
      primaryAction: '下载 Windows 版',
    ),
    ClientDownloadTarget(
      platform: ClientDownloadPlatform.macos,
      apiPlatform: 'MACOS',
      label: 'macOS',
      shortLabel: 'macOS',
      packageLabel: '.zip',
      description: '适合 Mac 桌面端，解压后把 PM chat 拖进「应用程序」。',
      primaryAction: '下载 macOS 版',
    ),
    ClientDownloadTarget(
      platform: ClientDownloadPlatform.linux,
      apiPlatform: 'LINUX',
      label: 'Linux',
      shortLabel: 'Linux',
      packageLabel: '.tar.gz',
      description: '适合 Linux x64 桌面环境，解压后运行 bundle/chat_app。',
      primaryAction: '下载 Linux 版',
    ),
    // Android 按 CPU 架构拆成两个 APK：主按钮给 64 位（绝大多数手机），
    // 32 位旧手机单独一个小链接。
    ClientDownloadTarget(
      platform: ClientDownloadPlatform.android,
      apiPlatform: 'ANDROID',
      label: 'Android',
      shortLabel: 'Android',
      packageLabel: '.apk · 64 位',
      description: '适合绝大多数 Android 手机和平板（64 位）。'
          '装不上的 32 位旧手机请下 32 位版。',
      primaryAction: '下载 Android（推荐，64 位）',
      abi: 'arm64-v8a',
      secondary: android32Target,
    ),
    ApiConstants.iosTestFlightUrl.length == 0
        ? iosWebAppTarget
        : iosTestFlightTarget,
  ];

  /// 只给装不上 64 位版的旧手机（多是 2015 年前后的机型）。
  static const ClientDownloadTarget android32Target = ClientDownloadTarget(
    platform: ClientDownloadPlatform.android,
    apiPlatform: 'ANDROID',
    label: 'Android 32 位',
    shortLabel: 'Android 32 位',
    packageLabel: '.apk · 32 位',
    description: '只给装不上 64 位版的 32 位旧手机。',
    primaryAction: '32 位旧手机',
    abi: 'armeabi-v7a',
  );

  /// 浏览器下载的 .ipa 装不到 iPhone 上。没有配置 TestFlight 公开链接时，
  /// 老实告诉用户用网页版（添加到主屏幕）。
  static const ClientDownloadTarget iosWebAppTarget = ClientDownloadTarget(
    platform: ClientDownloadPlatform.ios,
    apiPlatform: 'IOS',
    label: 'iPhone / iPad',
    shortLabel: 'iOS',
    packageLabel: '网页版 · 添加到主屏幕',
    description: '暂无可直接安装的 iOS 安装包。用 Safari 打开网页版，'
        '点「分享 → 添加到主屏幕」即可像 App 一样使用。',
    primaryAction: '在 iPhone 上使用',
    externalUrl: ApiConstants.webAppUrl,
    showsPwaInstructions: true,
  );

  static const ClientDownloadTarget iosTestFlightTarget = ClientDownloadTarget(
    platform: ClientDownloadPlatform.ios,
    apiPlatform: 'IOS',
    label: 'iPhone / iPad',
    shortLabel: 'iOS',
    packageLabel: 'TestFlight',
    description: '在 iPhone / iPad 上装 TestFlight，再通过邀请链接安装。',
    primaryAction: '前往 TestFlight',
    externalUrl: ApiConstants.iosTestFlightUrl,
  );

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
    return Future.wait(targets.map(fetchStatus));
  }

  Future<ClientDownloadStatus> fetchRecommended() {
    return fetchStatus(recommendedTarget());
  }

  Future<ClientDownloadStatus> fetchStatus(ClientDownloadTarget target) async {
    final externalUrl = target.externalUrl;
    if (externalUrl != null && externalUrl.isNotEmpty) {
      // 链接型通道不查发布包（比如 iOS 的 .ipa 根本装不上）。
      return ClientDownloadStatus(target: target, downloadUrl: externalUrl);
    }
    if (target.isWeb) {
      return ClientDownloadStatus(
        target: target,
        downloadUrl: ApiConstants.webAppUrl,
      );
    }

    final secondaryTarget = target.secondary;
    final results = await Future.wait([
      _fetchPackage(target),
      if (secondaryTarget != null) _fetchPackage(secondaryTarget),
    ]);
    final primary = results.first;
    if (results.length < 2) return primary;
    final secondary = results[1];
    // 服务器上还只有拆包前的整包时，两个架构查到的是同一个文件：不重复列出。
    if (!secondary.hasDownloadUrl ||
        secondary.downloadUrl == primary.downloadUrl) {
      return primary;
    }
    return primary.withSecondary(secondary);
  }

  Future<ClientDownloadStatus> _fetchPackage(
    ClientDownloadTarget target,
  ) async {
    try {
      final abi = target.abi;
      final uri = Uri.parse(ApiConstants.appVersionCheck).replace(
        queryParameters: {
          'platform': target.apiPlatform,
          'currentVersionCode': '0',
          if (abi != null) 'abi': abi,
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

  String get webAppUrl => ApiConstants.webAppUrl;

  String resolveUrl(String url) {
    if (url.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      return url;
    }
    return '${ApiConstants.baseUrl}$url';
  }

  /// Resolve the public static artifact URL used by browsers.
  ///
  /// The compatibility API route redirects to `/download/...` in production.
  /// Opening that redirect through `url_launcher` can replace a mobile PWA's
  /// current page, so Web downloads should target the final attachment URL.
  String resolveDownloadUrl(String url) {
    final resolved = Uri.parse(resolveUrl(url));
    final base = Uri.parse(ApiConstants.baseUrl);
    const apiPrefix = '/api/v1/app/download/';
    if (resolved.host == base.host && resolved.path.startsWith(apiPrefix)) {
      return resolved
          .replace(
              path: '/download/${resolved.path.substring(apiPrefix.length)}')
          .toString();
    }
    return resolved.toString();
  }

  ClientDownloadTarget _target(ClientDownloadPlatform platform) {
    return targets.firstWhere((target) => target.platform == platform);
  }
}
