import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Official sideload channel (ECS / download page).
const String kOfficialAndroidManifestUrl =
    'https://acquireenglish.curlhairai.com/downloads/android-latest.json';

bool isOfficialAndroidDownloadUrl(String raw) {
  final Uri uri = Uri.tryParse(raw.trim()) ?? Uri();
  return uri.scheme == 'https' &&
      uri.host == 'acquireenglish.curlhairai.com' &&
      uri.path.startsWith('/downloads/');
}

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
        connectTimeout: const Duration(seconds: 20),
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
    if (!isOfficialAndroidDownloadUrl(apkUrl)) {
      throw StateError('官网更新清单包含非官方下载地址。');
    }
    final String assetName = '${json['apk_name'] ?? ''}'.trim().isEmpty
        ? 'AcquireEnglish-android-latest.apk'
        : '${json['apk_name']}'.trim();
    final String sha = '${json['sha256'] ?? ''}'.trim();
    final String checksumUrl = '${json['checksum_url'] ?? ''}'.trim();
    final bool forceFlag =
        json['force'] == true ||
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
    final File partial = File('${file.path}.part');
    final String downloadUrl = _immutableApkUrl(update);

    // Mobile networks often close a 130MB APK transfer midway. Keep the
    // partial file and resume with HTTP Range instead of restarting at 0%.
    DioException? lastError;
    bool completed = false;
    for (int attempt = 0; attempt < 5; attempt++) {
      final int offset = partial.existsSync() ? partial.lengthSync() : 0;
      try {
        final Response<dynamic> response = await _dio.download(
          downloadUrl,
          partial.path,
          deleteOnError: false,
          fileAccessMode: offset > 0
              ? FileAccessMode.append
              : FileAccessMode.write,
          options: Options(
            headers: <String, String>{
              'Accept': 'application/octet-stream',
              'Accept-Encoding': 'identity',
              if (offset > 0) 'Range': 'bytes=$offset-',
            },
            connectTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 20),
            // This measures an idle gap, not total download duration.
            receiveTimeout: const Duration(minutes: 2),
          ),
          onReceiveProgress: (int received, int total) {
            onProgress?.call(
              offset + received,
              total > 0 ? offset + total : -1,
            );
          },
        );
        final int? status = response.statusCode;
        if (offset > 0 && status != HttpStatus.partialContent) {
          // A proxy ignored Range and sent the whole APK. Appending it would
          // corrupt the package, so restart once from an empty file.
          partial.deleteSync();
          continue;
        }
        lastError = null;
        completed = true;
        break;
      } on DioException catch (error) {
        lastError = error;
        if (attempt < 4) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    if (!completed) {
      final bool timeout =
          lastError?.type == DioExceptionType.connectionTimeout ||
          lastError?.type == DioExceptionType.receiveTimeout ||
          lastError?.type == DioExceptionType.sendTimeout;
      throw StateError(
        timeout ? '连接官网超时，已保留下载进度，请重试继续下载。' : '网络中断，已保留下载进度，请重试继续下载。',
      );
    }

    final String? expected = await _expectedChecksum(update);
    if (expected != null && expected.isNotEmpty) {
      final String actualChecksum =
          (await sha256.bind(partial.openRead()).first).toString();
      if (actualChecksum.toLowerCase() != expected.toLowerCase()) {
        await partial.delete();
        throw StateError('安装包校验失败，已删除下载文件。');
      }
    }
    if (file.existsSync()) {
      file.deleteSync();
    }
    await partial.rename(file.path);
    return file.path;
  }

  String _immutableApkUrl(AppUpdate update) {
    final Uri latest = Uri.parse(update.downloadUrl);
    // The manifest asset name is versioned. Downloading that immutable file
    // prevents a release changing the `latest` symlink during a resumed range.
    return latest
        .replace(
          pathSegments: <String>[
            ...latest.pathSegments.take(latest.pathSegments.length - 1),
            update.assetName,
          ],
        )
        .toString();
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
    final Response<String> response = await _dio.get<String>(
      url,
      options: Options(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
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
