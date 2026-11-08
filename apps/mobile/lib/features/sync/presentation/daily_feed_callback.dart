import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_ce/hive.dart';
import 'package:workmanager/workmanager.dart';

const String kDailyFeedTask = 'acquire_english_daily_feed';

@pragma('vm:entry-point')
void dailyFeedBackgroundDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? inputData) async {
    if (task != kDailyFeedTask && task != Workmanager.iOSBackgroundTask) {
      return true;
    }
    try {
      if (!Hive.isBoxOpen('prefs')) {
        await Hive.openBox<String>('prefs');
      }
      final Box<String> box = Hive.box<String>('prefs');
      await box.put(
        'daily_feed_bg_tick_v1',
        DateTime.now().toUtc().toIso8601String(),
      );
      await box.delete('daily_feed_synced_at_v1');
      await notifyDailyFeedIfEnabled(box);
    } catch (_) {}
    return true;
  });
}

Future<void> notifyDailyFeedIfEnabled(Box<String> box) async {
  final bool disabled =
      box.get('learning_preferences_v1')?.contains('"notify_daily_feed":false') ??
          false;
  if (disabled) {
    return;
  }
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    settings: const InitializationSettings(android: androidInit),
  );
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'daily_feed',
    '每日课程',
    channelDescription: '按学习偏好推送今日课程',
  );
  await plugin.show(
    id: 4101,
    title: 'AcquireEnglish',
    body: '今日课程已更新，打开 App 查看推荐。',
    notificationDetails: const NotificationDetails(android: androidDetails),
  );
}
