import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Official sideload channel (ECS / download page).
const String kOfficialAndroidManifestUrl =
    'https://acquireenglish.curlhairai.com/downloads/android-latest.json';

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

  /// Manifest `force: true` — this release must be installed.
  final bool force;

  /// Manifest `min_version_code` — local builds below this must update.
  final int? minVersionCode;

  /// Whether the installed build is below the channel floor / forced.
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
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<AppUpdate?> checkForUpdate() async {
    if (!Platform.isAndroid) {
      // Desktop still unsupported for official APK channel.
      return null;
    }
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final Response<dynamic> response = await _dio.get<dynamic>(
      kOfficialAndroidManifestUrl,
      options: Options(
        headers: <String, String>{'Accept': 'application/json'},
        receiveTimeout: const Duration(seconds: 12),
      ),
    );
    final Object? data = response.data;
    if (data is! Map) {
      throw StateError('官网更新清单格式无效。');
    }
    final Map<String, dynamic> json = Map<String, dynamic>.from(data);
    final String latestVersion = '${json['version'] ?? ''}'.trim();
    if (latestVersion.isEmpty) {
      throw StateError('官网更新清单缺少 version。');
    }
    final int? latestCode = (json['version_code'] as num?)?.toInt();
    final int localCode = int.tryParse(packageInfo.buildNumber) ?? 0;
    final bool newerByCode =
        latestCode != null && latestCode > 0 && latestCode > localCode;
    final bool newerByName =
        _compareVersions(latestVersion, packageInfo.version) > 0;
    if (!newerByCode && !newerByName) {
      return null;
    }

    final String apkUrl = '${json['apk_url'] ?? ''}'.trim();
    if (apkUrl.isEmpty) {
      throw StateError('官网更新清单缺少 apk_url。');
    }
    final String assetName = '${json['apk_name'] ?? ''}'.trim().isEmpty
        ? 'AcquireEnglish-android-latest.apk'
        : '${json['apk_name']}'.trim();
    final String sha = '${json['sha256'] ?? ''}'.trim();
    final String checksumUrl = '${json['checksum_url'] ?? ''}'.trim();
    final bool forceFlag = json['force'] == true ||
        '${json['force'] ?? ''}'.trim().toLowerCase() == 'true';
    final int? minVersionCode = (json['min_version_code'] as num?)?.toInt();

    return AppUpdate(
      version: latestVersion,
      versionCode: latestCode,
      assetName: assetName,
      downloadUrl: apkUrl,
      checksumUrl: checksumUrl.isEmpty ? null : checksumUrl,
      sha256: sha.isEmpty ? null : sha,
      notes: '${json['notes'] ?? ''}'.trim(),
      force: forceFlag,
      minVersionCode: minVersionCode,
    );
  }

  Future<String> download(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final Directory root =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final Directory destination = Directory(
      '${root.path}${Platform.pathSeparator}AcquireEnglish',
    );
    await destination.create(recursive: true);
    final File file = File(
      '${destination.path}${Platform.pathSeparator}${update.assetName}',
    );

    await _dio.download(
      update.downloadUrl,
      file.path,
      onReceiveProgress: onProgress,
    );

    final String? expected = await _expectedChecksum(update);
    if (expected != null && expected.isNotEmpty) {
      final String actualChecksum = (await sha256.bind(file.openRead()).first)
          .toString();
      if (actualChecksum.toLowerCase() != expected.toLowerCase()) {
        await file.delete();
        throw StateError('安装包校验失败，已删除下载文件。');
      }
    }
    return file.path;
  }

  Future<void> install(String path) async {
    final OpenResult result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<String?> _expectedChecksum(AppUpdate update) async {
    final String? inline = update.sha256?.trim();
    if (inline != null && inline.isNotEmpty) return inline;
    final String? url = update.checksumUrl?.trim();
    if (url == null || url.isEmpty) return null;
    final Response<String> response = await _dio.get<String>(url);
    for (final String rawLine in response.data?.split('\n') ?? <String>[]) {
      final String line = rawLine.trim();
      if (line.endsWith('  ${update.assetName}') ||
          line.endsWith(' ${update.assetName}')) {
        return line.split(RegExp(r'\s+')).first;
      }
      // Single-hash file.
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(line)) {
        return line;
      }
    }
    return null;
  }
}

int _compareVersions(String left, String right) {
  final List<int> leftParts = left
      .split('+')
      .first
      .split('.')
      .map(int.parse)
      .toList();
  final List<int> rightParts = right
      .split('+')
      .first
      .split('.')
      .map(int.parse)
      .toList();
  final int length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (int index = 0; index < length; index++) {
    final int difference =
        (index < leftParts.length ? leftParts[index] : 0) -
        (index < rightParts.length ? rightParts[index] : 0);
    if (difference != 0) {
      return difference;
    }
  }
  return 0;
}
