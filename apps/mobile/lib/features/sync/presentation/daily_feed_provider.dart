import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../data/acquire_api_client.dart';

const String _prefsKey = 'learning_preferences_v1';
const String _feedKey = 'daily_feed_bili_v1';
const String _feedSyncedAtKey = 'daily_feed_synced_at_v1';

final NotifierProvider<LearningPreferencesNotifier, AcquirePreferencesDto>
learningPreferencesProvider =
    NotifierProvider<LearningPreferencesNotifier, AcquirePreferencesDto>(
      LearningPreferencesNotifier.new,
    );

final NotifierProvider<DailyFeedNotifier, List<AcquireDailyFeedItemDto>>
dailyFeedProvider =
    NotifierProvider<DailyFeedNotifier, List<AcquireDailyFeedItemDto>>(
      DailyFeedNotifier.new,
    );

class LearningPreferencesNotifier extends Notifier<AcquirePreferencesDto> {
  @override
  AcquirePreferencesDto build() {
    if (!Hive.isBoxOpen('prefs')) {
      return const AcquirePreferencesDto();
    }
    final String? raw = Hive.box<String>('prefs').get(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return const AcquirePreferencesDto();
    }
    try {
      return AcquirePreferencesDto.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AcquirePreferencesDto();
    }
  }

  Future<void> save(AcquirePreferencesDto prefs) async {
    state = prefs;
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(_prefsKey, jsonEncode(prefs.toJson()));
    }
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      state = await api.putPreferences(prefs);
      if (Hive.isBoxOpen('prefs')) {
        await Hive.box<String>(
          'prefs',
        ).put(_prefsKey, jsonEncode(state.toJson()));
      }
    } catch (_) {
      // Keep local prefs when offline.
    }
    await ref.read(dailyFeedProvider.notifier).refresh(force: true);
  }

  Future<void> pullRemote() async {
    try {
      final AcquirePreferencesDto remote = await ref
          .read(acquireApiClientProvider)
          .getPreferences();
      state = remote;
      if (Hive.isBoxOpen('prefs')) {
        await Hive.box<String>(
          'prefs',
        ).put(_prefsKey, jsonEncode(remote.toJson()));
      }
    } catch (_) {}
  }

  /// Update local cache from a PUT response without issuing another network call.
  Future<void> applyLocal(AcquirePreferencesDto prefs) async {
    state = prefs;
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(_prefsKey, jsonEncode(prefs.toJson()));
    }
  }
}

class DailyFeedNotifier extends Notifier<List<AcquireDailyFeedItemDto>> {
  @override
  List<AcquireDailyFeedItemDto> build() {
    if (!Hive.isBoxOpen('prefs')) {
      return const <AcquireDailyFeedItemDto>[];
    }
    final String? raw = Hive.box<String>('prefs').get(_feedKey);
    if (raw == null || raw.isEmpty) {
      return const <AcquireDailyFeedItemDto>[];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(AcquireDailyFeedItemDto.fromJson)
          .where(
            (AcquireDailyFeedItemDto item) =>
                item.bvid.isNotEmpty && item.watchUrl.isNotEmpty,
          )
          .toList(growable: false);
    } catch (_) {
      return const <AcquireDailyFeedItemDto>[];
    }
  }

  Future<void> refresh({bool force = false}) async {
    if (!force && !_shouldRefresh()) {
      return;
    }
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final List<AcquireDailyFeedItemDto> feed = await api.dailyFeed();
      state = feed;
      if (Hive.isBoxOpen('prefs')) {
        final Box<String> box = Hive.box<String>('prefs');
        await box.put(
          _feedKey,
          jsonEncode(
            feed
                .map((AcquireDailyFeedItemDto item) => item.toJson())
                .toList(growable: false),
          ),
        );
        await box.put(
          _feedSyncedAtKey,
          DateTime.now().toUtc().toIso8601String(),
        );
        // Drop legacy course-pack feed cache so it cannot reappear as「学习课程」.
        await box.delete('daily_feed_v1');
      }
    } catch (_) {
      // Keep cached recommendations when offline.
    }
  }

  bool _shouldRefresh() {
    if (!Hive.isBoxOpen('prefs')) {
      return true;
    }
    final String? raw = Hive.box<String>('prefs').get(_feedSyncedAtKey);
    if (raw == null) {
      return true;
    }
    final DateTime? at = DateTime.tryParse(raw);
    if (at == null) {
      return true;
    }
    return DateTime.now().toUtc().difference(at) > const Duration(hours: 20);
  }
}
