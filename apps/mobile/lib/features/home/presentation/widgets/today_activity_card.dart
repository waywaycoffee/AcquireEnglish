import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../router/app_router.dart';
import '../../../authentication/presentation/account_storage.dart';
import '../../../daily_path/data/today_journey_store.dart';
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

class TodayActivityCard extends ConsumerStatefulWidget {
  const TodayActivityCard({super.key});

  @override
  ConsumerState<TodayActivityCard> createState() => _TodayActivityCardState();
}

class _TodayActivityCardState extends ConsumerState<TodayActivityCard> {
  bool _busy = false;

  DateTime _nextDay(DateTime today) =>
      DateTime(today.year, today.month, today.day + 1);

  bool _assessed() {
    final PlacementRow result = ref.read(vocabularyPlacementProvider);
    return result['estimate'] is int && result['testedAt'] is String;
  }

  Future<JourneyActivity?> _pick({bool tomorrow = false}) =>
      showModalBottomSheet<JourneyActivity>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _TodayActivityPicker(tomorrow: tomorrow),
      );

  Future<void> _runJourney({bool chooseAnother = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final DateTime today = DateTime.now();
    final String account = ref.read(studyAccountProvider);
    final TodayJourneyStore store = TodayJourneyStore(account, today);

    bool active() =>
        mounted &&
        account == ref.read(studyAccountProvider) &&
        DateUtils.isSameDay(today, DateTime.now());

    try {
      if (!_assessed()) {
        await context.push('${SGRoute.vocabularyPlacement.route}?journey=1');
        if (!active() || !_assessed()) return;
      }

      switch (store.stage) {
        case JourneyStage.review:
          final bool? completed = await context.push<bool>(
            '${SGRoute.reviewSession.route}?due=1&journeyReview=1',
          );
          if (active() && completed == true) {
            await store.saveStage(JourneyStage.learn);
            if (active() && store.activity?.route.isNotEmpty != true) {
              continue learn;
            }
          }
        learn:
        case JourneyStage.learn:
          final JourneyActivity? planned = store.activity;
          final JourneyActivity? activity =
              chooseAnother || planned == null || planned.route.isEmpty
              ? await _pick()
              : planned;
          if (!active() || activity == null) return;
          await store.saveActivity(activity);
          if (!active()) return;
          await context.push(activity.route);
          if (!active()) return;
          final bool? completed = await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => AlertDialog(
              title: const Text('这关学完了吗？'),
              content: Text(activity.title),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('稍后继续'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('完成本关'),
                ),
              ],
            ),
          );
          if (active() && completed == true) {
            await store.saveStage(JourneyStage.tomorrow);
            if (active()) continue chooseTomorrow;
          }
        chooseTomorrow:
        case JourneyStage.tomorrow:
        case JourneyStage.done:
          final JourneyActivity? activity = await _pick(tomorrow: true);
          if (!active() || activity == null) return;
          await TodayJourneyStore(
            account,
            _nextDay(today),
          ).saveActivity(activity);
          if (active()) await store.saveStage(JourneyStage.done);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String account = ref.watch(studyAccountProvider);
    final DateTime today = DateTime.now();
    final TodayJourneyStore store = TodayJourneyStore(account, today);
    final JourneyStage stage = store.stage;
    final JourneyActivity? planned = store.activity;
    final String title = switch (stage) {
      JourneyStage.review => '今天的英语之旅',
      JourneyStage.learn => '学习新内容',
      JourneyStage.tomorrow => '选明天学什么',
      JourneyStage.done => '更换明天的内容',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (stage != JourneyStage.review)
              Text('今天的英语之旅', style: Theme.of(context).textTheme.titleMedium),
            Text(switch (stage) {
              JourneyStage.review => '第 1 关 · 今日复习',
              JourneyStage.learn =>
                '第 2 关 · ${planned?.route.isNotEmpty == true ? planned!.title : '按兴趣学新内容'}',
              JourneyStage.tomorrow => '第 3 关 · 安排明天',
              JourneyStage.done =>
                '今日已完成 · 明天：${TodayJourneyStore(account, _nextDay(today)).activity?.title ?? '系统推荐'}',
            }),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                FilledButton.icon(
                  icon: Icon(
                    stage == JourneyStage.done
                        ? Icons.edit_calendar_outlined
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(title),
                  onPressed: _busy ? null : () => _runJourney(),
                ),
                if (stage == JourneyStage.learn &&
                    planned?.route.isNotEmpty == true)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _runJourney(chooseAnother: true),
                    child: const Text('换一个'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayActivityPicker extends ConsumerStatefulWidget {
  const _TodayActivityPicker({required this.tomorrow});

  final bool tomorrow;

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

    void open(String route, String title) =>
        Navigator.of(context).pop((route: route, title: title));

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
      onTap: () => open(
        route,
        route.startsWith('/episodes/') || route.startsWith('/reading/')
            ? subtitle
            : title,
      ),
    );

    final Widget video = ListTile(
      leading: const Icon(Icons.ondemand_video_outlined),
      title: const Text('看一段推荐视频'),
      subtitle: Text(hasVideo ? recommended.title : '去视频库挑一段'),
      onTap: () => open(
        hasVideo ? recommended.route : '/library',
        hasVideo ? recommended.title : '挑一段视频',
      ),
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
                widget.tomorrow ? '明天想学什么？' : '今天想做什么？',
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
            if (!widget.tomorrow && previousVideo != null)
              activity(
                Icons.forum_outlined,
                '聊昨天的视频',
                previousVideo.title,
                '${videoRoute(previousVideo)}?autoplay=0&activity=coach',
              ),
            activity(Icons.headphones, '磨耳朵', '听一段喜欢的音频', '/ear-grind'),
            if (widget.tomorrow)
              activity(Icons.auto_awesome, '交给系统推荐', '明天再看适合你的内容', ''),
          ],
        ),
      ),
    );
  }
}
