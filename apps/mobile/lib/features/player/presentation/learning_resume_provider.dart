import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';

final currentLearningKindProvider =
    NotifierProvider<CurrentLearningKind, String>(CurrentLearningKind.new);

class CurrentLearningKind extends Notifier<String> {
  @override
  String build() => Hive.isBoxOpen('prefs')
      ? Hive.box<String>(
          'prefs',
        ).get('current_learning_kind', defaultValue: 'video')!
      : 'video';
  void record(String kind) {
    state = kind;
    if (Hive.isBoxOpen('prefs'))
      unawaited(Hive.box<String>('prefs').put('current_learning_kind', kind));
  }
}

const String _lastLearningEpisodeKey = 'last_learning_episode_v1';

final NotifierProvider<LastLearningEpisodeNotifier, String?>
lastLearningEpisodeProvider =
    NotifierProvider<LastLearningEpisodeNotifier, String?>(
      LastLearningEpisodeNotifier.new,
    );

class LastLearningEpisodeNotifier extends Notifier<String?> {
  @override
  String? build() => Hive.isBoxOpen('prefs')
      ? Hive.box<String>('prefs').get(_lastLearningEpisodeKey)
      : null;

  void record(String episodeId) {
    if (episodeId.trim().isEmpty) return;
    ref.read(currentLearningKindProvider.notifier).record('video');
    if (Hive.isBoxOpen('prefs'))
      unawaited(
        Hive.box<String>('prefs').put('current_learning_kind', 'video'),
      );
    if (state == episodeId) return;
    state = episodeId;
    if (Hive.isBoxOpen('prefs')) {
      unawaited(
        Hive.box<String>('prefs').put(_lastLearningEpisodeKey, episodeId),
      );
    }
  }
}

class ContinueLearningTarget {
  const ContinueLearningTarget({required this.course, required this.episode});

  final LibraryCourseData course;
  final LibraryEpisodeItem episode;
}

/// Resume target for「接着看第 N 集」.
///
/// Never invent "first episode of first course" — that erased real progress
/// and made seriesContinueTarget treat the user as not yet pursuing.
final Provider<ContinueLearningTarget?> continueLearningTargetProvider =
    Provider<ContinueLearningTarget?>((Ref ref) {
      final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
      final String? lastEpisode = ref.watch(lastLearningEpisodeProvider);

      ContinueLearningTarget? findEpisode(String episodeId) {
        for (final LibraryCourseData course in courses) {
          for (final LibraryEpisodeItem episode in course.episodes) {
            if (episode.id == episodeId) {
              return ContinueLearningTarget(course: course, episode: episode);
            }
          }
        }
        return null;
      }

      if (lastEpisode != null && lastEpisode.isNotEmpty) {
        final ContinueLearningTarget? hit = findEpisode(lastEpisode);
        if (hit != null) return hit;
      }

      // Fallback: most recently studied unfinished episode (by course stamp).
      LibraryCourseData? bestCourse;
      LibraryEpisodeItem? bestEpisode;
      int bestStamp = -1;
      for (final LibraryCourseData course in courses) {
        final int stamp = course.lastStudiedAtMs ?? 0;
        for (final LibraryEpisodeItem episode in course.episodes) {
          if (episode.videoMissing) continue;
          if (episode.completed && episode.progressPercent >= 100) continue;
          if (episode.progressPercent <= 0 && !episode.completed) {
            // Prefer in-progress; allow completed=false with 0% only if this
            // course was studied recently and we need *next* after a finished
            // prior episode — handled below via completedEpisodes.
            continue;
          }
          if (stamp >= bestStamp) {
            bestStamp = stamp;
            bestCourse = course;
            bestEpisode = episode;
          }
        }
      }
      if (bestCourse != null && bestEpisode != null) {
        return ContinueLearningTarget(course: bestCourse, episode: bestEpisode);
      }

      // Last finished episode in the most recently studied multi-ep course →
      // caller will advance to next via seriesContinueTarget.
      LibraryCourseData? recentSeries;
      int recentStamp = -1;
      for (final LibraryCourseData course in courses) {
        if (course.episodes.length < 2) continue;
        final int stamp = course.lastStudiedAtMs ?? 0;
        if (stamp <= recentStamp) continue;
        final bool anyDone = course.episodes.any(
          (LibraryEpisodeItem e) => e.completed || e.progressPercent > 0,
        );
        if (!anyDone) continue;
        recentStamp = stamp;
        recentSeries = course;
      }
      if (recentSeries != null) {
        LibraryEpisodeItem? lastTouched;
        for (final LibraryEpisodeItem episode in recentSeries.episodes) {
          if (episode.completed || episode.progressPercent > 0) {
            lastTouched = episode;
          }
        }
        if (lastTouched != null) {
          return ContinueLearningTarget(
            course: recentSeries,
            episode: lastTouched,
          );
        }
      }
      return null;
    });
