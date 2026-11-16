import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'native_subtitle_ball.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_scheduler.dart';

/// Keeps subtitle completion alive in background / lock screen, and shows a
/// system overlay floating ball with live progress (Android).
///
/// Critical OEM rule (Android 12+ / 小米): the foreground service **must** be
/// started while the Activity is still foreground. Starting it from `paused`
/// is often rejected silently — then background Whisper freezes.
class SubtitleCompletionRuntime {
  SubtitleCompletionRuntime._();

  static final SubtitleCompletionRuntime instance =
      SubtitleCompletionRuntime._();

  bool _initialized = false;
  bool _serviceRunning = false;
  bool _overlayVisible = false;
  bool _needsOverlayPermission = false;
  bool _notifPermissionAsked = false;
  bool _batteryAsked = false;
  String _lastTitle = '爱快英语 · 补字幕';
  String _lastBody = '正在补全字幕…';
  double _lastProgress = 0.08;
  final StreamController<SubtitleRuntimeSnapshot> _snapshots =
      StreamController<SubtitleRuntimeSnapshot>.broadcast();

  /// True when the Android FGS is actually running (not just requested).
  bool get isActive => _serviceRunning;

  Stream<SubtitleRuntimeSnapshot> get snapshots => _snapshots.stream;

  SubtitleRuntimeSnapshot get currentSnapshot => SubtitleRuntimeSnapshot(
        active: _serviceRunning || _lastProgress > 0 && _lastProgress < 1,
        label: _lastBody,
        progress: _lastProgress,
        overlayVisible: _overlayVisible,
        needsOverlayPermission: _needsOverlayPermission,
      );

  /// Called by [OverlayPermissionHost] after the user grants overlay.
  void clearOverlayPermissionNeeded() {
    if (!_needsOverlayPermission) {
      return;
    }
    _needsOverlayPermission = false;
    _emit();
  }

  Future<void> init() async {
    if (_initialized || kIsWeb || !Platform.isAndroid) {
      _initialized = true;
      return;
    }
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'subtitle_completion_fg',
        channelName: '补字幕进度',
        channelDescription: '导入后补全中英字幕时保持后台运行',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
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
        // Kick the main isolate often so Whisper keeps draining while dimmed.
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    try {
      FlutterForegroundTask.setOnLockScreenVisibility(true);
    } catch (_) {}
    _serviceRunning = await FlutterForegroundTask.isRunningService;
    _initialized = true;
  }

  void _onTaskData(Object data) {
    if (data is Map && data['cmd'] == 'kick') {
      SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    }
  }

  void _emit() {
    if (!_snapshots.isClosed) {
      _snapshots.add(currentSnapshot);
    }
  }

  /// Ask notification / overlay / battery permissions while the UI is visible.
  Future<void> requestPermissions() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    await init();
    await _ensurePermissions();
  }

  /// Start / refresh when the queue has work. Call while app is still resumed.
  Future<bool> ensureRunning({
    String? label,
    double? progress,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }
    await init();
    final bool pending = await SubtitleCompletionQueue.shared.hasPendingWork();
    if (!pending) {
      await stop();
      return false;
    }
    await _ensurePermissions();
    final String rawLabel = (label ?? _lastBody).trim();
    final String body = rawLabel.isEmpty ? '正在补全字幕…' : rawLabel;
    final double frac = (progress ?? _lastProgress).clamp(0.0, 1.0);
    _lastBody = body;
    _lastProgress = frac;
    _lastTitle = '爱快英语 · 补字幕 ${(frac * 100).round()}%';

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    bool running = await FlutterForegroundTask.isRunningService;
    if (running) {
      await FlutterForegroundTask.updateService(
        notificationTitle: _lastTitle,
        notificationText: body,
      );
    } else {
      final ServiceRequestResult started =
          await FlutterForegroundTask.startService(
        serviceId: 4201,
        serviceTypes: const <ForegroundServiceTypes>[
          ForegroundServiceTypes.dataSync,
        ],
        notificationTitle: _lastTitle,
        notificationText: body,
        notificationButtons: const <NotificationButton>[
          NotificationButton(id: 'open', text: '打开'),
        ],
        callback: subtitleForegroundCallback,
      );
      if (started is ServiceRequestFailure) {
        debugPrint('subtitle fg start failed: ${started.error}');
        _serviceRunning = false;
        _emit();
        // Retry once after a short delay — first frame after resume often works.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (await FlutterForegroundTask.isAppOnForeground) {
          final ServiceRequestResult retry =
              await FlutterForegroundTask.startService(
            serviceId: 4201,
            serviceTypes: const <ForegroundServiceTypes>[
              ForegroundServiceTypes.dataSync,
            ],
            notificationTitle: _lastTitle,
            notificationText: body,
            callback: subtitleForegroundCallback,
          );
          if (retry is ServiceRequestFailure) {
            debugPrint('subtitle fg retry failed: ${retry.error}');
            _emit();
            return false;
          }
        } else {
          _emit();
          return false;
        }
      }
      running = await FlutterForegroundTask.isRunningService;
    }
    _serviceRunning = running;
    await _showOrUpdateOverlay(busy: true, label: body, progress: frac);
    _emit();
    return _serviceRunning;
  }

  Future<void> updateProgress({
    required String label,
    required double progress,
  }) async {
    if (!_serviceRunning) {
      await ensureRunning(label: label, progress: progress);
      return;
    }
    final String body = label.trim().isEmpty ? _lastBody : label.trim();
    final double frac = progress.clamp(0.0, 1.0);
    _lastBody = body;
    _lastProgress = frac;
    _lastTitle = '爱快英语 · 补字幕 ${(frac * 100).round()}%';
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: _lastTitle,
        notificationText: body,
      );
      _serviceRunning = true;
    } else {
      _serviceRunning = false;
      await ensureRunning(label: body, progress: frac);
      return;
    }
    await _showOrUpdateOverlay(busy: true, label: body, progress: frac);
    _emit();
  }

  Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) {
      _serviceRunning = false;
      _emit();
      return;
    }
    _serviceRunning = false;
    _lastProgress = 1.0;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    if (_overlayVisible) {
      await NativeSubtitleBall.update(progress: 1.0, label: '完成');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await NativeSubtitleBall.hide();
      _overlayVisible = false;
    }
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    _emit();
  }

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final NotificationPermission notif =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notif != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
        _notifPermissionAsked = true;
      }
    } catch (_) {
      _notifPermissionAsked = true;
    }
    try {
      final bool overlayOk = await NativeSubtitleBall.canDrawOverlays();
      if (!overlayOk) {
        _needsOverlayPermission = true;
        _emit();
      } else {
        _needsOverlayPermission = false;
      }
    } catch (_) {}
    if (!_batteryAsked) {
      _batteryAsked = true;
      try {
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      } catch (_) {}
    }
  }

  Future<void> _showOrUpdateOverlay({
    required bool busy,
    required String label,
    required double progress,
  }) async {
    try {
      final bool granted = await NativeSubtitleBall.canDrawOverlays();
      if (!granted) {
        _needsOverlayPermission = true;
        _overlayVisible = false;
        _emit();
        return;
      }
      _needsOverlayPermission = false;
      final bool shown = _overlayVisible
          ? await NativeSubtitleBall.update(
              progress: busy ? progress : 1.0,
              label: label,
            )
          : await NativeSubtitleBall.show(
              progress: busy ? progress : 1.0,
              label: label,
            );
      _overlayVisible = shown;
    } catch (error) {
      debugPrint('subtitle overlay failed: $error');
      _overlayVisible = false;
    }
  }

  Future<void> dispose() async {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    await stop();
    await _snapshots.close();
  }
}

class SubtitleRuntimeSnapshot {
  const SubtitleRuntimeSnapshot({
    required this.active,
    required this.label,
    required this.progress,
    required this.overlayVisible,
    this.needsOverlayPermission = false,
  });

  final bool active;
  final String label;
  final double progress;
  final bool overlayVisible;
  final bool needsOverlayPermission;
}

@pragma('vm:entry-point')
void subtitleForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_SubtitleForegroundTaskHandler());
}

class _SubtitleForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain(<String, dynamic>{'cmd': 'kick'});
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'open') {
      FlutterForegroundTask.launchApp();
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}
