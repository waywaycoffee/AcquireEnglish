import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_ce/hive.dart';
import 'package:workmanager/workmanager.dart';

import 'subtitle_completion_queue.dart';

const String kSubtitleCompletionTask = 'acquire_english_subtitle_completion';
const String kSubtitleCompletionNudgeKey = 'subtitle_completion_nudge_v1';

/// Called from the shared Workmanager dispatcher when the nudge task fires.
Future<void> handleSubtitleCompletionBackgroundTask() async {
  try {
    if (!Hive.isBoxOpen('prefs')) {
      await Hive.openBox<String>('prefs');
    }
    final Box<String> box = Hive.box<String>('prefs');
    await box.put(
      kSubtitleCompletionNudgeKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    // Ask the next app resume / foreground to start FGS drain immediately.
    await box.put('subtitle_completion_auto_run_v1', '1');
    final bool pending = await SubtitleCompletionQueue().hasPendingWork();
    if (pending) {
      await notifySubtitleCompletionPending();
    }
  } catch (_) {}
}

Future<void> notifySubtitleCompletionPending() async {
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    settings: const InitializationSettings(android: androidInit),
  );
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'subtitle_completion',
    '字幕补全',
    channelDescription: '充电空闲时自动补全中英字幕',
  );
  await plugin.show(
    id: 4102,
    title: '爱快英语',
    body: '有课程待补中英字幕。充电空闲时会自动继续；打开 App 可立即开始。',
    notificationDetails: const NotificationDetails(android: androidDetails),
  );
}

Future<void> scheduleSubtitleCompletionNudge() async {
  if (kIsWeb) {
    return;
  }
  if (!(Platform.isAndroid || Platform.isIOS)) {
    return;
  }
  try {
    await Workmanager().registerOneOffTask(
      kSubtitleCompletionTask,
      kSubtitleCompletionTask,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: true,
        requiresCharging: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(minutes: 2),
    );
  } catch (_) {}
}
