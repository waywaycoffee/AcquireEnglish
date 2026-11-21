import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_ce/hive.dart';

/// Persist today's deskmate nudge and fire at most one local reminder per day.
Future<void> rememberDeskmateNudge(Map<String, dynamic>? nudge) async {
  if (nudge == null) return;
  final String? body = nudge['body'] as String?;
  final String? day = nudge['day'] as String?;
  if (body == null || body.isEmpty || day == null) return;
  try {
    if (!Hive.isBoxOpen('prefs')) {
      await Hive.openBox<String>('prefs');
    }
    final Box<String> box = Hive.box<String>('prefs');
    await box.put('deskmate_nudge_day_v1', day);
    await box.put('deskmate_nudge_body_v1', body);
    await box.put(
      'deskmate_nudge_title_v1',
      (nudge['title'] as String?) ?? '同桌学习进展',
    );
    final String? shown = box.get('deskmate_nudge_notified_day_v1');
    if (shown == day) return;
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) return;
    await _showDeskmateNotification(
      title: (nudge['title'] as String?) ?? '同桌学习进展',
      body: body,
    );
    await box.put('deskmate_nudge_notified_day_v1', day);
  } catch (_) {}
}

Future<void> _showDeskmateNotification({
  required String title,
  required String body,
}) async {
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    settings: const InitializationSettings(android: androidInit),
  );
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'deskmate_progress',
    '同桌进展',
    channelDescription: '提醒你同桌今天的学习进度，鼓励你追上他',
  );
  await plugin.show(
    id: 4202,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(android: androidDetails),
  );
}
