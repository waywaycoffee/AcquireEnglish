import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'daily_feed_callback.dart';

Future<void> registerDailyFeedBackground() async {
  if (kIsWeb) {
    return;
  }
  if (!(Platform.isAndroid || Platform.isIOS)) {
    return;
  }
  try {
    await Workmanager().initialize(dailyFeedBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      kDailyFeedTask,
      kDailyFeedTask,
      frequency: const Duration(hours: 24),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (_) {
    // Plugin may be unavailable on some desktops / emulators.
  }
}
