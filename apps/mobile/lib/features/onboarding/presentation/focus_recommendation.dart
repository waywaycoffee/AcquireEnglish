import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../reading/domain/reading_doc.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart'
    show learningPreferencesProvider;
import '../../words/domain/syllabus_book.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../domain/onboarding_profile.dart';
import 'onboarding_provider.dart';

class FocusRecommendation {
  const FocusRecommendation({
    required this.focus,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.startLabel,
  });

  final LearningFocus focus;
  final String title;
  final String subtitle;
  final String route;
  final String startLabel;
}

const Map<String, List<String>> _topicKeywords = <String, List<String>>{
  'travel': <String>['travel', 'city', 'hotel', '旅行', '旅游'],
  'drama': <String>['film', 'movie', '影视', '电影'],
  'games': <String>['game', '游戏'],
  'campus': <String>['campus', 'school', 'library', '校园', '学校'],
  'business': <String>['business', 'workplace', '职场', '商务'],
  'tech': <String>['tech', 'robot', 'computer', '科技', '编程'],
  'daily': <String>['daily', 'morning', '日常'],
};

int _matchScore(
  String title,
  String contentLevel,
  String level,
  List<String> interests,
) {
  final String text = title.toLowerCase();
  final bool topicMatch = interests.any(
    (String interest) => _topicKeywords[interest]?.any(text.contains) ?? false,
  );
  return (topicMatch ? 2 : 0) +
      (contentLevel.trim().toUpperCase() == level.toUpperCase() ? 3 : 0);
}

T? _bestMatch<T>(Iterable<T> items, int Function(T) score) {
  T? best;
  int bestScore = -1;
  for (final T item in items) {
    final int rank = score(item);
    if (rank > bestScore) {
      best = item;
      bestScore = rank;
    }
  }
  return best;
}

FocusRecommendation buildFocusRecommendation({
  required OnboardingProfile profile,
  required AcquirePreferencesDto prefs,
  required List<LibraryCourseData> courses,
  required List<ReadingDoc> readingDocs,
  required SyllabusBook? activeBook,
}) {
  final LearningFocus focus =
      focusById(profile.focusId ?? focusIdFromTags(prefs.tags) ?? '') ??
      kLearningFocuses.first;
  final String level = profile.abilityId == null
      ? prefs.level
      : profile.resolvedLevel;
  final List<String> interests = profile.interestIds.isNotEmpty
      ? profile.interestIds
      : prefs.tags;
  final List<String> preferredTopics = interests.any(_topicKeywords.containsKey)
      ? interests
      : switch (profile.ageBandId) {
          'primary' ||
          'junior' ||
          'senior' ||
          'college' => const <String>['campus'],
          'adult' => const <String>['business'],
          _ => const <String>[],
        };

  FocusRecommendation recommendation(
    String title,
    String subtitle,
    String route,
  ) => FocusRecommendation(
    focus: focus,
    title: title,
    subtitle: subtitle,
    route: route,
    startLabel: focus.startLabel,
  );

  switch (focus.id) {
    case 'video':
      final LibraryCourseData? course = _bestMatch(
        courses.where(
          (LibraryCourseData item) => item.episodes.any(
            (LibraryEpisodeItem episode) => !episode.videoMissing,
          ),
        ),
        (LibraryCourseData item) => _matchScore(
          '${item.title} ${item.category}',
          item.level,
          level,
          preferredTopics,
        ),
      );
      if (course == null) {
        return recommendation('选择一段视频', '从课程库选择或导入视频。', focus.route);
      }
      final LibraryEpisodeItem episode = course.episodes.firstWhere(
        (LibraryEpisodeItem item) => !item.completed && !item.videoMissing,
        orElse: () => course.episodes.firstWhere(
          (LibraryEpisodeItem item) => !item.videoMissing,
        ),
      );
      return recommendation(
        episode.title,
        course.title,
        '/episodes/${Uri.encodeComponent(episode.id)}',
      );
    case 'reading':
      final ReadingDoc? doc = _bestMatch(
        readingDocs.where(
          (ReadingDoc item) => item.plainText.trim().isNotEmpty,
        ),
        (ReadingDoc item) =>
            _matchScore(item.title, item.level, level, preferredTopics),
      );
      if (doc == null) {
        return recommendation('选择一篇短文', '打开阅读书库选一篇开始。', focus.route);
      }
      return recommendation(
        doc.title,
        doc.level.isEmpty ? '阅读这篇短文' : '${doc.level} · 阅读这篇短文',
        '/reading/${Uri.encodeComponent(doc.id)}',
      );
    case 'oral':
      final bool travel = preferredTopics.contains('travel');
      return recommendation(
        travel ? '酒店入住' : '咖啡店点单',
        '听示范，再分角色练习。',
        '/learn/dialogue?lesson=${travel ? 1 : 0}',
      );
    case 'vocab':
      return activeBook == null
          ? recommendation('打开统一词书', '从词书选择一组词开始。', '/words')
          : recommendation(
              activeBook.title,
              '复习这组词',
              '/review/session?deck=syllabus&book=${Uri.encodeComponent(activeBook.id)}',
            );
    default:
      return recommendation(focus.label, focus.homeBlurb, focus.route);
  }
}

final Provider<FocusRecommendation?> focusRecommendationProvider =
    Provider<FocusRecommendation?>((Ref ref) {
      final OnboardingProfile profile = ref.watch(onboardingProvider);
      final AcquirePreferencesDto prefs = ref.watch(
        learningPreferencesProvider,
      );
      if (profile.focusId == null &&
          (profile.completed || focusIdFromTags(prefs.tags) == null))
        return null;

      return buildFocusRecommendation(
        profile: profile,
        prefs: prefs,
        courses: ref.watch(libraryCatalogProvider),
        readingDocs: ref.watch(readingLibraryProvider).all,
        activeBook: ref.watch(syllabusBooksProvider).activeBook,
      );
    });
