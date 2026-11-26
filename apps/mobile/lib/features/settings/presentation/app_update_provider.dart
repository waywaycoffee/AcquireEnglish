import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/app_update_service.dart';

const String kAppUpdateDismissedVersionKey = 'app_update_dismissed_version_v1';

/// Legacy daily throttle key (kept for old installs; no longer gates checks).
const String kAppUpdateLastCheckDayKey = 'app_update_last_check_day_v1';

final FutureProvider<String> appVersionProvider = FutureProvider<String>((
  Ref ref,
) async {
  final PackageInfo packageInfo = await PackageInfo.fromPlatform();
  return packageInfo.version;
});

final NotifierProvider<AppUpdateNotifier, AppUpdateState> appUpdateProvider =
    NotifierProvider<AppUpdateNotifier, AppUpdateState>(AppUpdateNotifier.new);

class AppUpdateState {
  const AppUpdateState({
    this.update,
    this.isChecking = false,
    this.isDownloading = false,
    this.isInstalling = false,
    this.downloadedPath,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.message,
    this.fromAutoCheck = false,
    this.force = false,
    this.localBuildNumber = 0,
  });

  final AppUpdate? update;
  final bool isChecking;
  final bool isDownloading;
  final bool isInstalling;
  final String? downloadedPath;
  final int downloadedBytes;
  final int? totalBytes;
  final String? message;
  final bool fromAutoCheck;
  final bool force;
  final int localBuildNumber;

  double? get downloadProgress => totalBytes == null || totalBytes! <= 0
      ? null
      : downloadedBytes / totalBytes!;
}

class AppUpdateNotifier extends Notifier<AppUpdateState> {
  @override
  AppUpdateState build() => const AppUpdateState();

  Future<void> check({bool auto = false}) async {
    state = AppUpdateState(isChecking: true, fromAutoCheck: auto);
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final int localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final AppUpdate? update = await AppUpdateService().checkForUpdate();
      if (update == null) {
        state = AppUpdateState(
          fromAutoCheck: auto,
          localBuildNumber: localBuild,
          message: auto ? null : '当前已是最新版本。',
        );
        return;
      }
      final bool forced = update.isForcedForLocalBuild(localBuild);
      if (auto && !forced && _isDismissed(update.version)) {
        state = AppUpdateState(
          fromAutoCheck: true,
          localBuildNumber: localBuild,
        );
        return;
      }
      state = AppUpdateState(
        update: update,
        fromAutoCheck: auto,
        force: forced,
        localBuildNumber: localBuild,
        message: forced
            ? '必须更新到 v${update.version} 才能继续使用。'
            : '发现 v${update.version}，可以下载更新。',
      );
    } catch (error) {
      state = AppUpdateState(
        fromAutoCheck: auto,
        message: auto ? null : '更新检测失败：$error',
      );
    }
  }

  /// Home launch: always hit the official manifest (tiny JSON). Soft prompts
  /// still respect per-version dismiss; forced updates never do.
  Future<void> maybeAutoCheck() async {
    await check(auto: true);
  }

  void dismissPrompt() {
    final AppUpdate? update = state.update;
    if (update != null && !state.force) {
      _markDismissed(update.version);
    }
    state = AppUpdateState(
      update: update,
      downloadedPath: state.downloadedPath,
      fromAutoCheck: false,
      force: state.force,
      localBuildNumber: state.localBuildNumber,
      message: null,
    );
  }

  Future<void> download() async {
    final AppUpdate? update = state.update;
    if (update == null) {
      return;
    }
    final bool forced = state.force;
    final int localBuild = state.localBuildNumber;
    state = AppUpdateState(
      update: update,
      isDownloading: true,
      force: forced,
      localBuildNumber: localBuild,
    );
    try {
      final String path = await AppUpdateService().download(
        update,
        onProgress: (int received, int total) {
          state = AppUpdateState(
            update: update,
            isDownloading: true,
            downloadedBytes: received,
            totalBytes: total > 0 ? total : null,
            force: forced,
            localBuildNumber: localBuild,
          );
        },
      );
      state = AppUpdateState(
        update: update,
        downloadedPath: path,
        force: forced,
        localBuildNumber: localBuild,
        message: '下载并校验完成，可以开始安装。',
      );
    } catch (error) {
      state = AppUpdateState(
        update: update,
        force: forced,
        localBuildNumber: localBuild,
        message: '更新下载失败：$error',
      );
    }
  }

  Future<void> install() async {
    final String? path = state.downloadedPath;
    final AppUpdate? update = state.update;
    if (path == null || update == null) {
      return;
    }
    final bool forced = state.force;
    final int localBuild = state.localBuildNumber;
    state = AppUpdateState(
      update: update,
      downloadedPath: path,
      isInstalling: true,
      force: forced,
      localBuildNumber: localBuild,
    );
    try {
      await AppUpdateService().install(path);
      state = AppUpdateState(
        update: update,
        downloadedPath: path,
        force: forced,
        localBuildNumber: localBuild,
        message: '已打开安装包，请按系统提示完成安装。',
      );
    } catch (error) {
      state = AppUpdateState(
        update: update,
        downloadedPath: path,
        force: forced,
        localBuildNumber: localBuild,
        message: '无法打开安装包：$error',
      );
    }
  }

  Box<String>? get _prefs {
    if (!Hive.isBoxOpen('prefs')) return null;
    return Hive.box<String>('prefs');
  }

  bool _isDismissed(String version) {
    return _prefs?.get(kAppUpdateDismissedVersionKey) == version;
  }

  void _markDismissed(String version) {
    _prefs?.put(kAppUpdateDismissedVersionKey, version);
  }
}
