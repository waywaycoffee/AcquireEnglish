import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

const String _deviceIdKey = 'acquire_device_id_v1';

String _newDeviceId() {
  final Random rng = Random.secure();
  final String hex = List<String>.generate(
    16,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'ae-$hex';
}

/// Stable per-install device id for the 4-terminal login cap.
Future<String> resolveAcquireDeviceId() async {
  if (!Hive.isBoxOpen('prefs')) {
    return 'temp-${_newDeviceId()}';
  }
  final Box<String> box = Hive.box<String>('prefs');
  final String? existing = box.get(_deviceIdKey);
  if (existing != null && existing.trim().isNotEmpty) {
    return existing.trim();
  }
  final String created = _newDeviceId();
  await box.put(_deviceIdKey, created);
  return created;
}

String acquireDeviceLabel() {
  if (kIsWeb) {
    return 'Web';
  }
  try {
    final String raw =
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim();
    return raw.length <= 120 ? raw : raw.substring(0, 120);
  } catch (_) {
    return Platform.operatingSystem;
  }
}
