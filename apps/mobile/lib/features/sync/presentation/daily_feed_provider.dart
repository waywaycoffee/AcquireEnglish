import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../library/data/course_pack_mapper.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../data/acquire_api_client.dart';

const String _prefsKey = 'learning_preferences_v1';
const String _feedKey = 'daily_feed_v1';
const String _feedSyncedAtKey = 'daily_feed_synced_at_v1';

final NotifierProvider<LearningPreferencesNotifier, AcquirePreferencesDto>
learningPreferencesProvider =
    NotifierProvider<LearningPreferencesNotifier, AcquirePreferencesDto>(
      LearningPreferencesNotifier.new,
    );

final NotifierProvider<DailyFeedNotifier, List<LibraryCourseData>>
dailyFeedProvider =
    NotifierProvider<DailyFeedNotifier, List<LibraryCourseData>>(
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
}

class DailyFeedNotifier extends Notifier<List<LibraryCourseData>> {
  @override
  List<LibraryCourseData> build() {
    if (!Hive.isBoxOpen('prefs')) {
      return const <LibraryCourseData>[];
    }
    final String? raw = Hive.box<String>('prefs').get(_feedKey);
    if (raw == null || raw.isEmpty) {
      return const <LibraryCourseData>[];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(AcquireCourseDto.fromJson)
          .map(mapAcquireCourseToLibrary)
          .toList(growable: false);
    } catch (_) {
      return const <LibraryCourseData>[];
    }
  }

  Future<void> refresh({bool force = false}) async {
    if (!force && !_shouldRefresh()) {
      return;
    }
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final List<AcquireCourseDto> feed = await api.dailyFeed();
      final List<LibraryCourseData> mapped = feed
          .map(mapAcquireCourseToLibrary)
          .toList(growable: false);
      state = mapped;
      if (Hive.isBoxOpen('prefs')) {
        final Box<String> box = Hive.box<String>('prefs');
        await box.put(
          _feedKey,
          jsonEncode(
            feed
                .map(
                  (AcquireCourseDto c) => <String, dynamic>{
                    'id': c.id,
                    'title': c.title,
                    'titleZh': c.titleZh,
                    'description': c.description,
                    'coverUrl': c.coverUrl,
                    'level': c.level,
                    'tags': c.tags,
                    'lessons': c.lessons
                        .map(
                          (AcquireLessonDto l) => <String, dynamic>{
                            'id': l.id,
                            'title': l.title,
                            'index': l.index,
                            'durationSec': l.durationSec,
                            'videoUrl': l.videoUrl,
                            'subtitles': <String, dynamic>{
                              'en': l.subtitleEn,
                              'zh': l.subtitleZh,
                            },
                          },
                        )
                        .toList(),
                  },
                )
                .toList(),
          ),
        );
        await box.put(
          _feedSyncedAtKey,
          DateTime.now().toUtc().toIso8601String(),
        );
      }
      await ref.read(libraryCatalogProvider.notifier).mergeCloudCourses(mapped);
    } catch (_) {
      // Keep cached feed.
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
