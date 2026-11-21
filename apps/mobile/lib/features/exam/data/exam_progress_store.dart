import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../sync/data/schedule_device_cloud_sync.dart';

const String kExamProgressKey = 'exam_progress_v1';

class ExamProgress {
  const ExamProgress({
    this.byFamily = const <String, Map<String, int>>{},
  });

  factory ExamProgress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ExamProgress();
    final Map<String, Map<String, int>> out = <String, Map<String, int>>{};
    json.forEach((String key, dynamic value) {
      if (value is Map) {
        out[key] = value.map(
          (dynamic k, dynamic v) => MapEntry<String, int>('$k', (v as num?)?.toInt() ?? 0),
        );
      }
    });
    return ExamProgress(byFamily: out);
  }

  /// familyId -> {practiced, correct, wrong, mocks}
  final Map<String, Map<String, int>> byFamily;

  Map<String, dynamic> toJson() => byFamily;

  Map<String, int> forFamily(String familyId) =>
      byFamily[familyId] ??
      const <String, int>{
        'practiced': 0,
        'correct': 0,
        'wrong': 0,
        'mocks': 0,
      };
}

class ExamProgressNotifier extends Notifier<ExamProgress> {
  @override
  ExamProgress build() {
    if (!Hive.isBoxOpen('prefs')) return const ExamProgress();
    final String? raw = Hive.box<String>('prefs').get(kExamProgressKey);
    if (raw == null || raw.isEmpty) return const ExamProgress();
    try {
      return ExamProgress.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const ExamProgress();
    }
  }

  Future<void> _persist(ExamProgress next) async {
    state = next;
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(kExamProgressKey, jsonEncode(next.toJson()));
    scheduleDeviceCloudSync(key: 'settings');
  }

  Future<void> recordPractice({
    required String familyId,
    required int correct,
    required int wrong,
    bool mock = false,
  }) async {
    if (familyId.isEmpty) return;
    final Map<String, Map<String, int>> map =
        Map<String, Map<String, int>>.from(state.byFamily);
    final Map<String, int> cur = Map<String, int>.from(state.forFamily(familyId));
    cur['practiced'] = (cur['practiced'] ?? 0) + correct + wrong;
    cur['correct'] = (cur['correct'] ?? 0) + correct;
    cur['wrong'] = (cur['wrong'] ?? 0) + wrong;
    if (mock) cur['mocks'] = (cur['mocks'] ?? 0) + 1;
    map[familyId] = cur;
    await _persist(ExamProgress(byFamily: map));
  }
}

final NotifierProvider<ExamProgressNotifier, ExamProgress> examProgressProvider =
    NotifierProvider<ExamProgressNotifier, ExamProgress>(ExamProgressNotifier.new);
