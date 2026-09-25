class AppVersionCheck {
  final bool updateAvailable;
  final bool forceUpdate;
  final String? latestVersion;
  final int? latestVersionCode;
  final String? releaseNotes;
  final String? downloadUrl;
  final int? fileSize;

  /// 安装包的 SHA-256（小写十六进制），旧版本服务端/旧发布没有。
  final String? sha256;

  /// 下载地址对应的 Android ABI（arm64-v8a / armeabi-v7a）；整包、其他平台为 null。
  final String? abi;

  const AppVersionCheck({
    required this.updateAvailable,
    this.forceUpdate = false,
    this.latestVersion,
    this.latestVersionCode,
    this.releaseNotes,
    this.downloadUrl,
    this.fileSize,
    this.sha256,
    this.abi,
  });

  factory AppVersionCheck.fromJson(Map<String, dynamic> json) {
    return AppVersionCheck(
      updateAvailable: json['updateAvailable'] ?? false,
      forceUpdate: json['forceUpdate'] ?? false,
      latestVersion: json['latestVersion'],
      latestVersionCode: json['latestVersionCode'],
      releaseNotes: json['releaseNotes'],
      downloadUrl: json['downloadUrl'],
      fileSize: json['fileSize'],
      sha256: json['sha256'],
      abi: json['abi'],
    );
  }

  factory AppVersionCheck.noUpdate() =>
      const AppVersionCheck(updateAvailable: false);
}
