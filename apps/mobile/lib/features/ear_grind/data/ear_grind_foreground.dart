import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps media_kit audio alive while the screen is off / locked.
class EarGrindForeground {
  EarGrindForeground._();

  static const int serviceId = 4202;
  static bool _inited = false;

  static Future<void> ensureInit() async {
    if (_inited || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ear_grind_media',
        channelName: '磨耳朵播放',
        channelDescription: '息屏或锁屏时继续播放导入的音频/视频声音',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: true,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    try {
      FlutterForegroundTask.setOnLockScreenVisibility(true);
    } catch (_) {}
    _inited = true;
  }

  static Future<void> requestPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await ensureInit();
    try {
      final NotificationPermission p =
          await FlutterForegroundTask.checkNotificationPermission();
      if (p != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}
    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (_) {}
  }

  static Future<void> start({
    required String title,
    required String body,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    await ensureInit();
    await requestPermissions();
    final bool running = await FlutterForegroundTask.isRunningService;
    if (running) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
        notificationButtons: const <NotificationButton>[
          NotificationButton(id: 'toggle', text: '播放/暂停'),
          NotificationButton(id: 'open', text: '打开'),
        ],
      );
      return;
    }
    final ServiceRequestResult started =
        await FlutterForegroundTask.startService(
      serviceId: serviceId,
      serviceTypes: const <ForegroundServiceTypes>[
        ForegroundServiceTypes.mediaPlayback,
      ],
      notificationTitle: title,
      notificationText: body,
      notificationButtons: const <NotificationButton>[
        NotificationButton(id: 'toggle', text: '播放/暂停'),
        NotificationButton(id: 'open', text: '打开'),
      ],
      callback: earGrindForegroundCallback,
    );
    if (started is ServiceRequestFailure) {
      debugPrint('ear grind fg start failed: ${started.error}');
    }
  }

  static Future<void> update({
    required String title,
    required String body,
  }) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: body,
    );
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        // Only stop if we own the notification channel-ish service id path;
        // subtitle completion may also use FGS — prefer update then stop when idle.
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void earGrindForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_EarGrindFgHandler());
}

class _EarGrindFgHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Keep isolate warm; playback lives on the main isolate via media_kit.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    FlutterForegroundTask.sendDataToMain(<String, dynamic>{'cmd': id});
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
