import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> pushThrottled({
    required String courseId,
    required String lessonId,
    required double positionSec,
    bool completed = false,
    Duration minInterval = const Duration(seconds: 2),
  }) async {
    final String key =
        '$courseId|$lessonId|${positionSec.round()}|$completed';
    final DateTime now = DateTime.now();
    if (_lastKey == key &&
        _lastPushAt != null &&
        now.difference(_lastPushAt!) < minInterval) {
      return;
    }
    _lastKey = key;
    _lastPushAt = now;
    try {
      await _api.upsertProgress(
        courseId: courseId,
        lessonId: lessonId,
        positionSec: positionSec,
        completed: completed,
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
