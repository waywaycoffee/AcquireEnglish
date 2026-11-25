import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/app_update_service.dart';

const String kAppUpdateLastCheckDayKey = 'app_update_last_check_day_v1';
const String kAppUpdateDismissedVersionKey = 'app_update_dismissed_version_v1';

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
      final AppUpdate? update = await AppUpdateService().checkForUpdate();
      if (auto) {
        _markCheckedToday();
        if (update != null && _isDismissed(update.version)) {
          state = const AppUpdateState(
            message: null,
            fromAutoCheck: true,
          );
          return;
        }
      }
      state = AppUpdateState(
        update: update,
        fromAutoCheck: auto,
        message: update == null
            ? (auto ? null : '当前已是最新版本。')
            : '发现 v${update.version}，可以下载更新。',
      );
    } catch (error) {
      state = AppUpdateState(
        fromAutoCheck: auto,
        message: auto ? null : '更新检测失败：$error',
      );
    }
  }

  /// Silent daily check used on home launch.
  Future<void> maybeAutoCheck() async {
    if (_checkedToday()) return;
    await check(auto: true);
  }

  void dismissPrompt() {
    final AppUpdate? update = state.update;
    if (update != null) {
      _markDismissed(update.version);
    }
    state = AppUpdateState(
      update: update,
      downloadedPath: state.downloadedPath,
      fromAutoCheck: false,
      message: null,
    );
  }

  Future<void> download() async {
    final AppUpdate? update = state.update;
    if (update == null) {
      return;
    }
    state = AppUpdateState(update: update, isDownloading: true);
    try {
      final String path = await AppUpdateService().download(
        update,
        onProgress: (int received, int total) {
          state = AppUpdateState(
            update: update,
            isDownloading: true,
            downloadedBytes: received,
            totalBytes: total > 0 ? total : null,
          );
        },
      );
      state = AppUpdateState(
        update: update,
        downloadedPath: path,
        message: '下载并校验完成，可以开始安装。',
      );
    } catch (error) {
      state = AppUpdateState(update: update, message: '更新下载失败：$error');
    }
  }

  Future<void> install() async {
    final String? path = state.downloadedPath;
    final AppUpdate? update = state.update;
    if (path == null || update == null) {
      return;
    }
    state = AppUpdateState(
      update: update,
      downloadedPath: path,
      isInstalling: true,
    );
    try {
      await AppUpdateService().install(path);
      state = AppUpdateState(
        update: update,
        downloadedPath: path,
        message: '已打开安装包，请按系统提示完成安装。',
      );
    } catch (error) {
      state = AppUpdateState(
        update: update,
        downloadedPath: path,
        message: '无法打开安装包：$error',
      );
    }
  }

  Box<String>? get _prefs {
    if (!Hive.isBoxOpen('prefs')) return null;
    return Hive.box<String>('prefs');
  }

  String _todayKey() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  bool _checkedToday() {
    return _prefs?.get(kAppUpdateLastCheckDayKey) == _todayKey();
  }

  void _markCheckedToday() {
    _prefs?.put(kAppUpdateLastCheckDayKey, _todayKey());
  }

  bool _isDismissed(String version) {
    return _prefs?.get(kAppUpdateDismissedVersionKey) == version;
  }

  void _markDismissed(String version) {
    _prefs?.put(kAppUpdateDismissedVersionKey, version);
  }
}
