import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../library/domain/homepage_recommended_bvids.dart';
import '../../words/presentation/learner_level_provider.dart';
import '../data/acquire_api_client.dart';

const String _prefsKey = 'learning_preferences_v1';
const String _feedKey = 'daily_feed_bili_v2';
const String _feedSyncedAtKey = 'daily_feed_synced_at_v2';

String _localDay(DateTime time) =>
    time.toLocal().toIso8601String().split('T').first;

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

/// BVids currently in the homepage daily recommendation pool.
///
/// Video-page rails should exclude these so the same clip is not recommended
/// twice (home「推荐视频」 + library B站/全英可逛).
final Provider<Set<String>> homepageRecommendedBvidsProvider =
    Provider<Set<String>>((Ref ref) {
  return homepageRecommendedBvidsFromFeed(ref.watch(dailyFeedProvider));
});

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

  Future<void> save(
    AcquirePreferencesDto prefs, {
    bool awaitCloud = true,
    bool refreshFeed = true,
  }) async {
    state = prefs;
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>(
        'prefs',
      ).put(_prefsKey, jsonEncode(prefs.toJson()));
    }
    Future<void> pushCloud() async {
      try {
        final AcquireApiClient api = ref.read(acquireApiClientProvider);
        final AcquirePreferencesDto remote = await api.putPreferences(prefs);
        state = remote;
        if (Hive.isBoxOpen('prefs')) {
          await Hive.box<String>(
            'prefs',
          ).put(_prefsKey, jsonEncode(state.toJson()));
        }
      } catch (_) {
        // Keep local prefs when offline.
      }
    }

    if (awaitCloud) {
      await pushCloud();
    } else {
      // Onboarding / first-open must not block UI on network.
      // ignore: unawaited_futures
      pushCloud();
    }
    if (!refreshFeed) {
      return;
    }
    final Future<void> feed =
        ref.read(dailyFeedProvider.notifier).refresh(force: true);
    if (awaitCloud) {
      await feed;
    } else {
      // ignore: unawaited_futures
      feed;
    }
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
      await Hive.box<String>(
        'prefs',
      ).put(_prefsKey, jsonEncode(prefs.toJson()));
    }
  }
}

class DailyFeedNotifier extends Notifier<List<AcquireDailyFeedItemDto>> {
  String get _account =>
      ref.read(authSessionProvider).email.trim().toLowerCase();

  @override
  List<AcquireDailyFeedItemDto> build() {
    ref.watch(
      authSessionProvider.select((AuthSessionState auth) => auth.email),
    );
    if (!Hive.isBoxOpen('prefs')) {
      return const <AcquireDailyFeedItemDto>[];
    }
    final String? raw = Hive.box<String>('prefs').get('$_feedKey:$_account');
    if (raw == null || raw.isEmpty) {
      return const <AcquireDailyFeedItemDto>[];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(AcquireDailyFeedItemDto.fromJson)
          .where(_isUsableRecommendation)
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
      final String account = _account;
      final String day = _localDay(DateTime.now());
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final String prefsLevel =
          ref.read(learningPreferencesProvider).level.trim();
      final String adaptive = ref.read(adaptiveLearnerCefrProvider).trim();
      // Prefer live adaptive CEFR so feed keywords stay near i+1.
      final String level =
          adaptive.isNotEmpty ? adaptive : (prefsLevel.isNotEmpty ? prefsLevel : 'A2');
      final List<AcquireDailyFeedItemDto> feed = await api.dailyFeed(
        date: day,
        level: level,
      );
      if (_account != account) return;
      final List<AcquireDailyFeedItemDto> usable =
          feed.where(_isUsableRecommendation).toList(growable: false);
      state = usable;
      if (Hive.isBoxOpen('prefs')) {
        final Box<String> box = Hive.box<String>('prefs');
        await box.put(
          '$_feedKey:$account',
          jsonEncode(
            usable
                .map((AcquireDailyFeedItemDto item) => item.toJson())
                .toList(growable: false),
          ),
        );
        if (usable.isNotEmpty) {
          await box.put('$_feedSyncedAtKey:$account', day);
        }
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
    final String? day = Hive.box<String>(
      'prefs',
    ).get('$_feedSyncedAtKey:$_account');
    return day != _localDay(DateTime.now());
  }
}

/// Keep interest + followed recommendations; API already prefers English samples.
bool _isUsableRecommendation(AcquireDailyFeedItemDto item) =>
    item.bvid.isNotEmpty && item.watchUrl.isNotEmpty;
