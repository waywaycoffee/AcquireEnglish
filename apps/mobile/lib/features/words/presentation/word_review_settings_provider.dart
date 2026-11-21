import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../daily_review/presentation/daily_review_provider.dart';
import '../../sync/data/schedule_device_cloud_sync.dart';
import '../domain/word_review_settings.dart';

const String kWordReviewSettingsKey = 'word_review_prefs_v1';

class WordReviewSettingsNotifier extends Notifier<WordReviewSettings> {
  @override
  WordReviewSettings build() {
    final WordReviewSettings settings = _load();
    // Align FSRS new quota with the words-plan setting on boot.
    Future<void>.microtask(() {
      try {
        unawaited(
          ref
              .read(dailyReviewProvider.notifier)
              .syncNewLimitFromWordSettings(settings.dailyNewLimit),
        );
      } catch (_) {}
    });
    return settings;
  }

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

  Future<void> _persist(
    WordReviewSettings next, {
    bool scheduleSync = true,
  }) async {
    state = next;
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    await Hive.box<String>('prefs').put(
      kWordReviewSettingsKey,
      jsonEncode(next.toJson()),
    );
    if (scheduleSync) scheduleDeviceCloudSync(key: 'settings');
  }

  Future<void> update(WordReviewSettings next) async {
    await _persist(next);
    await ref
        .read(dailyReviewProvider.notifier)
        .syncNewLimitFromWordSettings(next.dailyNewLimit);
  }

  Future<void> setDailyNewLimit(int value) async {
    await _persist(state.copyWith(dailyNewLimit: value));
    await ref
        .read(dailyReviewProvider.notifier)
        .syncNewLimitFromWordSettings(value);
  }

  Future<void> setDailyReviewLimit(int value) =>
      _persist(state.copyWith(dailyReviewLimit: value));

  Future<void> replaceFromCloud(WordReviewSettings settings) =>
      _persist(settings, scheduleSync: false);

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
