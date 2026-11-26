import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_ce/hive.dart';
import 'package:workmanager/workmanager.dart';

const String kJourneyReminderTask = 'acquire_english_journey_reminder';
const String _kDayKey = 'journey_reminder_day_v1';
const String _kTitleKey = 'journey_reminder_title_v1';
const String _kBodyKey = 'journey_reminder_body_v1';
const String _kNotifiedDayKey = 'journey_reminder_notified_day_v1';

/// Persist tomorrow's journey nudge and fire once via Workmanager.
Future<void> scheduleJourneyReminder({
  required DateTime day,
  required String title,
  required String body,
}) async {
  if (kIsWeb) return;
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  final String dayKey = _dayKey(day);
  final String shortTitle = title.trim().isEmpty ? '今日学习' : title.trim();
  final String shortBody = body.trim().isEmpty
      ? '点下一步，接着昨天继续学'
      : body.trim();
  try {
    if (!Hive.isBoxOpen('prefs')) {
      await Hive.openBox<String>('prefs');
    }
    final Box<String> box = Hive.box<String>('prefs');
    if (!_reminderEnabled(box)) return;
    await box.put(_kDayKey, dayKey);
    await box.put(_kTitleKey, shortTitle);
    await box.put(_kBodyKey, shortBody);

    final DateTime target = DateTime(day.year, day.month, day.day, 8);
    Duration delay = target.difference(DateTime.now());
    if (delay.inMinutes < 15) {
      delay = const Duration(minutes: 15);
    }
    await Workmanager().registerOneOffTask(
      kJourneyReminderTask,
      kJourneyReminderTask,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
  } catch (_) {}
}

/// Called from the shared Workmanager dispatcher.
Future<void> handleJourneyReminderBackgroundTask() async {
  try {
    if (!Hive.isBoxOpen('prefs')) {
      await Hive.openBox<String>('prefs');
    }
    final Box<String> box = Hive.box<String>('prefs');
    if (!_reminderEnabled(box)) return;
    final String? day = box.get(_kDayKey);
    if (day == null || day.isEmpty) return;
    if (box.get(_kNotifiedDayKey) == day) return;
    final String today = _dayKey(DateTime.now());
    // Fire on/after the planned day; skip if somehow early.
    if (day.compareTo(today) > 0) return;
    await _showJourneyNotification(
      title: box.get(_kTitleKey) ?? '今日学习',
      body: box.get(_kBodyKey) ?? '点下一步，接着昨天继续学',
    );
    await box.put(_kNotifiedDayKey, day);
  } catch (_) {}
}

bool _reminderEnabled(Box<String> box) {
  final String? raw = box.get('learning_settings_v1');
  if (raw == null || raw.isEmpty) return false;
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded['reminder'] == true;
    }
  } on FormatException {
    // Ignore corrupt settings — do not notify.
  }
  return false;
}

String _dayKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

Future<void> _showJourneyNotification({
  required String title,
  required String body,
}) async {
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) return;
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    settings: const InitializationSettings(android: androidInit),
  );
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'journey_reminder',
    '今日学习提醒',
    channelDescription: '提醒你接着昨天继续学',
  );
  await plugin.show(
    id: 4203,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(android: androidDetails),
  );
}
