class AppVersionCheck {
  final bool updateAvailable;
  final bool forceUpdate;
  final String? latestVersion;
  final int? latestVersionCode;
  final String? releaseNotes;
  final String? downloadUrl;
  final int? fileSize;

  const AppVersionCheck({
    required this.updateAvailable,
    this.forceUpdate = false,
    this.latestVersion,
    this.latestVersionCode,
    this.releaseNotes,
    this.downloadUrl,
    this.fileSize,
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
    );
  }

  factory AppVersionCheck.noUpdate() =>
      const AppVersionCheck(updateAvailable: false);
}
