import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../domain/course_plan.dart';

const String kCoursePlansKey = 'course_plans_v1';
const String kActiveCourseIdKey = 'course_plans_active_id_v1';
const String kTodayPathDoneKeyPrefix = 'today_path_done_v1:';

class CoursePlanStore {
  const CoursePlanStore();

  List<CoursePlan> loadAll() {
    if (!Hive.isBoxOpen('prefs')) return const <CoursePlan>[];
    final String? raw = Hive.box<String>('prefs').get(kCoursePlansKey);
    if (raw == null || raw.trim().isEmpty) return const <CoursePlan>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <CoursePlan>[];
      return decoded
          .map(
            (dynamic e) =>
                CoursePlan.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);
    } catch (_) {
      return const <CoursePlan>[];
    }
  }

  Future<void> saveAll(List<CoursePlan> plans) async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
          kCoursePlansKey,
          jsonEncode(plans.map((CoursePlan p) => p.toJson()).toList()),
        );
  }

  String? loadActiveCourseId() {
    if (!Hive.isBoxOpen('prefs')) return null;
    final String? id = Hive.box<String>('prefs').get(kActiveCourseIdKey);
    if (id == null || id.trim().isEmpty) return null;
    return id;
  }

  Future<void> saveActiveCourseId(String? id) async {
    if (!Hive.isBoxOpen('prefs')) return;
    if (id == null || id.isEmpty) {
      await Hive.box<String>('prefs').delete(kActiveCourseIdKey);
    } else {
      await Hive.box<String>('prefs').put(kActiveCourseIdKey, id);
    }
  }

  Set<String> loadDoneTaskIds(String dayKey) {
    if (!Hive.isBoxOpen('prefs')) return <String>{};
    final String? raw =
        Hive.box<String>('prefs').get('$kTodayPathDoneKeyPrefix$dayKey');
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.map((dynamic e) => '$e').toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> saveDoneTaskIds(String dayKey, Set<String> ids) async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
          '$kTodayPathDoneKeyPrefix$dayKey',
          jsonEncode(ids.toList()),
        );
  }
}
