class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    this.versionCode,
    this.checksumUrl,
    this.sha256,
    this.notes = '',
    this.force = false,
    this.minVersionCode,
  });

  final String version;
  final int? versionCode;
  final String assetName;
  final String downloadUrl;
  final String? checksumUrl;
  final String? sha256;
  final String notes;
  final bool force;
  final int? minVersionCode;

  bool isForcedForLocalBuild(int localBuildNumber) {
    if (force) return true;
    final int? minCode = minVersionCode;
    if (minCode != null && minCode > 0 && localBuildNumber < minCode) {
      return true;
    }
    return false;
  }
}

class AppUpdateService {
  Future<AppUpdate?> checkForUpdate() {
    throw UnsupportedError('Web 版请前往官网下载 Android 安装包。');
  }

  Future<String> download(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
  }) {
    throw UnsupportedError('Web 版不支持应用内下载安装包。');
  }

  Future<void> install(String path) {
    throw UnsupportedError('Web 版不支持应用内安装。');
  }
}
