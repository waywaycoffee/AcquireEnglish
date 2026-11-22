import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/episode_study_progress.dart';

const String _kStoreKey = 'episode_study_progress_v1';

class EpisodeStudyProgressNotifier
    extends StateNotifier<Map<String, EpisodeStudyProgress>> {
  EpisodeStudyProgressNotifier() : super(const <String, EpisodeStudyProgress>{}) {
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_kStoreKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final Map<String, dynamic> map =
          jsonDecode(raw) as Map<String, dynamic>;
      final Map<String, EpisodeStudyProgress> next =
          <String, EpisodeStudyProgress>{};
      for (final MapEntry<String, dynamic> e in map.entries) {
        if (e.value is Map) {
          final EpisodeStudyProgress p = EpisodeStudyProgress.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          );
          if (p.episodeId.isNotEmpty) {
            next[p.episodeId] = p;
          }
        }
      }
      state = next;
    } catch (_) {}
  }

  Future<void> _persist() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> out = <String, dynamic>{
      for (final MapEntry<String, EpisodeStudyProgress> e in state.entries)
        e.key: e.value.toJson(),
    };
    await prefs.setString(_kStoreKey, jsonEncode(out));
  }

  EpisodeStudyProgress of(String episodeId) {
    return state[episodeId] ??
        EpisodeStudyProgress(episodeId: episodeId);
  }

  Future<void> upsert(
    EpisodeStudyProgress progress, {
    bool requireOutput = false,
  }) async {
    final EpisodeStudyProgress next = progress.recompute(
      requireOutput: requireOutput,
    );
    state = <String, EpisodeStudyProgress>{...state, next.episodeId: next};
    await _persist();
  }

  Future<void> markWatched(String episodeId, {bool requireOutput = false}) {
    final EpisodeStudyProgress cur = of(episodeId);
    return upsert(cur.copyWith(watched: true), requireOutput: requireOutput);
  }

  Future<void> setIntensiveCoverage(
    String episodeId,
    double coverage, {
    bool requireOutput = false,
  }) {
    final EpisodeStudyProgress cur = of(episodeId);
    return upsert(
      cur.copyWith(intensiveCoverage: coverage.clamp(0, 1)),
      requireOutput: requireOutput,
    );
  }

  Future<void> markOutputPassed(
    String episodeId, {
    bool requireOutput = false,
  }) {
    final EpisodeStudyProgress cur = of(episodeId);
    return upsert(
      cur.copyWith(outputPassed: true),
      requireOutput: requireOutput,
    );
  }

  Future<void> setDueClipCount(
    String episodeId,
    int count, {
    bool requireOutput = false,
  }) {
    final EpisodeStudyProgress cur = of(episodeId);
    return upsert(
      cur.copyWith(dueClipCount: count < 0 ? 0 : count),
      requireOutput: requireOutput,
    );
  }
}

final episodeStudyProgressProvider = StateNotifierProvider<
    EpisodeStudyProgressNotifier, Map<String, EpisodeStudyProgress>>(
  (Ref ref) => EpisodeStudyProgressNotifier(),
);

EpisodeStudyProgress episodeProgressOf(
  Map<String, EpisodeStudyProgress> map,
  String episodeId,
) {
  return map[episodeId] ?? EpisodeStudyProgress(episodeId: episodeId);
}
