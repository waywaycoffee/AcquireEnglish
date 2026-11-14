import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'acquire_api_client.dart';

final Provider<ProgressSyncService> progressSyncServiceProvider =
    Provider<ProgressSyncService>((Ref ref) {
      return ProgressSyncService(ref.watch(acquireApiClientProvider));
    });

class ProgressSyncService {
  ProgressSyncService(this._api);

  final AcquireApiClient _api;
  DateTime? _lastPushAt;
  String? _lastKey;

  static const String _boxName = 'progress_lww_v1';

  Future<Box<dynamic>> _box() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<dynamic>(_boxName);
    }
    return Hive.openBox<dynamic>(_boxName);
  }

  Future<DateTime?> localUpdatedAt(String lessonId) async {
    final Box<dynamic> box = await _box();
    final Object? raw = box.get(lessonId);
    if (raw is! Map) {
      return null;
    }
    final Object? iso = raw['updatedAt'];
    if (iso is! String || iso.isEmpty) {
      return null;
    }
    return DateTime.tryParse(iso);
  }

  Future<void> rememberLocal({
    required String lessonId,
    required double positionSec,
    required DateTime updatedAt,
    bool completed = false,
  }) async {
    final Box<dynamic> box = await _box();
    await box.put(lessonId, <String, dynamic>{
      'positionSec': positionSec,
      'completed': completed,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    });
  }

  /// Prefer cloud progress when its [updatedAt] is strictly newer than local.
  /// Falls back to farther-position heuristic when local timestamp is missing.
  Future<AcquireProgressDto?> pickWinner({
    required String lessonId,
    required double localPositionSec,
    required AcquireProgressDto? remote,
  }) async {
    if (remote == null || remote.positionSec <= 1) {
      return null;
    }
    final DateTime? localAt = await localUpdatedAt(lessonId);
    if (localAt != null) {
      if (remote.updatedAt.toUtc().isAfter(localAt.toUtc())) {
        return remote;
      }
      return null;
    }
    final int localMs = (localPositionSec * 1000).round();
    final int cloudMs = (remote.positionSec * 1000).round();
    if (cloudMs > localMs + 1500) {
      return remote;
    }
    return null;
  }

  Future<void> pushThrottled({
    required String courseId,
    required String lessonId,
    required double positionSec,
    bool completed = false,
    Duration minInterval = const Duration(seconds: 2),
  }) async {
    final String key =
        '$courseId|$lessonId|${positionSec.round()}|$completed';
    final DateTime now = DateTime.now().toUtc();
    if (_lastKey == key &&
        _lastPushAt != null &&
        now.difference(_lastPushAt!) < minInterval) {
      return;
    }
    _lastKey = key;
    _lastPushAt = now;
    await rememberLocal(
      lessonId: lessonId,
      positionSec: positionSec,
      updatedAt: now,
      completed: completed,
    );
    try {
      final AcquireProgressDto saved = await _api.upsertProgress(
        courseId: courseId,
        lessonId: lessonId,
        positionSec: positionSec,
        completed: completed,
        clientUpdatedAt: now,
      );
      await rememberLocal(
        lessonId: lessonId,
        positionSec: saved.positionSec,
        updatedAt: saved.updatedAt.toUtc(),
        completed: saved.completed,
      );
    } catch (_) {
      // Offline / unauthenticated — ignore; local Hive still holds progress.
    }
  }

  Future<Map<String, AcquireProgressDto>> pullIndexed() async {
    try {
      final List<AcquireProgressDto> rows = await _api.listProgress();
      return <String, AcquireProgressDto>{
        for (final AcquireProgressDto row in rows) row.lessonId: row,
      };
    } catch (_) {
      return const <String, AcquireProgressDto>{};
    }
  }
}
