import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../domain/journey_next_step.dart';
import '../domain/learning_recommendation.dart';

/// Session swap ids, week-long dislikes, and per-module difficulty nudges.
class JourneyFeedbackStore {
  JourneyFeedbackStore(this.account);

  final String account;

  Box<String>? get _prefs =>
      Hive.isBoxOpen('prefs') ? Hive.box<String>('prefs') : null;

  String get _key => 'journeyFeedback:${Uri.encodeComponent(account)}';

  Map<String, Object?> _read() {
    final String? raw = _prefs?.get(_key);
    if (raw == null) return <String, Object?>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Recover with an empty store.
    }
    return <String, Object?>{};
  }

  Future<void> _write(Map<String, Object?> next) async {
    await _prefs?.put(_key, jsonEncode(next));
  }

  Set<String> get sessionSwaps {
    final Object? raw = _read()['sessionSwaps'];
    if (raw is! List) return <String>{};
    return raw.whereType<String>().toSet();
  }

  Map<String, String> get dislikeUntil {
    final Object? raw = _read()['dislikeUntil'];
    if (raw is! Map) return <String, String>{};
    return <String, String>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  Map<LearnModule, int> get difficultyShifts {
    final Object? raw = _read()['difficultyShifts'];
    if (raw is! Map) return <LearnModule, int>{};
    final Map<LearnModule, int> out = <LearnModule, int>{};
    for (final LearnModule module in LearnModule.values) {
      final Object? value = raw[module.name];
      if (value is int) out[module] = value.clamp(-2, 2);
    }
    return out;
  }

  bool isHidden(String id, {DateTime? now}) {
    if (sessionSwaps.contains(id)) return true;
    final String? until = dislikeUntil[id];
    if (until == null) return false;
    final DateTime? day = DateTime.tryParse(until);
    if (day == null) return false;
    final DateTime today = now ?? DateTime.now();
    return !DateTime(today.year, today.month, today.day).isAfter(day);
  }

  Future<void> apply({
    required String id,
    required LearnModule module,
    required LearnFeedback feedback,
    DateTime? now,
  }) async {
    final LearnFeedbackEffect effect = effectFor(feedback);
    final Map<String, Object?> record = Map<String, Object?>.from(_read());
    if (effect.sessionOnly) {
      final Set<String> swaps = sessionSwaps..add(id);
      record['sessionSwaps'] = swaps.toList();
    }
    if (effect.demoteDays > 0) {
      final DateTime today = now ?? DateTime.now();
      final DateTime until = DateTime(
        today.year,
        today.month,
        today.day,
      ).add(Duration(days: effect.demoteDays - 1));
      final Map<String, String> map = Map<String, String>.from(dislikeUntil);
      map[id] = until.toIso8601String().substring(0, 10);
      record['dislikeUntil'] = map;
    }
    if (effect.difficultyShift != 0) {
      final Map<String, int> shifts = <String, int>{
        for (final MapEntry<LearnModule, int> entry
            in difficultyShifts.entries)
          entry.key.name: entry.value,
      };
      final int next =
          ((shifts[module.name] ?? 0) + effect.difficultyShift).clamp(-2, 2);
      shifts[module.name] = next;
      record['difficultyShifts'] = shifts;
    }
    await _write(record);
  }

  Future<void> clearSessionSwaps() async {
    final Map<String, Object?> record = Map<String, Object?>.from(_read());
    record.remove('sessionSwaps');
    await _write(record);
  }
}
