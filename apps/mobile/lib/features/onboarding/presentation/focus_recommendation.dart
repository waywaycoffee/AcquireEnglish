import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../membership/domain/free_trial_seeds.dart';
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
  List<String> interests, {
  bool englishSpoken = false,
  bool chineseSpoken = false,
  bool freeTrialSeed = false,
}) {
  final String text = title.toLowerCase();
  final bool topicMatch = interests.any(
    (String interest) => _topicKeywords[interest]?.any(text.contains) ?? false,
  );
  // Learners need audible English speech — EN softsubs alone are not enough
  // (game uploads often have Chinese VO + translated EN captions).
  return (topicMatch ? 2 : 0) +
      (contentLevel.trim().toUpperCase() == level.toUpperCase() ? 3 : 0) +
      (englishSpoken ? 10 : 0) +
      (freeTrialSeed ? 8 : 0) +
      (chineseSpoken && !englishSpoken ? -12 : 0);
}

bool _courseEnglishSpoken(LibraryCourseData course) {
  final String spoken = course.spokenLanguage.trim().toLowerCase();
  return spoken == 'en' || spoken.startsWith('en');
}

bool _courseChineseSpoken(LibraryCourseData course) {
  final String spoken = course.spokenLanguage.trim().toLowerCase();
  return spoken == 'zh' || spoken.startsWith('zh');
}

bool _looksLikeFreeTrialEnglishSeed(LibraryCourseData course, LibraryEpisodeItem episode) {
  if (isFreeTrialCourseSeedId(course.id) || isFreeTrialSeedId(course.id)) {
    return true;
  }
  final String blob = '${course.id} ${episode.id} ${episode.sourceUrl ?? ''}';
  for (final FreeTrialSeedItem seed
      in kDefaultFreeTrialSeeds['video'] ?? const <FreeTrialSeedItem>[]) {
    final String bv = seed.bvid.trim();
    if (bv.isEmpty) continue;
    if (blob.toUpperCase().contains(bv.toUpperCase())) return true;
  }
  return false;
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
  String? levelOverride,
}) {
  final LearningFocus focus =
      focusById(profile.focusId ?? focusIdFromTags(prefs.tags) ?? '') ??
      kLearningFocuses.first;
  final String level = levelOverride ?? (profile.abilityId == null
      ? prefs.level
      : profile.resolvedLevel);
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
      // Rank playable episodes. Prefer English *speech* (and free-trial seeds),
      // not merely EN softsubs / title keywords like「游戏」.
      ({LibraryCourseData course, LibraryEpisodeItem episode})? best;
      int bestScore = -1;
      for (final LibraryCourseData course in courses) {
        final bool englishSpoken = _courseEnglishSpoken(course);
        final bool chineseSpoken = _courseChineseSpoken(course);
        for (final LibraryEpisodeItem episode in course.episodes) {
          if (episode.videoMissing) continue;
          final bool seed = _looksLikeFreeTrialEnglishSeed(course, episode);
          // Skip known Chinese-spoken library hits when we already have an
          // English-spoken or seed candidate; still allow if nothing else.
          final int score = _matchScore(
            '${course.title} ${course.category} ${episode.title}',
            course.level,
            level,
            preferredTopics,
            englishSpoken: englishSpoken,
            chineseSpoken: chineseSpoken,
            freeTrialSeed: seed,
          );
          final int tieBreak = episode.completed ? 0 : 1;
          final int ranked = score * 10 + tieBreak;
          if (ranked > bestScore) {
            bestScore = ranked;
            best = (course: course, episode: episode);
          }
        }
      }
      // If the winner is Chinese-spoken and not a seed, fall back to library
      // hub — better than sending the user into silent/Chinese game footage.
      if (best != null &&
          _courseChineseSpoken(best.course) &&
          !_courseEnglishSpoken(best.course) &&
          !_looksLikeFreeTrialEnglishSeed(best.course, best.episode)) {
        return recommendation(
          '选择一段有英语人声的视频',
          '兴趣只作筛选；请选口播为英语的内容，不要只看有没有英文字幕。',
          focus.route,
        );
      }
      if (best == null) {
        return recommendation('选择一段视频', '从课程库选择或导入视频。', focus.route);
      }
      return recommendation(
        best.episode.title,
        best.course.title,
        '/episodes/${Uri.encodeComponent(best.episode.id)}',
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
        travel ? '酒店入住' : '日常对话',
        '听示范，再分角色练习。',
        '/learn/dialogue?lesson=${travel ? 1 : 0}',
      );
    case 'vocab':
      return activeBook == null
          ? recommendation('打开统一词书', '从词书选择一组词开始。', '/words')
          : recommendation(
              activeBook.title,
              '复习这组词',
              '/review/session',
            );
    case 'exam':
      return recommendation(
        '选择考试目标',
        '按考试族刷词、听力与模考。',
        '/exam/select',
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
