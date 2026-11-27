import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../authentication/presentation/account_storage.dart';
import '../../../community/data/english_browse_actions.dart';
import '../../../daily_path/data/journey_reminder.dart';
import '../../../daily_path/data/today_journey_store.dart';
import '../../../daily_path/domain/today_task.dart';
import '../../../daily_path/presentation/today_learning_setup.dart';
import '../../../daily_path/presentation/today_path_provider.dart';
import '../../../daily_review/domain/daily_review.dart';
import '../../../daily_review/presentation/daily_review_provider.dart';
import '../../../daily_review/presentation/syllabus_overlap_dialog.dart';
import '../../../learner_model/data/journey_feedback_store.dart';
import '../../../learner_model/domain/journey_next_step.dart';
import '../../../learner_model/domain/learner_skill_profile.dart';
import '../../../learner_model/domain/learning_recommendation.dart';
import '../../../learner_model/presentation/learner_skill_profile_provider.dart';
import '../../../library/presentation/library_catalog_provider.dart';
import '../../../library/presentation/library_mock_data.dart';
import '../../../onboarding/domain/onboarding_profile.dart';
import '../../../onboarding/presentation/focus_recommendation.dart';
import '../../../onboarding/presentation/onboarding_provider.dart';
import '../../../player/presentation/learning_resume_provider.dart';
import '../../../reading/domain/reading_doc.dart';
import '../../../reading/presentation/reading_library_provider.dart';
import '../../../settings/presentation/settings_provider.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../sync/data/acquire_api_client.dart';
import '../../../sync/presentation/daily_feed_provider.dart';
import '../../../words/domain/syllabus_book.dart';
import '../../../words/presentation/syllabus_books_provider.dart';
import '../../../words/presentation/word_review_settings_provider.dart';
import '../learning_dashboard_provider.dart';

class TodayActivityCard extends ConsumerStatefulWidget {
  const TodayActivityCard({super.key});

  @override
  ConsumerState<TodayActivityCard> createState() => _TodayActivityCardState();
}

class _TodayActivityCardState extends ConsumerState<TodayActivityCard> {
  bool _busy = false;
  bool _syncScheduled = false;

  DateTime _nextDay(DateTime today) =>
      DateTime(today.year, today.month, today.day + 1);

  /// Unified FSRS due count via todayPath (reviewSources), not wordBook SM2.
  int _unifiedDueCount() {
    final TodayPathState path = ref.read(todayPathProvider);
    int total = 0;
    for (final TodayTask task in path.tasks) {
      if (task.doneToday) continue;
      if (task.count > 0) {
        total += task.count;
      } else {
        total += 1;
      }
    }
    return total;
  }
  Future<bool> _syncProgress(TodayJourneyStore store) async {
    final TodayStudyPlan plan = store.studyPlan;
    if (!plan.quotasConfigured) return false;
    final LearningDailyRecord today = ref.read(learningActivityProvider).today;
    final int videoMs = math.max(plan.videoDoneMs, today.videoStudyMilliseconds);
    final int vocabFromActivity = _newWordsToday();
    final int vocab = math.max(plan.vocabDone, vocabFromActivity);
    int readingWords = plan.readingWordsDone;
    final ReadingLibraryState library = ref.read(readingLibraryProvider);
    for (final String key in today.readArticleKeys) {
      final ReadingDoc? doc = library.docById(key);
      if (doc == null) continue;
      final ReadingProgress? progress = library.progressFor(doc.id);
      final double pct = (progress?.percent ?? 0).clamp(0.0, 1.0);
      readingWords = math.max(
        readingWords,
        (doc.wordCount * pct).round(),
      );
    }
    final ReadingDoc? cont = library.continueDoc;
    if (cont != null) {
      final ReadingProgress? progress = library.progressFor(cont.id);
      final double pct = (progress?.percent ?? 0).clamp(0.0, 1.0);
      readingWords = math.max(readingWords, (cont.wordCount * pct).round());
    }
    if (videoMs != plan.videoDoneMs ||
        vocab != plan.vocabDone ||
        readingWords != plan.readingWordsDone) {
      await store.saveProgress(
        videoDoneMs: videoMs,
        vocabDone: vocab,
        readingWordsDone: readingWords,
      );
      return true;
    }
    return false;
  }

  void _scheduleProgressSync(TodayJourneyStore store) {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _syncScheduled = false;
      if (!mounted) return;
      final bool changed = await _syncProgress(store);
      if (changed && mounted) setState(() {});
    });
  }

  Future<({int videoMinutes, int vocabCount, int readingWords})?>
      _askQuotas({
    int videoMinutes = 20,
    int vocabCount = 20,
    int readingWords = 500,
  }) {
    return showModalBottomSheet<
        ({int videoMinutes, int vocabCount, int readingWords})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.appWhite,
      builder: (_) => _TodayQuotaSheet(
        videoMinutes: videoMinutes,
        vocabCount: vocabCount,
        readingWords: readingWords,
      ),
    );
  }

  Future<void> _ensureQuotas(TodayJourneyStore store) async {
    final TodayStudyPlan plan = store.studyPlan;
    if (plan.quotasConfigured) return;
    // Carry yesterday quotas when present.
    final TodayJourneyStore yesterday = TodayJourneyStore(
      ref.read(studyAccountProvider),
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final TodayStudyPlan y = yesterday.studyPlan;
    final ({int videoMinutes, int vocabCount, int readingWords})? picked =
        await _askQuotas(
      videoMinutes: y.quotasConfigured ? y.videoMinutes : 20,
      vocabCount: y.quotasConfigured ? y.vocabCount : 20,
      readingWords: y.quotasConfigured ? y.readingWords : 500,
    );
    if (picked == null || !mounted) return;
    await store.saveQuotas(
      videoMinutes: picked.videoMinutes,
      vocabCount: picked.vocabCount,
      readingWords: picked.readingWords,
    );
    await ref.read(wordReviewSettingsProvider.notifier).setDailyNewLimit(picked.vocabCount);
    if (mounted) setState(() {});
  }

  Future<void> _editQuotas(TodayJourneyStore store) async {
    final TodayStudyPlan plan = store.studyPlan;
    final ({int videoMinutes, int vocabCount, int readingWords})? picked =
        await _askQuotas(
      videoMinutes: plan.videoMinutes,
      vocabCount: plan.vocabCount,
      readingWords: plan.readingWords,
    );
    if (picked == null || !mounted) return;
    await store.saveQuotas(
      videoMinutes: picked.videoMinutes,
      vocabCount: picked.vocabCount,
      readingWords: picked.readingWords,
    );
    await ref.read(wordReviewSettingsProvider.notifier).setDailyNewLimit(picked.vocabCount);
    if (mounted) setState(() {});
  }

  JourneyTask? _videoPursuit() {
    final ContinueLearningTarget? resume =
        ref.read(continueLearningTargetProvider);
    if (resume == null) return null;
    final List<LibraryEpisodeItem> episodes = resume.course.episodes
        .where((LibraryEpisodeItem episode) => !episode.videoMissing)
        .toList();
    if (episodes.isEmpty) return null;
    int index = episodes.indexWhere(
      (LibraryEpisodeItem episode) => episode.id == resume.episode.id,
    );
    if (index < 0) {
      if (resume.episode.videoMissing) {
        final int rawIndex = resume.course.episodes.indexWhere(
          (LibraryEpisodeItem e) => e.id == resume.episode.id,
        );
        if (rawIndex >= 0) {
          for (int i = rawIndex + 1; i < resume.course.episodes.length; i++) {
            final LibraryEpisodeItem candidate = resume.course.episodes[i];
            if (candidate.videoMissing) continue;
            index = episodes.indexWhere(
              (LibraryEpisodeItem e) => e.id == candidate.id,
            );
            break;
          }
        }
      }
      if (index < 0) return null;
    }
    final LibraryEpisodeItem current = episodes[index];
    final LibraryEpisodeItem? next =
        index + 1 < episodes.length ? episodes[index + 1] : null;
    String routeOf(LibraryEpisodeItem episode) =>
        '/episodes/${Uri.encodeComponent(episode.id)}';
    String episodeLabel(LibraryEpisodeItem episode, int episodeIndex) {
      final String raw = episode.title.trim();
      if (raw.contains('第') && raw.contains('集')) return '继续$raw';
      return '继续第${episodeIndex + 1}集 · $raw';
    }

    final bool confirmedSeries = index >= 1 ||
        resume.course.completedEpisodes >= 1 ||
        (ref.read(lastLearningEpisodeProvider) ?? '').isNotEmpty;
    return seriesContinueTarget(
      SeriesProgress(
        itemCount: episodes.length,
        lastIndex: index,
        lastCompleted: current.completed || current.progressPercent >= 95,
        confirmed: confirmedSeries,
        currentTitle: episodeLabel(current, index),
        currentRoute: routeOf(current),
        nextTitle: next == null ? '' : episodeLabel(next, index + 1),
        nextRoute: next == null ? '' : routeOf(next),
      ),
      enabled: true,
      module: LearnModule.video,
    );
  }

  JourneyTask? _vocabPursuit() {
    final SyllabusBooksState books = ref.read(syllabusBooksProvider);
    final SyllabusBook? book = books.activeBook;
    if (book != null && !books.isComplete(book)) {
      return JourneyTask(
        route: syllabusBookSessionRoute(book.id),
        title: '背词 · ${book.title}',
        module: LearnModule.vocab,
      );
    }
    return const JourneyTask(
      route: '/words/syllabus?selectForStudy=1',
      title: '选择一本词书',
      module: LearnModule.vocab,
    );
  }

  JourneyTask? _readingPursuit() {
    final ReadingDoc? book = ref.read(readingLibraryProvider).continueDoc;
    if (book != null) {
      return JourneyTask(
        route: '/reading/${Uri.encodeComponent(book.id)}',
        title: '继续读${book.displayTitle}',
        module: LearnModule.reading,
      );
    }
    final LearnerSkillProfile profile = ref.read(learnerSkillProfileProvider);
    final FocusRecommendation article = buildFocusRecommendation(
      profile: ref.read(onboardingProvider).copyWith(focusId: 'reading'),
      prefs: ref.read(learningPreferencesProvider),
      courses: const <LibraryCourseData>[],
      readingDocs: ref.read(readingLibraryProvider).all,
      activeBook: null,
      levelOverride: profile.recommendationEstimate(LearnerSkill.reading).band,
    );
    if (article.route.startsWith('/reading/')) {
      return JourneyTask(
        route: article.route,
        title: article.title,
        module: LearnModule.reading,
      );
    }
    return const JourneyTask(
      route: '/reading',
      title: '打开书库选一篇',
      module: LearnModule.reading,
    );
  }

  JourneyTask? _pursuitFor(TodayStudyTrack track) {
    return switch (track) {
      TodayStudyTrack.video => _videoPursuit(),
      TodayStudyTrack.vocab => _vocabPursuit(),
      TodayStudyTrack.reading => _readingPursuit(),
    };
  }

  String _trackLabel(TodayStudyTrack track) => switch (track) {
        TodayStudyTrack.video => '视频',
        TodayStudyTrack.vocab => '背单词',
        TodayStudyTrack.reading => '阅读',
      };

  Future<void> _seedTomorrow(
    String account,
    DateTime today,
    TodayJourneyStore store,
  ) async {
    final TodayJourneyStore tomorrow = TodayJourneyStore(
      account,
      _nextDay(today),
    );
    if (tomorrow.studyPlan.quotasConfigured) return;
    final TodayStudyPlan plan = store.studyPlan;
    await tomorrow.saveQuotas(
      videoMinutes: plan.videoMinutes,
      vocabCount: plan.vocabCount,
      readingWords: plan.readingWords,
    );
    final TodayStudyTrack? last = plan.lastTrack ?? plan.nextTrack;
    final JourneyTask? pursuit =
        last == null ? null : _pursuitFor(last);
    if (pursuit != null) {
      await tomorrow.saveActivity(
        journeyActivity(route: pursuit.route, title: pursuit.title),
        planned: true,
        reason: '接着昨天继续${_trackLabel(last!)}',
      );
    }
    if (ref.read(learningSettingsProvider).reminder && pursuit != null) {
      await scheduleJourneyReminder(
        day: _nextDay(today),
        title: pursuit.title,
        body: '点下一步，接着昨天继续学',
      );
    }
  }

  int _newWordsToday() => ref
      .read(dailyReviewProvider)
      .days[reviewDayKey(ref.read(reviewClockProvider)())]
      ?.newLearned ?? 0;

  bool _hasDueWords() {
    final DailyReviewState review = ref.read(dailyReviewProvider);
    final DateTime now = ref.read(reviewClockProvider)();
    return ref.read(reviewSourcesProvider).any((ReviewSource source) {
      final ReviewRecord? record = review.records[source.key];
      return source.kind == ReviewKind.word &&
          !source.key.startsWith('recommended:') &&
          record != null && !record.isNew && !record.card.due.isAfter(now);
    });
  }

  TodayLearningStep? _nextLearningStep(TodayJourneyStore store) {
    final TodayStudyPlan plan = store.studyPlan;
    final SyllabusBooksState books = ref.read(syllabusBooksProvider);
    final SyllabusBook? book = books.activeBook;
    final DailyReviewState review = ref.read(dailyReviewProvider);
    final int learned = _newWordsToday();
    return store.learningOrder.where((TodayLearningStep step) => switch (step) {
      TodayLearningStep.newWords =>
        !plan.vocabTrackDone && learned < plan.vocabCount &&
            learned < review.dailyNewLimit &&
            (book == null || !books.isComplete(book)),
      TodayLearningStep.video => !plan.videoDone,
      TodayLearningStep.reviewWords => _hasDueWords(),
      TodayLearningStep.reading => !plan.readingDone,
      TodayLearningStep.photoChat => !store.oralIntroDone,
    }).firstOrNull;
  }

  Future<void> _editLearningOrder(TodayJourneyStore store) async {
    final List<TodayLearningStep> order =
        List<TodayLearningStep>.of(store.learningOrder);
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter refresh) => Column(
            children: <Widget>[
              const ListTile(title: Text('拖动调整今日学习顺序')),
              Expanded(
                child: ReorderableListView(
                  onReorderItem: (int oldIndex, int newIndex) => refresh(() {
                    order.insert(newIndex, order.removeAt(oldIndex));
                  }),
                  children: <Widget>[
                    for (final TodayLearningStep step in order)
                      ListTile(key: ValueKey(step), title: Text(step.label)),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('保存顺序'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    await store.saveLearningOrder(order);
    if (mounted) setState(() {});
  }

  Future<void> _runNext() async {
    if (_busy) return;
    setState(() => _busy = true);
    final DateTime today = DateTime.now();
    final String account = ref.read(studyAccountProvider);
    final TodayJourneyStore store = TodayJourneyStore(account, today);
    try {
      await _ensureQuotas(store);
      if (!mounted || !store.studyPlan.quotasConfigured) return;
      await _syncProgress(store);
      while (mounted && ref.read(studyAccountProvider) == account) {
        final TodayLearningStep? step = _nextLearningStep(store);
        if (step == null) {
          await _seedTomorrow(account, today, store);
          await store.saveStage(JourneyStage.done);
          return;
        }
        await store.saveStage(JourneyStage.learn);
        if (!mounted) return;
        if (step == TodayLearningStep.photoChat) {
          await offerTodayOralIntro(
            context,
            ref,
            alreadyDone: store.oralIntroDone,
            markDone: store.markOralIntroDone,
          );
        } else if ((step, store.selectedMaterial(TodayStudyTrack.video))
            case (TodayLearningStep.video, final JourneyActivity selected)) {
          await _openSelectedVideo(selected);
        } else {
          final String route = switch (step) {
            TodayLearningStep.newWords => _vocabPursuit()!.route,
            TodayLearningStep.video => _videoPursuit()?.route ?? '/library',
            TodayLearningStep.reviewWords => '/review/session?due=1&kind=word',
            TodayLearningStep.reading => store.selectedMaterial(TodayStudyTrack.reading)?.route ??
                _readingPursuit()!.route,
            TodayLearningStep.photoChat => '/digital-human?sceneMenu=1',
          };
          await context.push(route);
        }
        if (!mounted || ref.read(studyAccountProvider) != account) return;
        await _syncProgress(store);
        if (!mounted || _nextLearningStep(store) == step) return;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRefreshBatch({TodayStudyTrack? trackHint}) async {
    final List<ScoredLearnCandidate> picks = _refreshCandidates();
    if (!mounted) return;
    final ScoredLearnCandidate? chosen =
        await showModalBottomSheet<ScoredLearnCandidate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.appWhite,
      builder: (_) => _RefreshBatchSheet(
        candidates: picks,
        onFeedback: (ScoredLearnCandidate item, LearnFeedback feedback) async {
          await JourneyFeedbackStore(
            ref.read(studyAccountProvider),
          ).apply(
            id: item.candidate.route,
            module: item.candidate.module,
            feedback: feedback,
          );
        },
      ),
    );
    if (!mounted || chosen == null) return;
    final TodayJourneyStore store = TodayJourneyStore(
      ref.read(studyAccountProvider),
      DateTime.now(),
    );
    final TodayStudyTrack track = switch (chosen.candidate.module) {
      LearnModule.video => TodayStudyTrack.video,
      LearnModule.vocab => TodayStudyTrack.vocab,
      LearnModule.reading || LearnModule.oral => TodayStudyTrack.reading,
    };
    await store.saveProgress(lastTrack: trackHint ?? track);
    await store.saveActivity(journeyActivity(
      route: chosen.candidate.route,
      title: chosen.candidate.title,
    ));
    await context.push(chosen.candidate.route);
    if (mounted) setState(() {});
  }

  List<ScoredLearnCandidate> _refreshCandidates() {
    final LearnerSkillProfile profile = ref.read(learnerSkillProfileProvider);
    final OnboardingProfile onboarding = ref.read(onboardingProvider);
    final JourneyFeedbackStore feedback = JourneyFeedbackStore(
      ref.read(studyAccountProvider),
    );
    final AcquirePreferencesDto prefs = ref.read(learningPreferencesProvider);
    final List<LibraryCourseData> courses = ref.read(libraryCatalogProvider);
    final ReadingLibraryState reading = ref.read(readingLibraryProvider);
    final List<LearnCandidate> candidates = <LearnCandidate>[];

    // Up to 5 video picks via level + interest ranking.
    final List<LearnCandidate> videoPool = <LearnCandidate>[];
    for (final LibraryCourseData course in courses) {
      for (final LibraryEpisodeItem episode in course.episodes) {
        if (episode.videoMissing) continue;
        final String route = '/episodes/${Uri.encodeComponent(episode.id)}';
        if (feedback.isHidden(route)) continue;
        videoPool.add(
          LearnCandidate(
            id: route,
            title: episode.title,
            route: route,
            module: LearnModule.video,
            contentBand: contentBandOrFallback(
              course.level,
              profile.recommendationEstimate(LearnerSkill.listening).band,
            ),
            interestMatch: onboarding.focusId == 'video' ||
                (onboarding.focusId?.isEmpty ?? true),
          ),
        );
      }
    }
    final List<ScoredLearnCandidate> rankedVideo = rankLearnCandidates(
      candidates: videoPool,
      profile: profile,
      difficultyShift: feedback.difficultyShifts,
    );
    for (final ScoredLearnCandidate item in rankedVideo.take(5)) {
      candidates.add(item.candidate);
    }

    // Reading candidates (several).
    final List<LearnCandidate> readingPool = <LearnCandidate>[];
    for (final ReadingDoc doc in reading.all) {
      final String route = '/reading/${Uri.encodeComponent(doc.id)}';
      if (feedback.isHidden(route)) continue;
      readingPool.add(
        LearnCandidate(
          id: route,
          title: doc.displayTitle,
          route: route,
          module: LearnModule.reading,
          contentBand: contentBandOrFallback(
            doc.level,
            profile.recommendationEstimate(LearnerSkill.reading).band,
          ),
          interestMatch: onboarding.focusId == 'reading',
          pursuit: reading.continueDoc?.id == doc.id,
        ),
      );
    }
    if (readingPool.isEmpty) {
      final FocusRecommendation article = buildFocusRecommendation(
        profile: onboarding.copyWith(focusId: 'reading'),
        prefs: prefs,
        courses: const <LibraryCourseData>[],
        readingDocs: reading.all,
        activeBook: null,
        levelOverride:
            profile.recommendationEstimate(LearnerSkill.reading).band,
      );
      if (article.route.startsWith('/reading/')) {
        readingPool.add(
          LearnCandidate(
            id: article.route,
            title: article.title,
            route: article.route,
            module: LearnModule.reading,
            contentBand: contentBandOrFallback(
              article.contentBand,
              profile.recommendationEstimate(LearnerSkill.reading).band,
            ),
            interestMatch: true,
          ),
        );
      }
    }
    final List<ScoredLearnCandidate> rankedReading = rankLearnCandidates(
      candidates: readingPool,
      profile: profile,
      difficultyShift: feedback.difficultyShifts,
    );
    for (final ScoredLearnCandidate item in rankedReading.take(5)) {
      candidates.add(item.candidate);
    }

    // Vocab: prefer active book level band.
    final SyllabusBooksState books = ref.read(syllabusBooksProvider);
    final SyllabusBook? selected = books.activeBook;
    final SyllabusBook? active =
        selected != null && !books.isComplete(selected) ? selected : null;
    candidates.add(
      LearnCandidate(
        id: active?.id ?? 'vocab-books',
        title: active == null ? '打开词书挑一组新词' : '继续背 · ${active.title}',
        route: active == null
            ? '/words/syllabus'
            : syllabusBookSessionRoute(active.id),
        module: LearnModule.vocab,
        contentBand: profile.estimate(LearnerSkill.vocab).band,
        interestMatch: onboarding.focusId == 'vocab',
        pursuit: active != null,
        notInterested: feedback.isHidden('/words'),
      ),
    );

    return rankLearnCandidates(
      candidates: candidates,
      profile: profile,
      difficultyShift: feedback.difficultyShifts,
    );
  }

  Future<void> _openSelectedVideo(JourneyActivity selected) async {
    final Uri uri = Uri.parse(selected.route);
    final String? url = uri.queryParameters['watchUrl'];
    String? episodeId = uri.pathSegments.firstOrNull == 'episodes'
        ? uri.pathSegments.lastOrNull : null;
    if (url != null) {
      try {
        episodeId = await ensureEnglishBrowseEpisode(ref, item: AcquireDailyFeedItemDto(
          id: url, bvid: '', title: selected.title, watchUrl: url, author: '',
        ));
      } catch (_) {
        // The source may be temporarily unavailable.
      }
    }
    if (!mounted) return;
    final String? courseId = uri.queryParameters['courseId'];
    final LibraryCourseData? course = ref.read(libraryCatalogProvider).where(
      (LibraryCourseData course) => course.id == courseId ||
          (episodeId != null && course.episodes.any((episode) => episode.id == episodeId)),
    ).firstOrNull;
    final LibraryEpisodeItem? episode = course == null ? null : nextStudyEpisode(
      course,
      lastEpisodeId: ref.read(lastLearningEpisodeProvider),
    );
    final String? id = episode?.id ?? (course == null ? episodeId : null);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂时无法播放这项素材，可重试或重新选择。')),
      );
      return;
    }
    await context.push(Uri(
      pathSegments: <String>['', 'episodes', id],
      queryParameters: course == null ? null : <String, String>{'courseId': course.id},
    ).toString());
  }

  Future<void> _chooseStudyMaterial() async {
    final String account = ref.read(studyAccountProvider);
    final TodayJourneyStore store = TodayJourneyStore(account, DateTime.now());
    final List<JourneyActivity> videos =
        store.selectedMaterials(TodayStudyTrack.video);
    final List<JourneyActivity> readings =
        store.selectedMaterials(TodayStudyTrack.reading);
    final String? route = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.appWhite,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text('选择今日学习内容')),
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('选择要看的视频'),
                subtitle: Text(
                  videos.isEmpty
                      ? '尚未选择'
                      : videos.map((JourneyActivity e) => e.title).join(' · '),
                ),
                onTap: () => Navigator.pop(sheetContext, 'select-video'),
              ),
              ListTile(
                leading: const Icon(Icons.auto_stories_outlined),
                title: const Text('选择要读的书'),
                subtitle: Text(
                  readings.isEmpty
                      ? '尚未选择'
                      : readings.map((JourneyActivity e) => e.title).join(' · '),
                ),
                onTap: () => Navigator.pop(sheetContext, 'select-reading'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('自由拍照学词'),
                onTap: () => Navigator.pop(sheetContext, '/digital-human?sceneMenu=1'),
              ),
            ],
          ),
        ),
      ),
    );
    if (route == null || !mounted || ref.read(studyAccountProvider) != account) {
      return;
    }
    if (route == 'select-video') {
      // Library adds materials itself (multi-select + duration confirm).
      await context.push('/library?selectForStudy=1');
      if (mounted) setState(() {});
      return;
    }
    if (route == 'select-reading') {
      await context.push('/reading?selectForStudy=1');
      if (mounted) setState(() {});
      return;
    }
    await context.push(route);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final String account = ref.watch(studyAccountProvider);
    ref
      ..watch(continueLearningTargetProvider)
      ..watch(readingLibraryProvider)
      ..watch(learningPreferencesProvider)
      ..watch(currentLearningKindProvider)
      ..watch(libraryCatalogProvider)
      ..watch(learningActivityProvider)
      ..watch(todayPathProvider)
      ..watch(dailyReviewProvider)
      ..watch(learnerSkillProfileProvider)
      ..watch(syllabusBooksProvider);
    final DateTime today = DateTime.now();
    final TodayJourneyStore store = TodayJourneyStore(account, today);
    _scheduleProgressSync(store);
    final TodayStudyPlan plan = store.studyPlan;
    final int due = _unifiedDueCount();
    final TodayLearningStep? nextStep = _nextLearningStep(store);
    final List<JourneyActivity> todayVideos =
        store.selectedMaterials(TodayStudyTrack.video);
    final List<JourneyActivity> todayReadings =
        store.selectedMaterials(TodayStudyTrack.reading);

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
                  plan.quotasConfigured
                      ? (nextStep == null ? '今日计划已完成' : '按计划接着学')
                      : '先定今天学多少',
                  style: TextStyle(
                    color: AppDesignTokens.brandGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _chooseStudyMaterial,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: AppDesignTokens.textPrimary,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('今日学习', style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      )),
                      Icon(Icons.chevron_right),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/digital-human?sceneMenu=1'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('自由拍照学词'),
                ),
                if (todayVideos.isNotEmpty)
                  Text(
                    '今日视频 · ${todayVideos.map((JourneyActivity e) => e.title).join(' · ')}',
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  ),
                if (todayReadings.isNotEmpty)
                  Text(
                    '今日读物 · ${todayReadings.map((JourneyActivity e) => e.title).join(' · ')}',
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  ),
                if (plan.quotasConfigured) ...<Widget>[
                  const SizedBox(height: 16),
                  _QuotaProgressRow(
                    label: '视频',
                    detail: plan.videoMinutes <= 0
                        ? '今日跳过'
                        : '${(plan.videoDoneMs / 60000).floor()}/${plan.videoMinutes} 分钟',
                    progress: plan.videoMinutes <= 0 ? 0 : plan.videoProgress,
                    skipped: plan.videoMinutes <= 0,
                    done: plan.videoDone,
                  ),
                  const SizedBox(height: 8),
                  _QuotaProgressRow(
                    label: '单词',
                    detail: plan.vocabCount <= 0
                        ? '今日跳过'
                        : '${plan.vocabDone}/${plan.vocabCount} 个',
                    progress: plan.vocabCount <= 0 ? 0 : plan.vocabProgress,
                    skipped: plan.vocabCount <= 0,
                    done: plan.vocabTrackDone,
                  ),
                  if (plan.quotasConfigured &&
                      plan.vocabCount > 0 &&
                      plan.vocabTrackDone) ...<Widget>[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const Key('home-vocab-bonus'),
                        onPressed: _busy
                            ? null
                            : () => unawaited(_addMoreVocab(store)),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('再背几个'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _QuotaProgressRow(
                    label: '阅读',
                    detail: plan.readingWords <= 0
                        ? '今日跳过'
                        : '${plan.readingWordsDone}/${plan.readingWords} 词',
                    progress:
                        plan.readingWords <= 0 ? 0 : plan.readingProgress,
                    skipped: plan.readingWords <= 0,
                    done: plan.readingDone,
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _chooseStudyMaterial,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppDesignTokens.brandGreen,
                      foregroundColor: AppDesignTokens.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      '选择学习内容',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                Text(
                  store.learningOrder.map((TodayLearningStep step) => step.label).join(' → '),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _editLearningOrder(store),
                  child: const Text('调整学习顺序'),
                ),
                FilledButton(
                  onPressed: _busy || (plan.quotasConfigured && nextStep == null)
                      ? null
                      : _runNext,
                  child: Text(nextStep == null && plan.quotasConfigured
                      ? '今日计划已完成'
                      : nextStep == null || !plan.quotasConfigured
                          ? '继续学习'
                          : '继续学习 · ${nextStep.label}'),
                ),
                if (plan.quotasConfigured) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: _busy ? null : () => _editQuotas(store),
                        child: Text(
                          '改配额',
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _busy ? null : () => _openRefreshBatch(),
                        child: Text(
                          '刷一批',
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: _busy
                ? null
                : () => context.push(
                      due > 0 ? '/review/session?due=1' : '/review',
                    ),
            child: Text(
              due > 0 ? '去今日复习 · 到期 $due' : '自己去复习 / 词书',
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addMoreVocab(TodayJourneyStore store) async {
    final int? n = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppDesignTokens.appWhite,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '再背几个？',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '今日额度加完后可继续新学，不影响明天的基础配额。',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final int n in const <int>[5, 10, 15, 20, 30])
                      ActionChip(
                        label: Text('+$n'),
                        onPressed: () => Navigator.pop(sheetContext, n),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (n == null || !mounted) return;
    final int effective = await store.addVocabBonus(n);
    await ref.read(wordReviewSettingsProvider.notifier).setDailyNewLimit(
          effective.clamp(0, 150),
        );
    if (mounted) setState(() {});
  }
}

class _QuotaProgressRow extends StatelessWidget {
  const _QuotaProgressRow({
    required this.label,
    required this.detail,
    required this.progress,
    required this.skipped,
    required this.done,
  });

  final String label;
  final String detail;
  final double progress;
  final bool skipped;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(
              color: AppDesignTokens.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: skipped ? 0 : progress.clamp(0.0, 1.0),
              minHeight: 8,
              color: done
                  ? AppDesignTokens.brandGreen
                  : AppDesignTokens.brandGreen.withValues(alpha: 0.7),
              backgroundColor: AppDesignTokens.borderGray.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 88,
          child: Text(
            skipped ? '跳过' : (done ? '已完成' : detail),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: done
                  ? AppDesignTokens.brandGreen
                  : AppDesignTokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}


class _TodayQuotaSheet extends StatefulWidget {
  const _TodayQuotaSheet({
    required this.videoMinutes,
    required this.vocabCount,
    required this.readingWords,
  });

  final int videoMinutes;
  final int vocabCount;
  final int readingWords;

  @override
  State<_TodayQuotaSheet> createState() => _TodayQuotaSheetState();
}

class _TodayQuotaSheetState extends State<_TodayQuotaSheet> {
  late int _video = widget.videoMinutes;
  late int _vocab = widget.vocabCount;
  late int _reading = widget.readingWords;

  Widget _chipRow({
    required String label,
    required List<int> presets,
    required int value,
    required String unit,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('跳过'),
              selected: value == 0,
              onSelected: (_) => onChanged(0),
            ),
            for (final int preset in presets)
              ChoiceChip(
                label: Text('$preset$unit'),
                selected: value == preset,
                onSelected: (_) => onChanged(preset),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canSave = _video > 0 || _vocab > 0 || _reading > 0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '今天学多少？',
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '三轨可同时开；填 0 表示今天不做这一轨。',
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            _chipRow(
              label: '视频',
              presets: const <int>[15, 20, 30],
              value: _video,
              unit: ' 分钟',
              onChanged: (int v) => setState(() => _video = v),
            ),
            const SizedBox(height: 14),
            _chipRow(
              label: '今天背几个单词',
              presets: const <int>[5, 10, 15, 20, 30, 50],
              value: _vocab,
              unit: ' 个',
              onChanged: (int v) => setState(() => _vocab = v),
            ),
            const SizedBox(height: 14),
            _chipRow(
              label: '阅读',
              presets: const <int>[300, 500, 800],
              value: _reading,
              unit: ' 词',
              onChanged: (int v) => setState(() => _reading = v),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: !canSave
                    ? null
                    : () => Navigator.pop(context, (
                          videoMinutes: _video,
                          vocabCount: _vocab,
                          readingWords: _reading,
                        )),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.brandGreen,
                  foregroundColor: AppDesignTokens.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  '开始今日学习',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefreshBatchSheet extends StatelessWidget {
  const _RefreshBatchSheet({
    required this.candidates,
    required this.onFeedback,
  });

  final List<ScoredLearnCandidate> candidates;
  final Future<void> Function(ScoredLearnCandidate, LearnFeedback) onFeedback;

  @override
  Widget build(BuildContext context) {
    final List<ScoredLearnCandidate> videos = candidates
        .where((ScoredLearnCandidate c) => c.candidate.module == LearnModule.video)
        .take(5)
        .toList();
    final List<ScoredLearnCandidate> readings = candidates
        .where(
          (ScoredLearnCandidate c) => c.candidate.module == LearnModule.reading,
        )
        .take(5)
        .toList();
    final List<ScoredLearnCandidate> vocabs = candidates
        .where((ScoredLearnCandidate c) => c.candidate.module == LearnModule.vocab)
        .take(2)
        .toList();

    Widget section(String title, List<ScoredLearnCandidate> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              title,
              style: TextStyle(
                color: AppDesignTokens.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          for (final ScoredLearnCandidate item in items)
            ListTile(
              title: Text(
                item.candidate.title,
                style: TextStyle(color: AppDesignTokens.textPrimary),
              ),
              subtitle: Text(
                item.reason,
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
              trailing: IconButton(
                icon: Icon(
                  Icons.swap_horiz,
                  color: AppDesignTokens.textSecondary,
                ),
                onPressed: () async {
                  await onFeedback(item, LearnFeedback.swap);
                },
              ),
              onLongPress: () async {
                await onFeedback(item, LearnFeedback.notInterested);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('七天内不再默认推荐这条')),
                  );
                }
              },
              onTap: () => Navigator.pop(context, item),
            ),
        ],
      );
    }

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '刷一批',
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '按当前水平与兴趣推荐。点选一条开始；长按可「不感兴趣」。',
                style: TextStyle(
                  color: AppDesignTokens.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            section('视频 · 最多 5 条', videos),
            section('阅读', readings),
            section('背单词', vocabs),
            if (videos.isEmpty && readings.isEmpty && vocabs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '暂时没有匹配的推荐，去书库或视频库逛逛吧。',
                  style: TextStyle(color: AppDesignTokens.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
