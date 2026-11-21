import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reading/domain/reading_doc.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
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

String _interestLabel(List<String> ids) {
  for (final OnboardingInterest item in kOnboardingInterests) {
    if (ids.contains(item.id)) return item.label;
  }
  return '日常';
}

String _oralSceneTitle(List<String> interests) {
  if (interests.contains('travel')) return '酒店入住：马上开口问预订';
  if (interests.contains('business')) return '职场寒暄：一句就能接上';
  if (interests.contains('campus')) return '校园问路：立刻用得上';
  if (interests.contains('tech')) return '数码店咨询：场景口语';
  return '咖啡店点单：马上开口';
}

String _readingTitle({
  required List<String> interests,
  required String level,
  required List<ReadingDoc> docs,
}) {
  final String interest = _interestLabel(interests);
  ReadingDoc? match;
  for (final ReadingDoc doc in docs) {
    if (doc.level.isNotEmpty &&
        doc.level.toUpperCase() == level.toUpperCase()) {
      match = doc;
      break;
    }
  }
  match ??= docs.isEmpty ? null : docs.first;
  if (match != null) {
    return match.title;
  }
  if (interests.contains('tech')) {
    return '入门科技短文 · $level';
  }
  return '$interest主题短文 · $level';
}

FocusRecommendation buildFocusRecommendation({
  required OnboardingProfile profile,
  required AcquirePreferencesDto prefs,
  required List<AcquireDailyFeedItemDto> feed,
  required List<ReadingDoc> readingDocs,
  required String? activeBookTitle,
}) {
  final String focusId =
      profile.focusId ?? focusIdFromTags(prefs.tags) ?? 'video';
  final LearningFocus focus =
      focusById(focusId) ?? kLearningFocuses.first;
  final String level =
      profile.abilityId == null ? prefs.level : profile.resolvedLevel;
  final List<String> interests = profile.interestIds.isNotEmpty
      ? profile.interestIds
      : prefs.tags
          .where(
            (String t) => kOnboardingInterests.any(
              (OnboardingInterest i) => i.id == t,
            ),
          )
          .toList(growable: false);
  final String interest = _interestLabel(interests);

  switch (focus.id) {
    case 'video':
      final AcquireDailyFeedItemDto? item =
          feed.isEmpty ? null : feed.first;
      return FocusRecommendation(
        focus: focus,
        title: item?.title ?? '$interest · $level 精听片段',
        subtitle: item == null
            ? focus.homeBlurb
            : '按兴趣与水平为你挑的一段视频',
        route: focus.route,
        startLabel: focus.startLabel,
      );
    case 'reading':
      ReadingDoc? doc;
      for (final ReadingDoc d in readingDocs) {
        if (d.level.toUpperCase() == level.toUpperCase()) {
          doc = d;
          break;
        }
      }
      doc ??= readingDocs.isEmpty ? null : readingDocs.first;
      final String title = doc?.title ??
          _readingTitle(
            interests: interests,
            level: level,
            docs: readingDocs,
          );
      return FocusRecommendation(
        focus: focus,
        title: title,
        subtitle: interests.contains('tech')
            ? '阅读 + 科技 + $level：一篇入门短文'
            : '按兴趣与水平筛选的短文',
        route: doc == null
            ? focus.route
            : '/reading/${Uri.encodeComponent(doc.id)}',
        startLabel: focus.startLabel,
      );
    case 'oral':
      return FocusRecommendation(
        focus: focus,
        title: _oralSceneTitle(interests),
        subtitle: '生活场景，开口就能练',
        route: focus.route,
        startLabel: focus.startLabel,
      );
    case 'vocab':
      return FocusRecommendation(
        focus: focus,
        title: activeBookTitle ?? '统一词书 · $level 词组',
        subtitle: activeBookTitle == null
            ? focus.homeBlurb
            : '按目标与水平继续这组词',
        route: focus.route,
        startLabel: focus.startLabel,
      );
    default:
      return FocusRecommendation(
        focus: focus,
        title: focus.label,
        subtitle: focus.homeBlurb,
        route: focus.route,
        startLabel: focus.startLabel,
      );
  }
}

final Provider<FocusRecommendation?> focusRecommendationProvider =
    Provider<FocusRecommendation?>((Ref ref) {
  final OnboardingProfile profile = ref.watch(onboardingProvider);
  final AcquirePreferencesDto prefs = ref.watch(learningPreferencesProvider);
  final String? focusId = profile.focusId ?? focusIdFromTags(prefs.tags);
  if (focusId == null) return null;

  final List<AcquireDailyFeedItemDto> feed = ref.watch(dailyFeedProvider);
  final ReadingLibraryState library = ref.watch(readingLibraryProvider);
  final String? bookTitle =
      ref.watch(syllabusBooksProvider).activeBook?.title;

  return buildFocusRecommendation(
    profile: profile,
    prefs: prefs,
    feed: feed,
    readingDocs: library.all,
    activeBookTitle: bookTitle,
  );
});
