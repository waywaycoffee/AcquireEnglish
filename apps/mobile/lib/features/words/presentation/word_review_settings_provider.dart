import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../domain/word_review_settings.dart';

const String kWordReviewSettingsKey = 'word_review_prefs_v1';

class WordReviewSettingsNotifier extends Notifier<WordReviewSettings> {
  @override
  WordReviewSettings build() => _load();

  WordReviewSettings _load() {
    if (!Hive.isBoxOpen('prefs')) {
      return WordReviewSettings.defaults;
    }
    final String? raw = Hive.box<String>('prefs').get(kWordReviewSettingsKey);
    if (raw == null || raw.trim().isEmpty) {
      return WordReviewSettings.defaults;
    }
    try {
      return WordReviewSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map<dynamic, dynamic>),
      );
    } catch (_) {
      return WordReviewSettings.defaults;
    }
  }

  Future<void> _persist(WordReviewSettings next) async {
    state = next;
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    await Hive.box<String>('prefs').put(
      kWordReviewSettingsKey,
      jsonEncode(next.toJson()),
    );
  }

  Future<void> update(WordReviewSettings next) => _persist(next);

  Future<void> setDailyNewLimit(int value) =>
      _persist(state.copyWith(dailyNewLimit: value));

  Future<void> setDailyReviewLimit(int value) =>
      _persist(state.copyWith(dailyReviewLimit: value));

  Future<void> setModeEnabled(WordPracticeMode mode, {required bool enabled}) {
    final Set<WordPracticeMode> next = state.enabledModes.toSet();
    if (enabled) {
      next.add(mode);
    } else {
      next.remove(mode);
    }
    if (next.isEmpty) {
      next.add(WordPracticeMode.recognize);
    }
    return _persist(
      state.copyWith(
        enabledModes: WordPracticeMode.values
            .where(next.contains)
            .toList(growable: false),
      ),
    );
  }
}

final NotifierProvider<WordReviewSettingsNotifier, WordReviewSettings>
wordReviewSettingsProvider =
    NotifierProvider<WordReviewSettingsNotifier, WordReviewSettings>(
      WordReviewSettingsNotifier.new,
    );
