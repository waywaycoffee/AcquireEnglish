import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../router/app_router.dart';
import '../../../library/presentation/library_catalog_provider.dart';
import '../../../library/presentation/library_mock_data.dart';
import '../../../onboarding/domain/onboarding_profile.dart';
import '../../../onboarding/presentation/focus_recommendation.dart';
import '../../../onboarding/presentation/onboarding_provider.dart';
import '../../../player/presentation/learning_resume_provider.dart';
import '../../../reading/domain/reading_doc.dart';
import '../../../reading/presentation/reading_library_provider.dart';
import '../../../sync/presentation/daily_feed_provider.dart';
import '../../../words/presentation/learner_level_provider.dart';
import '../../../words/presentation/vocabulary_placement_provider.dart';
import '../learning_dashboard_provider.dart';

class TodayActivityCard extends ConsumerWidget {
  const TodayActivityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('今天的英语之旅'),
              onPressed: () async {
                bool assessed() {
                  final PlacementRow result = ref.read(
                    vocabularyPlacementProvider,
                  );
                  return result['estimate'] is int &&
                      result['testedAt'] is String;
                }

                if (!assessed()) {
                  await context.push(
                    '${SGRoute.vocabularyPlacement.route}?journey=1',
                  );
                  if (!context.mounted || !assessed()) return;
                }
                final String? route = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const _TodayActivityPicker(),
                );
                if (context.mounted && route != null) await context.push(route);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayActivityPicker extends ConsumerStatefulWidget {
  const _TodayActivityPicker();

  @override
  ConsumerState<_TodayActivityPicker> createState() =>
      _TodayActivityPickerState();
}

class _TodayActivityPickerState extends ConsumerState<_TodayActivityPicker> {
  final Set<String> _skippedRoutes = <String>{};

  @override
  Widget build(BuildContext context) {
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    final ReadingLibraryState reading = ref.watch(readingLibraryProvider);
    final ReadingDoc? book = reading.continueDoc;
    final ContinueLearningTarget? resume = ref.watch(
      continueLearningTargetProvider,
    );
    final OnboardingProfile profile = ref.watch(onboardingProvider);
    final prefs = ref.watch(learningPreferencesProvider);
    final String level = ref.watch(adaptiveLearnerCefrProvider);
    final FocusRecommendation? readingSuggestion = book == null
        ? buildFocusRecommendation(
            profile: profile.copyWith(focusId: 'reading'),
            prefs: prefs,
            courses: const <LibraryCourseData>[],
            readingDocs: reading.all,
            activeBook: null,
            levelOverride: level,
          )
        : null;
    final Set<String> yesterday = ref
        .watch(learningActivityProvider)
        .yesterday
        .watchedVideoKeys;
    final LibraryEpisodeItem? previousVideo = courses
        .expand((LibraryCourseData c) => c.episodes)
        .where(
          (LibraryEpisodeItem e) =>
              yesterday.contains(e.id) &&
              !e.videoMissing &&
              e.hasEnglishSubtitles,
        )
        .lastOrNull;
    String videoRoute(LibraryEpisodeItem e) =>
        '/episodes/${Uri.encodeComponent(e.id)}';
    final FocusRecommendation recommended = buildFocusRecommendation(
      profile: profile.copyWith(focusId: 'video'),
      prefs: prefs,
      courses: <LibraryCourseData>[
        for (final LibraryCourseData course in courses)
          course.copyWith(
            episodes: course.episodes
                .where(
                  (LibraryEpisodeItem e) =>
                      !e.videoMissing &&
                      ((e.videoAsset ?? '').trim().isNotEmpty ||
                          (e.sourceUrl ?? '').trim().isNotEmpty) &&
                      !_skippedRoutes.contains(videoRoute(e)),
                )
                .toList(),
          ),
      ],
      readingDocs: const <ReadingDoc>[],
      activeBook: null,
      levelOverride: level,
    );
    final bool hasVideo = recommended.route.startsWith('/episodes/');

    void open(String route) => Navigator.of(context).pop(route);

    Widget activity(
      IconData icon,
      String title,
      String subtitle,
      String route,
    ) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => open(route),
    );

    final Widget video = ListTile(
      leading: const Icon(Icons.ondemand_video_outlined),
      title: const Text('看一段推荐视频'),
      subtitle: Text(hasVideo ? recommended.title : '去视频库挑一段'),
      onTap: () => open(hasVideo ? recommended.route : '/library'),
      trailing: hasVideo
          ? IconButton(
              tooltip: '跳过这条，换一段',
              icon: const Icon(Icons.skip_next),
              onPressed: () =>
                  setState(() => _skippedRoutes.add(recommended.route)),
            )
          : const Icon(Icons.chevron_right),
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                '今天想做什么？',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (hasVideo)
              Dismissible(
                key: ValueKey<String>(recommended.route),
                direction: DismissDirection.horizontal,
                onDismissed: (_) =>
                    setState(() => _skippedRoutes.add(recommended.route)),
                background: const Align(
                  alignment: Alignment.center,
                  child: Icon(Icons.skip_next),
                ),
                child: video,
              )
            else
              video,
            if (resume != null &&
                !resume.episode.videoMissing &&
                ref.watch(lastLearningEpisodeProvider) == resume.episode.id)
              activity(
                Icons.play_circle_outline,
                '继续上次的视频',
                resume.episode.title,
                videoRoute(resume.episode),
              ),
            activity(
              Icons.menu_book_outlined,
              book == null ? '选一本书读' : '继续读正在看的书',
              book?.displayTitle ?? readingSuggestion!.title,
              book == null
                  ? readingSuggestion!.route
                  : '/reading/${Uri.encodeComponent(book.id)}',
            ),
            activity(Icons.quiz_outlined, '做真题', '练一组目标考试的题目', '/exam'),
            activity(
              Icons.record_voice_over_outlined,
              '聊聊周围的环境',
              '可以直接描述，也可以在口语页主动拍照',
              '/digital-human?sceneMenu=1',
            ),
            if (previousVideo != null)
              activity(
                Icons.forum_outlined,
                '聊昨天的视频',
                previousVideo.title,
                '${videoRoute(previousVideo)}?autoplay=0&activity=coach',
              ),
            activity(Icons.headphones, '磨耳朵', '听一段喜欢的音频', '/ear-grind'),
          ],
        ),
      ),
    );
  }
}
