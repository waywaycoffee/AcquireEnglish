import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:workmanager/workmanager.dart';

import '../import_course/data/netdisk_drama_reservation.dart';
import '../subtitle_completion/subtitle_completion_background.dart';
import 'idle_job_queue.dart';

const String kIdleJobsTask = 'acquire_english_idle_jobs';

const String kNetdiskDramaIdleTask = 'acquire_english_netdisk_drama_idle';

/// Schedule / refresh idle Workmanager tasks (charging + battery not low).
Future<void> scheduleIdleJobs() async {
  if (kIsWeb) return;
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  if (!idleJobsEnabled()) return;
  try {
    await Workmanager().registerOneOffTask(
      kIdleJobsTask,
      kIdleJobsTask,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresCharging: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      initialDelay: const Duration(minutes: 3),
    );
    await Workmanager().registerPeriodicTask(
      '${kIdleJobsTask}_periodic',
      kIdleJobsTask,
      frequency: const Duration(hours: 6),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresCharging: true,
      ),
    );
    // Drama netdisk prep: Wi‑Fi / network enough (no charging), so reserved
    // episodes can download while the phone is idle but unplugged.
    final bool hasDrama = IdleJobQueue.shared.pending.any(
      (IdleJob j) => j.kind == IdleJobKind.netdiskDrama,
    );
    if (hasDrama) {
      await Workmanager().registerOneOffTask(
        kNetdiskDramaIdleTask,
        kIdleJobsTask,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        initialDelay: const Duration(minutes: 1),
      );
      await Workmanager().registerPeriodicTask(
        '${kNetdiskDramaIdleTask}_periodic',
        kIdleJobsTask,
        frequency: const Duration(hours: 1),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );
    }
  } catch (_) {}
}

Future<void> cancelIdleJobsSchedule() async {
  if (kIsWeb) return;
  try {
    await Workmanager().cancelByUniqueName(kIdleJobsTask);
    await Workmanager().cancelByUniqueName('${kIdleJobsTask}_periodic');
  } catch (_) {}
}

Future<void> setIdleWakeFlag(bool value) async {
  if (!Hive.isBoxOpen('prefs')) {
    await Hive.openBox<String>('prefs');
  }
  await Hive.box<String>('prefs').put(kIdleJobsWakeKey, value ? '1' : '0');
}

Future<bool> consumeIdleWakeFlag() async {
  if (!Hive.isBoxOpen('prefs')) {
    try {
      await Hive.openBox<String>('prefs');
    } catch (_) {
      return false;
    }
  }
  final Box<String> box = Hive.box<String>('prefs');
  final String? raw = box.get(kIdleJobsWakeKey);
  if (raw == '1') {
    await box.put(kIdleJobsWakeKey, '0');
    return true;
  }
  return false;
}

/// Called from the shared Workmanager dispatcher.
Future<void> handleIdleJobsBackgroundTask() async {
  try {
    if (!Hive.isBoxOpen('prefs')) {
      await Hive.openBox<String>('prefs');
    }
    if (!idleJobsEnabled()) return;
    // Netdisk drama files can download headless (Dio + Documents); catalog
    // path is rebound on next app resume via findCachedNetdiskMedia.
    final IdleJob? drama = IdleJobQueue.shared.pending
        .where((IdleJob j) => j.kind == IdleJobKind.netdiskDrama)
        .firstOrNull;
    if (drama != null) {
      await drainOneNetdiskDramaReservation(job: drama);
      if (IdleJobQueue.shared.pending.any(
        (IdleJob j) => j.kind == IdleJobKind.netdiskDrama,
      )) {
        await scheduleIdleJobs();
      }
    }
    // Other idle kinds need the Flutter UI isolate (ASR FGS / enrich / sync).
    await setIdleWakeFlag(true);
    await scheduleSubtitleCompletionNudge();
    if (IdleJobQueue.shared.pending.isNotEmpty) {
      await notifySubtitleCompletionPending();
    }
  } catch (_) {}
}
