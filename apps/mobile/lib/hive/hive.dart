import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'hive_registrar.g.dart';

/// Hive `Box` loads the whole file into memory. A bloated prefs.hive (rewrites
/// of large JSON without compact) OOMs cold start — quarantine and recreate.
const int kPrefsHiveMaxBytes = 80 * 1024 * 1024;

Future<void> initHive() async {
  if (!kIsWeb) {
    final Directory dir = await getApplicationSupportDirectory();
    final String path = dir.path;
    await _quarantineOversizedPrefs(dir);
    Hive
      ..init(path)
      ..registerAdapters();
  }
  final Box<String> prefs = await Hive.openBox<String>('prefs');
  // Compact once if the on-disk file grew past a soft threshold after open.
  if (!kIsWeb) {
    try {
      final File hiveFile = File(
        '${(await getApplicationSupportDirectory()).path}/prefs.hive',
      );
      if (hiveFile.existsSync() &&
          hiveFile.lengthSync() > 16 * 1024 * 1024) {
        await prefs.compact();
      }
    } catch (_) {}
  }
}

Future<void> _quarantineOversizedPrefs(Directory dir) async {
  try {
    final File hive = File('${dir.path}/prefs.hive');
    if (!hive.existsSync()) return;
    final int size = hive.lengthSync();
    if (size <= kPrefsHiveMaxBytes) return;
    final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final File bak = File('${dir.path}/prefs.hive.oom.bak.$stamp');
    if (bak.existsSync()) bak.deleteSync();
    hive.renameSync(bak.path);
    final File lock = File('${dir.path}/prefs.lock');
    if (lock.existsSync()) lock.deleteSync();
    debugPrint(
      'Quarantined oversized prefs.hive '
      '(${(size / (1024 * 1024)).toStringAsFixed(1)} MB) → ${bak.path}',
    );
  } catch (e) {
    debugPrint('prefs.hive quarantine failed: $e');
  }
}
