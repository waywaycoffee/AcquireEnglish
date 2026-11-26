import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../authentication/presentation/account_storage.dart';
import '../../../daily_path/data/today_journey_store.dart';
import '../../../learner_model/data/journey_feedback_store.dart';
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
import '../../../sync/data/acquire_api_client.dart';
import '../../../sync/presentation/daily_feed_provider.dart';
import '../../../words/presentation/learner_level_provider.dart';
import '../../../words/presentation/word_book_provider.dart';

class TodayActivityCard extends ConsumerStatefulWidget {
  const TodayActivityCard({super.key});

  @override
  ConsumerState<TodayActivityCard> createState() => _TodayActivityCardState();
}

class _TodayActivityCardState extends ConsumerState<TodayActivityCard> {
  bool _busy = false;
  bool _skippingEmptyReview = false;

  DateTime _nextDay(DateTime today) =>
      DateTime(today.year, today.month, today.day + 1);

  Future<JourneyActivity?> _pick({bool tomorrow = false}) =>
      showModalBottomSheet<JourneyActivity>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppDesignTokens.appWhite,
        builder: (_) => _TodayActivityPicker(tomorrow: tomorrow),
      );

  Future<void> _ensureEmptyReviewSkipped(TodayJourneyStore store) async {
    if (_skippingEmptyReview || store.stage != JourneyStage.review) return;
    final int due = ref.read(wordBookProvider.notifier).dueCounts().dueReviews;
    if (due > 0) return;
    _skippingEmptyReview = true;
    await store.saveStage(JourneyStage.learn);
    if (mounted) setState(() => _skippingEmptyReview = false);
  }

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
      await _ensureEmptyReviewSkipped(store);
      if (!mounted) return;
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
            title: Text(
              '这关学完了吗？',
              style: TextStyle(color: AppDesignTokens.textPrimary),
            ),
            content: Text(
              activity.title,
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
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
          await _seedTomorrowIfNeeded(account, today);
          await store.saveStage(JourneyStage.tomorrow);
        }
        return;
      }
      switch (store.stage) {
        case JourneyStage.review:
        case JourneyStage.learn:
          return;
        case JourneyStage.tomorrow:
          await store.saveStage(JourneyStage.done);
          return;
        case JourneyStage.done:
          return;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _seedTomorrowIfNeeded(String account, DateTime today) async {
    final TodayJourneyStore tomorrow = TodayJourneyStore(
      account,
      _nextDay(today),
    );
    if (tomorrow.activity?.route.isNotEmpty ?? false) return;
    final JourneyNextStep preview = resolveJourneyNext(
      JourneyNextRequest(
        dueReviewCount: 0,
        reviewFinished: true,
        pursuit: _currentPursuit(),
        recommendation: _coldTask(),
        recommendationReason: '',
      ),
    );
    if (preview.route.isEmpty) return;
    await tomorrow.saveActivity((
      route: preview.route,
      title: preview.title.replaceFirst(RegExp(r'^下一步 · '), ''),
    ));
  }

  JourneyTask? _currentPursuit() {
    final Set<String> tracks = selectedLearningTracks(
      ref.read(learningPreferencesProvider).tags,
    );
    final JourneyTask? videoNext = _videoPursuit(
      ref.read(continueLearningTargetProvider),
      enabled: tracks.contains(kTrackVideo),
    );
    final ReadingDoc? book = ref.read(readingLibraryProvider).continueDoc;
    final JourneyTask? readingNext =
        tracks.contains(kTrackReading) && book != null
        ? JourneyTask(
            route: '/reading/${Uri.encodeComponent(book.id)}',
            title: '继续读${book.displayTitle}',
            module: LearnModule.reading,
          )
        : null;
    final String recent = ref.read(currentLearningKindProvider);
    return recent == 'reading'
        ? (readingNext ?? videoNext)
        : (videoNext ?? readingNext);
  }

  JourneyTask? _coldTask() {
    final Set<String> tracks = selectedLearningTracks(
      ref.read(learningPreferencesProvider).tags,
    );
    final ScoredLearnCandidate? cold = _coldRecommendation(
      videoOn: tracks.contains(kTrackVideo),
      readingOn: tracks.contains(kTrackReading),
    );
    if (cold == null) return null;
    return JourneyTask(
      route: cold.candidate.route,
      title: cold.candidate.title,
      module: cold.candidate.module,
    );
  }

  Future<void> _changeTomorrow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final DateTime today = DateTime.now();
    final String account = ref.read(studyAccountProvider);
    try {
      final JourneyActivity? picked = await _pick(tomorrow: true);
      if (!mounted || picked == null) return;
      await TodayJourneyStore(account, _nextDay(today)).saveActivity(picked);
      await TodayJourneyStore(account, today).saveStage(JourneyStage.done);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFeedback() async {
    final TodayJourneyStore store = TodayJourneyStore(
      ref.read(studyAccountProvider),
      DateTime.now(),
    );
    final JourneyNextStep step = _nextStep(store);
    if (step.kind == JourneyNextKind.review || step.route.isEmpty) {
      await _swapOnce();
      return;
    }
    final LearnFeedback? feedback = await showModalBottomSheet<LearnFeedback>(
      context: context,
      backgroundColor: AppDesignTokens.appWhite,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                '换一个',
                style: TextStyle(color: AppDesignTokens.textPrimary),
              ),
              subtitle: Text(
                '只改这一次，不记成长期偏好',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
              onTap: () => Navigator.pop(context, LearnFeedback.swap),
            ),
            ListTile(
              title: Text(
                '不感兴趣',
                style: TextStyle(color: AppDesignTokens.textPrimary),
              ),
              subtitle: Text(
                '七天内不再默认推荐这条',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
              onTap: () => Navigator.pop(context, LearnFeedback.notInterested),
            ),
            ListTile(
              title: Text(
                '太难了',
                style: TextStyle(color: AppDesignTokens.textPrimary),
              ),
              subtitle: Text(
                '同类内容以后略降一档',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
              onTap: () => Navigator.pop(context, LearnFeedback.tooHard),
            ),
            ListTile(
              title: Text(
                '太简单了',
                style: TextStyle(color: AppDesignTokens.textPrimary),
              ),
              subtitle: Text(
                '同类内容以后略升一档',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
              onTap: () => Navigator.pop(context, LearnFeedback.tooEasy),
            ),
          ],
        ),
      ),
    );
    if (!mounted || feedback == null) return;
    final LearnModule module = step.route.startsWith('/reading/')
        ? LearnModule.reading
        : step.route.contains('review')
        ? LearnModule.vocab
        : LearnModule.video;
    await JourneyFeedbackStore(
      ref.read(studyAccountProvider),
    ).apply(id: step.route, module: module, feedback: feedback);
    if (feedback == LearnFeedback.swap ||
        feedback == LearnFeedback.notInterested) {
      await _swapOnce();
    } else if (mounted) {
      setState(() {});
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
    return resolveJourneyNext(
      JourneyNextRequest(
        paused: paused,
        dueReviewCount: due,
        reviewFinished: reviewFinished,
        pursuit: _currentPursuit(),
        recommendation: _coldTask(),
        recommendationReason: _coldRecommendation(
              videoOn: selectedLearningTracks(
                ref.read(learningPreferencesProvider).tags,
              ).contains(kTrackVideo),
              readingOn: selectedLearningTracks(
                ref.read(learningPreferencesProvider).tags,
              ).contains(kTrackReading),
            )?.reason ??
            '',
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
    final JourneyFeedbackStore feedback = JourneyFeedbackStore(
      ref.read(studyAccountProvider),
    );
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
          notInterested: feedback.isHidden('/review/session?kind=word'),
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
            notInterested: feedback.isHidden(video.route),
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
            notInterested: feedback.isHidden(article.route),
          ),
        );
      }
    }
    return pickAimlessNext(
      rankLearnCandidates(
        candidates: candidates,
        profile: profile,
        difficultyShift: feedback.difficultyShifts,
      ),
    );
  }

  String _ctaLabel(JourneyNextStep step, JourneyStage stage) {
    if (stage == JourneyStage.tomorrow) return '就这样 · 明天见';
    if (stage == JourneyStage.done) return '更换明天的内容';
    return switch (step.kind) {
      JourneyNextKind.review => '下一步：开始复习',
      JourneyNextKind.paused ||
      JourneyNextKind.continuePursuit => '下一步：${step.title.replaceFirst(RegExp(r'^继续 · '), '')}',
      JourneyNextKind.recommend => '下一步：打开学习',
      JourneyNextKind.chooseLevel => '下一步：选一条适合你的',
    };
  }

  int _activeGate(JourneyStage stage, JourneyNextStep step) {
    if (stage == JourneyStage.tomorrow || stage == JourneyStage.done) return 3;
    if (step.kind == JourneyNextKind.review) return 1;
    return 2;
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
    final int due = ref.watch(wordBookProvider.notifier).dueCounts().dueReviews;
    if (stage == JourneyStage.review && due == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ensureEmptyReviewSkipped(store));
      });
    }
    final JourneyNextStep step = _nextStep(store);
    final int gate = _activeGate(stage, step);
    final JourneyActivity? tomorrow = TodayJourneyStore(
      account,
      _nextDay(today),
    ).activity;
    final List<({String title, String label})> preview =
        <({String title, String label})>[
          if (due > 0 && stage == JourneyStage.review)
            (title: '复习 $due 词', label: '到期优先'),
          if (step.kind != JourneyNextKind.review)
            (
              title: step.title.replaceFirst(RegExp(r'^下一步 · '), ''),
              label: step.reason,
            ),
          (
            title: tomorrow?.title.isNotEmpty == true
                ? tomorrow!.title
                : '排明天',
            label: tomorrow?.route.isNotEmpty == true
                ? '明天已替你排好'
                : '可跳过，系统代排',
          ),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppDesignTokens.toyCardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '今天 · 约 15 分钟',
                  style: TextStyle(
                    color: AppDesignTokens.brandGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  stage == JourneyStage.tomorrow || stage == JourneyStage.done
                      ? '今天打卡完成'
                      : '英语之旅',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  stage == JourneyStage.tomorrow || stage == JourneyStage.done
                      ? '复习和今天的新学都过了。明天继续点「下一步」就行。'
                      : '不用想学什么。点下一步，把复习和感兴趣的内容一路做完。',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                _GateRow(active: gate),
                const SizedBox(height: 14),
                if (stage == JourneyStage.tomorrow ||
                    stage == JourneyStage.done)
                  _TomorrowBanner(
                    title: tomorrow?.title.isNotEmpty == true
                        ? tomorrow!.title
                        : '明天按你的水平再排一条',
                    reason: tomorrow?.route.isNotEmpty == true
                        ? '明天已替你排好 · 可改'
                        : '还没定明天 · 可现在选',
                  )
                else
                  _NextBanner(
                    title: step.kind == JourneyNextKind.review
                        ? '下一步 · 今日复习'
                        : step.title.startsWith('下一步')
                        ? step.title
                        : '下一步 · ${step.title}',
                    reason: step.kind == JourneyNextKind.review
                        ? '到期 $due 张词卡 · 做完自动进新学'
                        : step.reason,
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : stage == JourneyStage.done
                        ? _changeTomorrow
                        : _runJourney,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppDesignTokens.brandGreen,
                      foregroundColor: AppDesignTokens.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _ctaLabel(step, stage),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                if (stage == JourneyStage.tomorrow) ...<Widget>[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _changeTomorrow,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppDesignTokens.textPrimary,
                        side: BorderSide(color: AppDesignTokens.borderGray),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('换明天学别的'),
                    ),
                  ),
                ] else if (stage == JourneyStage.review ||
                    stage == JourneyStage.learn) ...<Widget>[
                  if (step.kind != JourneyNextKind.review) ...<Widget>[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: _busy ? null : _openFeedback,
                        child: Text(
                          '换一个 / 反馈',
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        if (stage == JourneyStage.review || stage == JourneyStage.learn) ...<
          Widget
        >[
          const SizedBox(height: 18),
          Text(
            '今天还会带你过',
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          for (final ({String title, String label}) item in preview)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppDesignTokens.appWhite,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: Icon(
                    Icons.circle,
                    size: 10,
                    color: AppDesignTokens.brandGreen,
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      color: AppDesignTokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    item.label,
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _GateRow extends StatelessWidget {
  const _GateRow({required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    Widget chip(int n, String label) {
      final bool on = active == n;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? AppDesignTokens.successSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? AppDesignTokens.brandGreen : AppDesignTokens.borderGray,
          ),
        ),
        child: Text(
          '$n $label',
          style: TextStyle(
            color: on
                ? AppDesignTokens.brandGreen
                : AppDesignTokens.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        chip(1, '复习'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 12,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        chip(2, '新学'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 12,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        chip(3, '明天'),
      ],
    );
  }
}

class _NextBanner extends StatelessWidget {
  const _NextBanner({required this.title, required this.reason});

  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.successSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppDesignTokens.brandGreen.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reason,
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              height: 1.4,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TomorrowBanner extends StatelessWidget {
  const _TomorrowBanner({required this.title, required this.reason});

  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.selectedSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '明天已替你排好',
            style: TextStyle(
              color: AppDesignTokens.brandGreen,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reason,
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
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
    final AcquirePreferencesDto prefs = ref.watch(learningPreferencesProvider);
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
      if (continuingVideo && recommended.route != videoRoute(resume.episode))
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
      leading: Icon(icon, color: AppDesignTokens.brandGreen),
      title: Text(title, style: TextStyle(color: AppDesignTokens.textPrimary)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: AppDesignTokens.textSecondary),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppDesignTokens.textSecondary,
      ),
      onTap: () => open(
        route,
        route.startsWith('/episodes/') || route.startsWith('/reading/')
            ? subtitle
            : title,
      ),
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
                widget.tomorrow ? '明天想学什么？' : '想换一个也可以',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppDesignTokens.textPrimary,
                ),
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
              activity(
                Icons.ondemand_video_outlined,
                recommended.title,
                '看一段推荐视频',
                recommended.route,
              ),
            if (book != null)
              activity(
                Icons.menu_book_outlined,
                book.displayTitle,
                '继续读正在看的书',
                '/reading/${Uri.encodeComponent(book.id)}',
              )
            else if (readingSuggestion != null)
              activity(
                Icons.menu_book_outlined,
                readingSuggestion.title,
                '选一本书读',
                readingSuggestion.route,
              ),
            if (widget.tomorrow)
              activity(Icons.auto_awesome, '交给系统推荐', '明天再看适合你的内容', ''),
          ],
        ),
      ),
    );
  }
}
