import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../authentication/presentation/account_storage.dart';
import '../../../daily_path/data/today_journey_store.dart';
import '../../../learner_model/domain/journey_next_step.dart';
import '../../../learner_model/domain/learner_skill_profile.dart';
import '../../../learner_model/domain/learning_recommendation.dart';
import '../../../library/presentation/library_catalog_provider.dart';
import '../../../library/presentation/library_mock_data.dart';
import '../../../onboarding/domain/learning_tracks.dart';
import '../../../onboarding/domain/onboarding_profile.dart';
import '../../../onboarding/presentation/focus_recommendation.dart';
import '../../../onboarding/presentation/onboarding_provider.dart';
import '../../../player/presentation/learning_resume_provider.dart';
import '../../../reading/domain/reading_doc.dart';
import '../../../reading/presentation/reading_library_provider.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../sync/presentation/daily_feed_provider.dart';
import '../../../words/presentation/learner_level_provider.dart';
import '../../../words/presentation/word_book_provider.dart';
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

  Future<JourneyActivity?> _pick({bool tomorrow = false}) =>
      showModalBottomSheet<JourneyActivity>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _TodayActivityPicker(tomorrow: tomorrow),
      );

  Future<void> _runJourney() async {
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
      final JourneyNextStep step = _nextStep(store);
      if (store.stage == JourneyStage.review ||
          store.stage == JourneyStage.learn) {
        if (step.kind == JourneyNextKind.review) {
          final bool? completed = await context.push<bool>(step.route);
          if (active() && (completed ?? false)) {
            await store.saveStage(JourneyStage.learn);
          }
          return;
        }
        if (step.kind == JourneyNextKind.chooseLevel || step.route.isEmpty) {
          final JourneyActivity? picked = await _pick();
          if (!active() || picked == null) return;
          await store.saveStage(JourneyStage.learn);
          await store.saveActivity(picked);
          if (!mounted) return;
          await context.push(picked.route);
          return;
        }
        final JourneyActivity activity = (
          route: step.route,
          title: step.title,
        );
        await store.saveStage(JourneyStage.learn);
        await store.saveActivity(activity);
        if (!mounted) return;
        await context.push(activity.route);
        if (!mounted) return;
        final bool? completed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            backgroundColor: AppDesignTokens.appWhite,
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
        if (active() && (completed ?? false)) {
          await store.saveStage(JourneyStage.tomorrow);
        }
        return;
      }
      switch (store.stage) {
        case JourneyStage.review:
        case JourneyStage.learn:
          return;
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

  Future<void> _swapOnce() async {
    if (_busy) return;
    setState(() => _busy = true);
    final DateTime today = DateTime.now();
    final String account = ref.read(studyAccountProvider);
    final TodayJourneyStore store = TodayJourneyStore(account, today);
    try {
      final JourneyActivity? picked = await _pick();
      if (!mounted || picked == null) return;
      await store.saveStage(JourneyStage.learn);
      await store.saveActivity(picked);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  JourneyNextStep _nextStep(TodayJourneyStore store) {
    final bool reviewFinished = store.stage != JourneyStage.review;
    final JourneyActivity? pausedActivity = store.activity;
    final JourneyTask? paused =
        store.stage == JourneyStage.learn &&
            pausedActivity != null &&
            pausedActivity.route.isNotEmpty
        ? JourneyTask(
            route: pausedActivity.route,
            title: pausedActivity.title,
            module: LearnModule.vocab,
          )
        : null;
    final int due = ref.read(wordBookProvider.notifier).dueCounts().dueReviews;
    final Set<String> tracks = selectedLearningTracks(
      ref.read(learningPreferencesProvider).tags,
    );
    final bool videoOn = tracks.contains(kTrackVideo);
    final bool readingOn = tracks.contains(kTrackReading);
    final ContinueLearningTarget? resume = ref.read(
      continueLearningTargetProvider,
    );
    final JourneyTask? videoNext = _videoPursuit(resume, enabled: videoOn);
    final ReadingDoc? book = ref.read(readingLibraryProvider).continueDoc;
    final JourneyTask? readingNext = readingOn && book != null
        ? JourneyTask(
            route: '/reading/${Uri.encodeComponent(book.id)}',
            title: '继续读${book.displayTitle}',
            module: LearnModule.reading,
          )
        : null;
    final String recent = ref.read(currentLearningKindProvider);
    final JourneyTask? pursuit = recent == 'reading'
        ? (readingNext ?? videoNext)
        : (videoNext ?? readingNext);
    final ScoredLearnCandidate? cold = pursuit == null
        ? _coldRecommendation(videoOn: videoOn, readingOn: readingOn)
        : null;
    return resolveJourneyNext(
      JourneyNextRequest(
        paused: paused,
        dueReviewCount: due,
        reviewFinished: reviewFinished,
        pursuit: pursuit,
        recommendation: cold == null
            ? null
            : JourneyTask(
                route: cold.candidate.route,
                title: cold.candidate.title,
                module: cold.candidate.module,
              ),
        recommendationReason: cold?.reason ?? '',
      ),
    );
  }

  JourneyTask? _videoPursuit(
    ContinueLearningTarget? resume, {
    required bool enabled,
  }) {
    if (!enabled || resume == null || resume.episode.videoMissing) return null;
    final List<LibraryEpisodeItem> episodes = resume.course.episodes
        .where((LibraryEpisodeItem episode) => !episode.videoMissing)
        .toList();
    final int index = episodes.indexWhere(
      (LibraryEpisodeItem episode) => episode.id == resume.episode.id,
    );
    if (index < 0) return null;
    final LibraryEpisodeItem current = episodes[index];
    final LibraryEpisodeItem? next = index + 1 < episodes.length
        ? episodes[index + 1]
        : null;
    String routeOf(LibraryEpisodeItem episode) =>
        '/episodes/${Uri.encodeComponent(episode.id)}';
    return seriesContinueTarget(
      SeriesProgress(
        itemCount: episodes.length,
        lastIndex: index,
        lastCompleted: current.completed,
        confirmed: false,
        currentTitle: '继续${current.title}',
        currentRoute: routeOf(current),
        nextTitle: next == null ? '' : '继续${next.title}',
        nextRoute: next == null ? '' : routeOf(next),
      ),
      enabled: true,
      module: LearnModule.video,
    );
  }

  ScoredLearnCandidate? _coldRecommendation({
    required bool videoOn,
    required bool readingOn,
  }) {
    final String level = ref.read(adaptiveLearnerCefrProvider);
    final LearnerSkillProfile profile = LearnerSkillProfile.initial(
      priorBand: level,
    );
    final OnboardingProfile onboarding = ref.read(onboardingProvider);
    final List<LearnCandidate> candidates = <LearnCandidate>[
      if (selectedLearningTracks(
        ref.read(learningPreferencesProvider).tags,
      ).contains(kTrackVocab))
        LearnCandidate(
          id: 'vocab-next',
          title: '背一组适合现在的词',
          route: '/review/session?kind=word',
          module: LearnModule.vocab,
          contentBand: profile.estimate(LearnerSkill.vocab).band,
          interestMatch: onboarding.focusId == 'vocab',
        ),
    ];
    if (videoOn) {
      final FocusRecommendation video = buildFocusRecommendation(
        profile: onboarding.copyWith(focusId: 'video'),
        prefs: ref.read(learningPreferencesProvider),
        courses: ref.read(libraryCatalogProvider),
        readingDocs: const <ReadingDoc>[],
        activeBook: null,
        levelOverride: profile
            .recommendationEstimate(LearnerSkill.listening)
            .band,
      );
      if (video.route.startsWith('/episodes/')) {
        candidates.add(
          LearnCandidate(
            id: video.route,
            title: video.title,
            route: video.route,
            module: LearnModule.video,
            contentBand: profile
                .recommendationEstimate(LearnerSkill.listening)
                .band,
            interestMatch: true,
          ),
        );
      }
    }
    if (readingOn) {
      final ReadingLibraryState reading = ref.read(readingLibraryProvider);
      final FocusRecommendation article = buildFocusRecommendation(
        profile: onboarding.copyWith(focusId: 'reading'),
        prefs: ref.read(learningPreferencesProvider),
        courses: const <LibraryCourseData>[],
        readingDocs: reading.all,
        activeBook: null,
        levelOverride: profile.recommendationEstimate(LearnerSkill.reading).band,
      );
      if (article.route.startsWith('/reading/')) {
        candidates.add(
          LearnCandidate(
            id: article.route,
            title: article.title,
            route: article.route,
            module: LearnModule.reading,
            contentBand: profile
                .recommendationEstimate(LearnerSkill.reading)
                .band,
            interestMatch: true,
          ),
        );
      }
    }
    return pickAimlessNext(
      rankLearnCandidates(candidates: candidates, profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String account = ref.watch(studyAccountProvider);
    ref
      ..watch(wordBookProvider)
      ..watch(continueLearningTargetProvider)
      ..watch(readingLibraryProvider)
      ..watch(learningPreferencesProvider)
      ..watch(currentLearningKindProvider)
      ..watch(libraryCatalogProvider);
    final DateTime today = DateTime.now();
    final TodayJourneyStore store = TodayJourneyStore(account, today);
    final JourneyStage stage = store.stage;
    final JourneyNextStep step = _nextStep(store);
    final bool planning = stage == JourneyStage.review || stage == JourneyStage.learn;
    final String title = planning
        ? step.title
        : switch (stage) {
            JourneyStage.tomorrow => '选明天学什么',
            JourneyStage.done => '更换明天的内容',
            _ => step.title,
          };
    final String detail = planning
        ? step.reason
        : switch (stage) {
            JourneyStage.tomorrow => '第 3 关 · 安排明天',
            JourneyStage.done =>
              '今日已完成 · 明天：${TodayJourneyStore(account, _nextDay(today)).activity?.title ?? '按你的水平再排一条'}',
            _ => step.reason,
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('今天的英语之旅', style: Theme.of(context).textTheme.titleMedium),
            Text(detail),
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
                if (planning && step.kind != JourneyNextKind.review)
                  TextButton(
                    onPressed: _busy ? null : _swapOnce,
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
    final bool continuingVideo =
        resume != null &&
        !resume.episode.videoMissing &&
        ref.watch(lastLearningEpisodeProvider) == resume.episode.id;
    final bool purposeful = continuingVideo || book != null;
    final LearnerSkillProfile skillProfile = LearnerSkillProfile.initial(
      priorBand: level,
    );
    String asBand(String raw, String fallback) {
      final String upper = raw.trim().toUpperCase();
      return kLearnerBands.contains(upper) ? upper : fallback;
    }

    final List<LearnCandidate> candidates = <LearnCandidate>[
      LearnCandidate(
        id: 'vocab-next',
        title: '背一组适合现在的词',
        route: '/review/session?kind=word',
        module: LearnModule.vocab,
        contentBand: skillProfile.estimate(LearnerSkill.vocab).band,
        interestMatch: profile.focusId == 'vocab',
      ),
      if (hasVideo)
        LearnCandidate(
          id: recommended.route,
          title: recommended.title,
          route: recommended.route,
          module: LearnModule.video,
          contentBand: asBand(
            level,
            skillProfile.recommendationEstimate(LearnerSkill.listening).band,
          ),
          interestMatch: true,
          pursuit:
              continuingVideo &&
              recommended.route == videoRoute(resume.episode),
        ),
      if (continuingVideo &&
          (recommended.route != videoRoute(resume.episode)))
        LearnCandidate(
          id: videoRoute(resume.episode),
          title: resume.episode.title,
          route: videoRoute(resume.episode),
          module: LearnModule.video,
          contentBand: skillProfile
              .recommendationEstimate(LearnerSkill.listening)
              .band,
          pursuit: true,
        ),
      LearnCandidate(
        id: book?.id ?? 'reading-next',
        title: book?.displayTitle ?? (readingSuggestion?.title ?? '选一篇来读'),
        route: book == null
            ? (readingSuggestion?.route ?? '/reading')
            : '/reading/${Uri.encodeComponent(book.id)}',
        module: LearnModule.reading,
        contentBand: asBand(
          book?.level ?? '',
          skillProfile.recommendationEstimate(LearnerSkill.reading).band,
        ),
        pursuit: book != null,
      ),
    ];
    final List<ScoredLearnCandidate> ranked = rankLearnCandidates(
      candidates: candidates,
      profile: skillProfile,
    );
    final ScoredLearnCandidate? aimless = pickAimlessNext(ranked);
    final List<ScoredLearnCandidate> shortlist = purposefulShortlist(ranked);

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
            if (!purposeful && aimless != null)
              activity(
                Icons.arrow_forward_rounded,
                '下一步 · ${aimless.candidate.title}',
                aimless.reason,
                aimless.candidate.route,
              )
            else if (purposeful)
              for (int i = 0; i < shortlist.length; i++)
                activity(
                  i == 0 ? Icons.star_rounded : Icons.swap_horiz_rounded,
                  i == 0
                      ? '最可能 · ${shortlist[i].candidate.title}'
                      : shortlist[i].candidate.title,
                  shortlist[i].slightlyHard
                      ? '稍难 · ${shortlist[i].reason}'
                      : shortlist[i].reason,
                  shortlist[i].candidate.route,
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
