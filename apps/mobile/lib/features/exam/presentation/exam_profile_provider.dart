import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../sync/data/schedule_device_cloud_sync.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_registry.dart';

const String kExamProfileKey = 'exam_profile_v1';

class ExamProfileNotifier extends Notifier<ExamProfile> {
  @override
  ExamProfile build() {
    if (!Hive.isBoxOpen('prefs')) return const ExamProfile();
    final String? raw = Hive.box<String>('prefs').get(kExamProfileKey);
    if (raw == null || raw.isEmpty) return const ExamProfile();
    try {
      return ExamProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const ExamProfile();
    }
  }

  Future<void> _persist(ExamProfile next) async {
    state = next;
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(kExamProfileKey, jsonEncode(next.toJson()));
    scheduleDeviceCloudSync(key: 'settings');
  }

  Future<void> setMode(StudyMode mode) async {
    await _persist(state.copyWith(mode: mode));
  }

  Future<void> setFamily(String familyId, {String? targetScore}) async {
    final ExamFamily? family = examFamilyById(familyId);
    if (family == null) return;
    await _persist(
      state.copyWith(
        mode: StudyMode.exam,
        familyId: familyId,
        targetScore: targetScore,
        clearTargetScore: targetScore == null,
      ),
    );
  }

  Future<void> setAcquisition() async {
    await _persist(
      state.copyWith(
        mode: StudyMode.acquisition,
        clearFamily: true,
        clearTargetScore: true,
      ),
    );
  }

  Future<void> replaceFromCloud(ExamProfile profile) async {
    state = profile;
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>(
      'prefs',
    ).put(kExamProfileKey, jsonEncode(profile.toJson()));
  }
}

final NotifierProvider<ExamProfileNotifier, ExamProfile> examProfileProvider =
    NotifierProvider<ExamProfileNotifier, ExamProfile>(ExamProfileNotifier.new);
