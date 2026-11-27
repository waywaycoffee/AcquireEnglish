import '../../daily_path/data/today_journey_store.dart';
import '../../daily_path/presentation/today_path_provider.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/account_storage.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../community/domain/cafe_adventure.dart';
import '../../community/presentation/publish_learning_result_screen.dart';
import '../../community/presentation/study_play_screen.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../player/presentation/widgets/pronunciation_assessment_dialog.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/audio/success_sfx.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/domain/subtitle_letter_case.dart';
import '../../shared/domain/word_lookup_entry.dart';
import '../../review_hub/presentation/review_recall_theme.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../learner_model/presentation/learner_skill_profile_provider.dart';
import '../../sync/data/study_activity_service.dart';
import '../../phrases/presentation/phrase_book_provider.dart';
import '../../words/domain/foundation_media.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../../words/domain/syllabus_book.dart';
import '../../words/domain/vocab_entry.dart';
import '../../words/domain/word_morphology.dart';
import '../../words/domain/word_review_settings.dart';
import '../../words/presentation/foundation_media_provider.dart';
import '../../reading/data/reading_gloss.dart';
import '../../words/presentation/learner_level_provider.dart';
import '../../words/presentation/syllabus_books_provider.dart';
import '../../words/presentation/vocabulary_placement_provider.dart';
import '../../words/presentation/widgets/phonics_syllable_blocks.dart';
import '../../words/presentation/word_book_provider.dart';
import '../../words/presentation/word_review_settings_provider.dart';
import '../../words/presentation/word_review_settings_sheet.dart';
import '../../words/presentation/widgets/word_root_breakdown_panel.dart';
import '../../micro_review/presentation/micro_review_controller.dart';
import '../data/missed_review_book.dart';
import '../data/review_session_draft.dart';
import '../data/word_encounter_store.dart';
import '../domain/cloze_sentence.dart';
import '../domain/daily_review.dart';
import '../domain/weakest_rating.dart';
import 'daily_review_provider.dart';
import 'foundation_media_video_sheet.dart';
import 'fsrs_sd_meter.dart';
import 'new_word_session.dart';
import 'review_source_context_panel.dart';
import 'review_spelling_screen.dart';
import 'word_occurrences_sheet.dart';

class DailyReviewScreen extends ConsumerStatefulWidget {
  const DailyReviewScreen({
    super.key,
    this.session = false,
    this.practice = false,
    this.practiceKind,
    this.learnNewOnly = false,
    this.dueOnly = false,
    this.journeyReview = false,
    this.expressions = false,
    this.recommended = false,
    this.missedOnly = false,
    this.focusWord,
    this.weakOnly = false,
    this.sourceLabel,
    this.sourceEpisodeId,
    this.todayTaskId,
    this.syllabusOnly = false,
    this.syllabusBookId,
  });
  final bool session;
  final bool recommended;
  final bool practice;
  final bool expressions;
  final ReviewKind? practiceKind;

  /// New-learn only (词书封面开背): waiting cards within today's new quota.
  final bool learnNewOnly;

  /// Due reviews only (复习 tab): skip introducing new book words.
  final bool dueOnly;
  final bool journeyReview;

  /// Only cards currently in the missed-word book.
  final bool missedOnly;

  /// Prefer / restrict to this lemma (word detail “复习此词”).
  final String? focusWord;
  final bool weakOnly;
  final String? sourceLabel;
  final String? sourceEpisodeId;
  final String? todayTaskId;

  /// Only syllabus book cards (`syllabus:…` keys).
  final bool syllabusOnly;

  /// When set with [syllabusOnly], restrict to one book id.
  final String? syllabusBookId;
  @override
  ConsumerState<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends ConsumerState<DailyReviewScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _activeTimer;
  int _activeMilliseconds = 0;
  DateTime _lastInteraction = DateTime.now();
  bool _draftInitialized = false;

  final ScrollController _sessionScroll = ScrollController();
  String? _currentKey;
  List<String>? _deckKeys;
  List<ReviewSource>? _newWordBatch;
  final Set<String> _completedKeys = <String>{};
  final Set<String> _missedKeys = <String>{};
  final Map<String, int> _freshPasses = <String, int>{};
  String? _passStorageKey;
  final Map<String, List<String>> _choices = <String, List<String>>{};
  final Map<String, String> _reviewMeanings = <String, String>{};
  final Set<String> _requestedMeanings = <String>{};
  final Set<String> _prefetchedAudio = <String>{};
  final OfflineWordDictionary _reviewDictionary = OfflineWordDictionary();
  String? _playedWord;
  bool _retryWord = false;
  bool _forward = true;
  bool _revealed = false;
  /// Expanded syllable / phonics coach under the headword.
  bool _phonicsOpen = false;
  bool _saving = false;
  ReviewKind? _overviewKind;
  bool _reportedPlanProgress = false;
  final Map<String, fsrs.Rating> _sessionRatings = <String, fsrs.Rating>{};
  /// Per-card override: episodeId (preferred) or related source label.
  final Map<String, String> _contextPick = <String, String>{};

  bool _speaking = false;
  int _speechSequence = 0;
  WordPronunciationService? _speech;

  /// Index into [WordReviewSettings.orderedModes] for the current word card.
  int _modeStep = 0;
  final Map<String, List<fsrs.Rating>> _stageRatings =
      <String, List<fsrs.Rating>>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final DailyReviewNotifier review = ref.read(dailyReviewProvider.notifier);
      review.scheduleCloudBackup();
      // Soft encounter grades only during an active session, not overview open.
      if (widget.session) {
        unawaited(review.drainEncounterSoftCredits());
      }
    });
    _activeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          widget.session &&
          ModalRoute.of(context)?.isCurrent == true &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed) &&
          DateTime.now().difference(_lastInteraction) <
              const Duration(seconds: 60) &&
          !(_deckKeys?.every(_completedKeys.contains) ?? false)) {
        _activeMilliseconds += 1000;
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && mounted)
      unawaited(_persistDraft());
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      ref.read(dailyReviewProvider.notifier).scheduleCloudBackup();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _activeTimer?.cancel();
    _sessionScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _stopSpeech();
    super.dispose();
  }

  List<ReviewSource> _filteredSources() {
    Iterable<ReviewSource> sources = ref.watch(reviewSourcesProvider);
    if (widget.syllabusOnly) {
      final String? bookId = widget.syllabusBookId?.trim();
      final Set<String> bookLemmas = <String>{};
      if (bookId != null && bookId.isNotEmpty) {
        final SyllabusBook? book =
            ref.read(syllabusBooksProvider).bookById(bookId);
        if (book != null) {
          for (final SyllabusWord word in book.words) {
            final String lemma = word.word.trim().toLowerCase();
            if (lemma.isNotEmpty) bookLemmas.add(lemma);
          }
        }
      }
      sources = sources.where((ReviewSource source) {
        // Book-scoped: that book's cards + favorites that also appear in it.
        if (source.key.startsWith('syllabus:')) {
          if (bookId == null || bookId.isEmpty) return true;
          return source.key.startsWith('syllabus:$bookId:');
        }
        if (source.key.startsWith('entry:')) {
          if (bookLemmas.isEmpty) return bookId == null || bookId.isEmpty;
          final String? lemma = lemmaFromReviewKey(source.key);
          return lemma != null && bookLemmas.contains(lemma);
        }
        return false;
      });
    } else {
      sources = sources.where(
        (ReviewSource source) =>
            source.key.startsWith('recommended:') == widget.recommended,
      );
    }
    if (widget.expressions) {
      sources = sources.where(
        (ReviewSource source) => source.kind != ReviewKind.sentence,
      );
    } else if (widget.practiceKind != null) {
      sources = sources.where(
        (ReviewSource source) => source.kind == widget.practiceKind,
      );
    }
    final String? focus = widget.focusWord?.trim().toLowerCase();
    if (focus != null && focus.isNotEmpty) {
      sources = sources.where(
        (ReviewSource source) =>
            source.kind == ReviewKind.word &&
            source.question.trim().toLowerCase() == focus,
      );
    }
    if (widget.weakOnly) {
      final DailyReviewState review = ref.watch(dailyReviewProvider);
      sources = sources.where((ReviewSource source) {
        final int? last = review.records[source.key]?.lastRating;
        return last == fsrs.Rating.again.index ||
            last == fsrs.Rating.hard.index;
      });
    }
    if (!widget.session && _overviewKind != null) {
      sources = sources.where(
        (ReviewSource source) => source.kind == _overviewKind,
      );
    }
    if (widget.sourceLabel != null || widget.sourceEpisodeId != null) {
      sources = sources.where(
        (ReviewSource source) =>
            (widget.sourceEpisodeId != null &&
                (source.episodeId == widget.sourceEpisodeId ||
                    source.relatedSources.any(
                      (ReviewSourceLink link) =>
                          link.episodeId == widget.sourceEpisodeId,
                    ))) ||
            (widget.sourceLabel != null &&
                (source.sourceLabel == widget.sourceLabel ||
                    source.relatedSources.any(
                      (ReviewSourceLink link) =>
                          link.label == widget.sourceLabel ||
                          link.displayLabel == widget.sourceLabel,
                    ))),
      );
    }
    return sources
        .map(
          (ReviewSource source) => source.forContext(
            label: widget.sourceLabel,
            episode: widget.sourceEpisodeId,
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MicroReviewUiState>(microReviewProvider, (
      MicroReviewUiState? prev,
      MicroReviewUiState next,
    ) {
      final String? msg = next.message;
      if (msg == null || msg == prev?.message) return;
      if (msg == 'open_review') {
        handleMicroReviewOpenMessage(context, ref);
        return;
      }
      if (msg.startsWith('本轮')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    });
    ref.listen<String>(studyAccountProvider, (String? previous, String next) {
      if (previous != null && previous != next) {
        _stopSpeech();
        setState(() {
          _deckKeys = null;
          _newWordBatch = null;
          _currentKey = null;
          _completedKeys.clear();
          _sessionRatings.clear();
          _missedKeys.clear();
          _stageRatings.clear();
          _draftInitialized = false;
          _activeMilliseconds = 0;
        });
      }
    });
    final DailyReviewState state = ref.watch(dailyReviewProvider);
    // Prefetch without watching: a watch here can markNeedsBuild when an
    // overlay flips TickerMode and resumes paused Riverpod subscriptions.
    ref.read(foundationMediaManifestProvider);
    final List<ReviewSource> sources = _filteredSources();
    final DateTime now = ref.read(reviewClockProvider)();
    if (widget.session) _restoreWordPasses(now);
    final ReviewPlan plan = reviewPlanForLearnerLevel(
      state: state,
      sources: sources,
      now: now,
      threshold: ref.watch(adaptiveReadingFreqThresholdProvider),
      lexicon: ref.watch(readingFrequencyLexiconProvider).asData?.value,
    );
    final bool recallChrome = widget.session;
    return PadScaffold(
      currentDestination: AppNavDestination.home,
      showContinueLearning: false,
      showNavigation: !widget.session,
      backgroundColor: recallChrome ? ReviewRecallTheme.bg : null,
      topBar: PadTopBar(
        title: widget.syllabusOnly
            ? '学习书库'
            : widget.recommended
            ? '推荐背词'
            : widget.missedOnly
            ? '错词本'
            : widget.session
            ? (widget.practice
                  ? (widget.focusWord != null && widget.focusWord!.isNotEmpty
                        ? '复习此词'
                        : '自由复习')
                  : (_revealed ? '核对与评分' : '主动回忆'))
            : '每日复习',
        description: widget.session
            ? (widget.learnNewOnly
                  ? '点词书封面开背 · 背过的词会进入复习'
                  : widget.dueOnly
                  ? '复习已学过的词 · 新词请去词书架点封面'
                  : widget.syllabusOnly
                  ? '自建考纲核心词 / 导入词书，走同一套 FSRS。'
                  : widget.missedOnly
                  ? '优先重练标记为「忘记」的词。'
                  : widget.practice
                  ? '随时再练，不改变复习计划。'
                  : null)
            : '复习单词、短语和收藏句子。',
        leading: widget.session
            ? PadBackButton(onPressed: _leaveSession, tooltip: '返回复习首页')
            : null,
        actions: <Widget>[
          if (widget.session &&
              sources.any(
                (ReviewSource source) => source.kind == ReviewKind.word,
              ))
            IconButton(
              tooltip: '让计划适合你',
              onPressed: _saving
                  ? null
                  : () => showWordReviewSettingsSheet(context),
              icon: Icon(
                Icons.tune_rounded,
                color: recallChrome ? ReviewRecallTheme.textSecondary : null,
              ),
            ),
        ],
        trailing: widget.session
            ? TextButton(
                onPressed: _saving ? null : _leaveSession,
                style: TextButton.styleFrom(
                  foregroundColor: recallChrome
                      ? ReviewRecallTheme.lime
                      : null,
                ),
                child: const Text('稍后继续'),
              )
            : IconButton(
                tooltip: '复习设置',
                onPressed: _saving || state.storageError != null
                    ? null
                    : () => _showSettings(state.dailyNewLimit),
                icon: const Icon(Icons.tune_rounded),
              ),
      ),
      body: widget.session && state.storageError == null
          ? Listener(
              onPointerDown: (_) => _lastInteraction = DateTime.now(),
              child: _buildSessionBody(state, sources, plan, now),
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool compact = constraints.maxWidth < 600;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 32,
                    12,
                    compact ? 16 : 32,
                    32,
                  ),
                  children: <Widget>[
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (state.storageError != null)
                              _ReviewSurface(
                                child: Text(
                                  state.storageError!,
                                  style: TextStyle(
                                    color: Color(0xFF9B2828),
                                    height: 1.6,
                                  ),
                                ),
                              )
                            else
                              _buildOverview(state, sources, plan, now),
                            const SizedBox(height: 24),
                            _buildQueueInfo(plan, state.dailyNewLimit),
                            const SizedBox(height: 32),
                            _buildExplanation(),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  ReviewSessionDraftStore get _draftStore => ReviewSessionDraftStore(
    account: ref.read(studyAccountProvider),
    scope: jsonEncode(<Object?>[
      widget.practice,
      widget.practiceKind?.name ?? _overviewKind?.name,
      widget.expressions,
      widget.recommended,
      widget.missedOnly,
      widget.focusWord,
      widget.weakOnly,
      widget.sourceLabel,
      widget.sourceEpisodeId,
      widget.syllabusOnly,
      widget.syllabusBookId,
      widget.learnNewOnly,
      widget.dueOnly,
      if (widget.journeyReview) true,
    ]),
  );

  Future<void> _persistDraft() async {
    if (!mounted || !widget.session || _deckKeys == null) return;
    final ReviewSessionDraftStore store = _draftStore;
    try {
      if (_deckKeys!.every(_completedKeys.contains)) {
        await store.clear();
        return;
      }
      final DailyReviewState state = ref.read(dailyReviewProvider);
      await store.save(
        ReviewSessionDraft(
          keys: List<String>.of(_deckKeys!),
          versions: <String, int>{
            for (final String key in _deckKeys!)
              if (state.records[key] != null) key: state.records[key]!.reviews,
          },
          completed: Set<String>.of(_completedKeys),
          ratings: _sessionRatings.map(
            (String key, fsrs.Rating value) =>
                MapEntry<String, int>(key, value.index),
          ),
          current: _currentKey,
          updatedAt: ref.read(reviewClockProvider)(),
          activeMilliseconds: _activeMilliseconds,
        ),
      );
    } catch (_) {
      if (mounted) _message('评分仍保存在复习记录中，但本轮位置未能保存。');
    }
  }

  String _sessionRoute({
    bool practice = false,
    String? label,
    String? episodeId,
  }) => Uri(
    path: SGRoute.reviewSession.route,
    queryParameters: <String, String>{
      if (practice) 'practice': '1',
      if (_overviewKind != null) 'kind': _overviewKind!.name,
      if (widget.recommended) 'deck': 'recommended',
      if (label != null) 'source': label,
      if (episodeId != null) 'sourceEpisode': episodeId,
    },
  ).toString();

  Future<void> _leaveSession({bool journeyCompleted = false}) async {
    if (_saving) return;
    await _persistDraft();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(journeyCompleted ? true : null);
    } else {
      // Deep-linked session has no stack; return to the review overview.
      context.go(SGRoute.review.route);
    }
  }

  List<ReviewRecord> _practiceRecords(
    DailyReviewState state,
    List<ReviewSource> sources,
    DateTime now,
  ) {
    final Set<String> active = sources
        .map((ReviewSource source) => source.key)
        .toSet();
    final List<ReviewRecord> learned = state.records.values
        .where(
          (ReviewRecord record) => active.contains(record.key) && !record.isNew,
        )
        .toList();
    final List<ReviewRecord> today = learned
        .where(
          (ReviewRecord record) =>
              record.card.lastReview != null &&
              reviewDayKey(record.card.lastReview!) == reviewDayKey(now),
        )
        .toList();
    return (today.isNotEmpty ? today : learned)
      ..sort((ReviewRecord a, ReviewRecord b) => a.order.compareTo(b.order));
  }

  void _prepareDeck(
    ReviewPlan plan,
    DailyReviewState state,
    List<ReviewSource> sources,
    DateTime now,
  ) {
    if (_deckKeys != null) return;
    final ReviewSessionDraft? draft = _draftStore.load(now);
    if (draft != null) {
      final Set<String> active = sources
          .map((ReviewSource source) => source.key)
          .toSet();
      final List<String> valid = draft.keys
          .where(
            (String key) =>
                active.contains(key) &&
                state.records.containsKey(key) &&
                (draft.completed.contains(key) ||
                    state.records[key]!.reviews == draft.versions[key]),
          )
          .toList();
      if (valid.any((String key) => !draft.completed.contains(key))) {
        _deckKeys = valid;
        _completedKeys.addAll(draft.completed.where(valid.contains));
        for (final MapEntry<String, int> row in draft.ratings.entries) {
          if (_completedKeys.contains(row.key) &&
              row.value >= 0 &&
              row.value < fsrs.Rating.values.length)
            _sessionRatings[row.key] = fsrs.Rating.values[row.value];
        }
        _missedKeys.addAll(
          _sessionRatings.entries
              .where(
                (MapEntry<String, fsrs.Rating> r) =>
                    r.value == fsrs.Rating.again || r.value == fsrs.Rating.hard,
              )
              .map((MapEntry<String, fsrs.Rating> r) => r.key),
        );
        _currentKey = valid.contains(draft.current)
            ? draft.current
            : valid.firstWhere((String key) => !_completedKeys.contains(key));
        _activeMilliseconds = draft.activeMilliseconds;
        return;
      }
    }
    final Set<String> activeKeys = sources
        .map((ReviewSource source) => source.key)
        .toSet();
    final MissedReviewBook missedBook = MissedReviewBook(
      account: ref.read(studyAccountProvider),
    );

    if (widget.missedOnly) {
      final List<String> missed = missedBook.prioritize(activeKeys);
      _deckKeys = missed.isNotEmpty
          ? missed
          : sources
                .map((ReviewSource s) => s.key)
                .where(state.records.containsKey)
                .toList();
      _currentKey = _deckKeys!.firstOrNull;
      return;
    }

    final ReviewKind? kind = widget.practiceKind;
    if (widget.practice &&
        (kind != null ||
            widget.expressions ||
            widget.sourceLabel != null ||
            widget.sourceEpisodeId != null ||
            widget.weakOnly)) {
      final List<String> keys = sources
          .map((ReviewSource source) => source.key)
          .where(state.records.containsKey)
          .toList();
      // Prefer focus word at the front when provided.
      final String? focusKey = widget.focusWord == null
          ? null
          : 'word:${widget.focusWord!.trim().toLowerCase()}';
      if (focusKey != null && keys.contains(focusKey)) {
        keys
          ..remove(focusKey)
          ..insert(0, focusKey);
      }
      _deckKeys = keys;
      _currentKey = _deckKeys!.firstOrNull;
      return;
    }
    if (widget.practice) {
      _deckKeys = _practiceRecords(
        state,
        sources,
        now,
      ).map((ReviewRecord record) => record.key).toList();
      _currentKey = _deckKeys!.firstOrNull;
      return;
    }

    final int configuredCap = ref
        .read(wordReviewSettingsProvider)
        .dailyReviewLimit
        .clamp(0, 500);
    final int reviewCap =
        widget.journeyReview && (configuredCap == 0 || configuredCap > 5)
        ? 5
        : configuredCap;
    List<ReviewRecord> due = <ReviewRecord>[...plan.due];
    final List<String> missedPriority = missedBook.prioritize(activeKeys);
    if (missedPriority.isNotEmpty) {
      due.sort((ReviewRecord a, ReviewRecord b) {
        final int ai = missedPriority.indexOf(a.key);
        final int bi = missedPriority.indexOf(b.key);
        final bool aMissed = ai >= 0;
        final bool bMissed = bi >= 0;
        if (aMissed && bMissed) return ai.compareTo(bi);
        if (aMissed) return -1;
        if (bMissed) return 1;
        return a.order.compareTo(b.order);
      });
    }
    if (reviewCap > 0 && due.length > reviewCap) {
      due = due.take(reviewCap).toList(growable: false);
    }
    final List<ReviewRecord> fresh = plan.waiting
        .take(plan.newAvailable)
        .toList();

    // Product split: 词书封面 = 新学；复习页 = 到期复习。
    if (widget.learnNewOnly) {
      _deckKeys = fresh.map((ReviewRecord r) => r.key).toList(growable: false);
      _currentKey = _deckKeys!.firstOrNull;
      return;
    }
    if (widget.dueOnly) {
      _deckKeys = due.map((ReviewRecord r) => r.key).toList(growable: false);
      _currentKey = _deckKeys!.firstOrNull;
      return;
    }

    final List<String> keys = <String>[];
    int credit = ref.read(dailyReviewProvider).dueReviewsSinceNew;
    int dueIndex = 0;
    int newIndex = 0;
    while (dueIndex < due.length || newIndex < fresh.length) {
      if (newIndex < fresh.length && (dueIndex == due.length || credit >= 4)) {
        keys.add(fresh[newIndex++].key);
        credit = 0;
      } else {
        keys.add(due[dueIndex++].key);
        credit++;
      }
    }
    _deckKeys = keys;
    _currentKey = keys.firstOrNull;
  }

  void _moveCard(int offset, List<String> keys) {
    if (_saving || keys.isEmpty) return;
    final int index = keys.indexOf(_currentKey ?? '');
    final int next = index + offset;
    if (next < 0 || next >= keys.length) return;
    _stopSpeech();
    if (_sessionScroll.hasClients) _sessionScroll.jumpTo(0);
    setState(() {
      _forward = offset > 0;
      _currentKey = keys[next];
      _playedWord = null;
      _phonicsOpen = false;
      _retryWord = false;
      _modeStep = 0;
      _revealed = _completedKeys.contains(_currentKey);
    });
    unawaited(_persistDraft());
  }

  Widget _buildSessionBody(
    DailyReviewState state,
    List<ReviewSource> sources,
    ReviewPlan plan,
    DateTime now,
  ) {
    if (widget.learnNewOnly && !widget.practice) {
      final SyllabusBooksState books = ref.watch(syllabusBooksProvider);
      final String? requestedId = widget.syllabusBookId;
      if (requestedId != null && requestedId != books.activeBookId) {
        return Center(
          child: Text(!books.ready
              ? '正在读取当前词书…'
              : '这本词书当前未选中，请前往词书架切换。'),
        );
      }
      final Set<String> waiting = plan.waiting.map((record) => record.key).toSet();
      final Set<String> seenWords = <String>{};
      _newWordBatch ??= sources
          .where((source) =>
              source.kind == ReviewKind.word &&
              waiting.contains(source.key) &&
              (source.cardType == null || source.cardType == 'recognize') &&
              seenWords.add(source.question.trim().toLowerCase()))
          .take(plan.newAvailable)
          .toList(growable: false);
      if (_newWordBatch!.isNotEmpty) {
        return NewWordSession(
          key: ValueKey(ref.read(studyAccountProvider)),
          words: _newWordBatch!,
        );
      }
    }
    _prepareDeck(plan, state, sources, now);
    if (!_draftInitialized) {
      _draftInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_persistDraft());
      });
    }
    final Map<String, ReviewSource> byKey = <String, ReviewSource>{
      for (final ReviewSource source in sources) source.key: source,
    };
    final List<String> keys = _deckKeys!
        .where(
          (String key) =>
              byKey.containsKey(key) && state.records.containsKey(key),
        )
        .toList();
    if (!keys.contains(_currentKey)) {
      _currentKey =
          keys
              .where((String key) => !_completedKeys.contains(key))
              .firstOrNull ??
          keys.firstOrNull;
      _revealed = _completedKeys.contains(_currentKey);
    }
    final int completed = keys.where(_completedKeys.contains).length;
    final bool finished = keys.isEmpty || completed == keys.length;
    final int index = keys.indexOf(_currentKey ?? '');
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    final Duration duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    final ReviewSource? visible = finished ? null : byKey[_currentKey];
    if (visible != null && visible.key != _playedWord) {
      _playedWord = visible.key;
      final List<ReviewSource> upcoming = <ReviewSource>[
        visible,
        if (index >= 0 && index + 1 < keys.length) byKey[keys[index + 1]]!,
      ];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final ReviewSource source in upcoming) {
          if (source.kind == ReviewKind.word) _prepareReviewWord(source);
        }
        if (visible.kind == ReviewKind.word && _currentKey == visible.key) {
          unawaited(_playWord(visible));
        }
      });
    }

    final Widget progressHeader = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 28 : 64,
        16,
        compact ? 28 : 64,
        0,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    finished
                        ? (widget.practice
                              ? '本轮已练习完'
                              : '今天的复习，完成了')
                        : '${widget.practice ? '自由练习' : '计划复习'} · ${index < 0 ? completed + 1 : index + 1}/${keys.length}',
                    key: const Key('daily-review-session-progress'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ReviewRecallTheme.textPrimary,
                    ),
                  ),
                  if (!finished)
                    Text(
                      '还剩 ${keys.length - completed}',
                      style: const TextStyle(
                        color: ReviewRecallTheme.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: keys.isEmpty ? 0 : completed / keys.length,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
                backgroundColor: ReviewRecallTheme.border,
                color: ReviewRecallTheme.lime,
              ),
            ],
          ),
        ),
      ),
    );

    if (!finished && visible != null) {
      return Column(
        children: <Widget>[
          progressHeader,
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 32,
                16,
                compact ? 12 : 32,
                8,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: AnimatedSwitcher(
                    duration: duration,
                    layoutBuilder:
                        (Widget? currentChild, List<Widget> previousChildren) =>
                            currentChild ?? const SizedBox.shrink(),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    transitionBuilder:
                        (Widget child, Animation<double> animation) =>
                            FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: Offset(_forward ? 0.06 : -0.06, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                    child: KeyedSubtree(
                      key: ValueKey<String>(_currentKey!),
                      child: _buildStudy(
                        byKey[_currentKey]!,
                        state.records[_currentKey]!,
                        fillViewport: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 24 : 40,
                8,
                compact ? 24 : 40,
                16,
              ),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 776),
                  child: Row(
                    children: <Widget>[
                      OutlinedButton.icon(
                        key: const Key('daily-review-previous'),
                        onPressed: _saving || index <= 0
                            ? null
                            : () => _moveCard(-1, keys),
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('上一张'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${index + 1} / ${keys.length}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('daily-review-next'),
                        onPressed: _saving || index >= keys.length - 1
                            ? null
                            : () => _moveCard(1, keys),
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.chevron_right_rounded),
                        label: const Text('下一张'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            key: const Key('daily-review-session-scroll'),
            controller: _sessionScroll,
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 32,
              0,
              compact ? 12 : 32,
              compact ? 16 : 32,
            ),
            children: <Widget>[
              progressHeader,
              const SizedBox(height: 28),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (finished)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 12 : 32,
                          ),
                          child: _ReviewSurface(
                            child: Column(
                              children: <Widget>[
                                const Icon(
                                  Icons.task_alt_rounded,
                                  size: 52,
                                  color: ReviewRecallTheme.lime,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  keys.isEmpty
                                      ? '暂时没有可复习的卡片'
                                      : widget.practice
                                      ? '这轮自由复习完成了'
                                      : '今天的复习，完成了',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: ReviewRecallTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.practice
                                      ? '这轮练习不会改变复习计划或新学额度，想巩固时可以随时再练。'
                                      : widget.journeyReview
                                      ? (keys.isEmpty
                                            ? '可以直接开始学习新内容。'
                                            : '接下来学习你感兴趣的新内容。')
                                      : sources.isEmpty
                                      ? '去词书架选择要学习的词书。'
                                      : '把一点点进步累积起来。剩下的交给时间。',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    height: 1.7,
                                    color: ReviewRecallTheme.textSecondary,
                                  ),
                                ),
                                if (!widget.practice &&
                                    _sessionRatings.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 18),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: ReviewRecallTheme.cardOlive,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        const Text(
                                          '本轮进度已保存',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: ReviewRecallTheme.lime,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${_sessionRatings.length} 条 · ${(_activeMilliseconds / 60000).ceil().clamp(1, 999)} 分钟',
                                          key: const Key('review-saved-summary'),
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            color: ReviewRecallTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '记得 / 很轻松 ${_sessionRatings.values.where((fsrs.Rating v) => v == fsrs.Rating.good || v == fsrs.Rating.easy).length} 条\n'
                                          '吃力 ${_sessionRatings.values.where((fsrs.Rating v) => v == fsrs.Rating.hard).length} 条 · 忘记 ${_sessionRatings.values.where((fsrs.Rating v) => v == fsrs.Rating.again).length} 条',
                                          style: const TextStyle(
                                            height: 1.55,
                                            color:
                                                ReviewRecallTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_missedKeys.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 12),
                                    FilledButton(
                                      onPressed: () => context.push(
                                        Uri(
                                          path: SGRoute.reviewSession.route,
                                          queryParameters: <String, String>{
                                            'practice': '1',
                                            'weak': '1',
                                            if (widget.recommended)
                                              'deck': 'recommended',
                                          },
                                        ).toString(),
                                      ),
                                      style: ReviewRecallTheme.secondaryButton,
                                      child: Text(
                                        '再练薄弱内容（${_missedKeys.length}）',
                                      ),
                                    ),
                                  ],
                                  TextButton(
                                    onPressed: () async {
                                      await ref
                                          .read(studyActivityServiceProvider)
                                          .touchReview();
                                      await ref
                                          .read(dailyReviewProvider.notifier)
                                          .syncCloudBackup();
                                      if (mounted)
                                        Navigator.of(context).push<void>(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const StudyPlayScreen(),
                                          ),
                                        );
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: ReviewRecallTheme.lime,
                                    ),
                                    child: const Text('同步并去一起练打卡'),
                                  ),
                                  FilledButton(
                                    onPressed: () => _showResultPreview(),
                                    style: ReviewRecallTheme.secondaryButton,
                                    child: const Text('预览成果卡'),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                FilledButton(
                                  onPressed: () => _leaveSession(
                                    journeyCompleted: widget.journeyReview,
                                  ),
                                  style: ReviewRecallTheme.primaryButton,
                                  child: Text(
                                    widget.journeyReview ? '进入新学' : '返回学习',
                                  ),
                                ),
                                if (widget.practice &&
                                    keys.any(_missedKeys.contains))
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _deckKeys = keys
                                          .where(_missedKeys.contains)
                                          .toList();
                                      _currentKey = _deckKeys!.first;
                                      _missedKeys.clear();
                                      _completedKeys.clear();
                                      _sessionRatings.clear();
                                      _activeMilliseconds = 0;
                                      _draftInitialized = false;
                                      _revealed = false;
                                    }),
                                    child: const Text('重练没记住的卡片'),
                                  ),
                                if (widget.practice ||
                                    plan.next != null) ...<Widget>[
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _deckKeys = null;
                                      _missedKeys.clear();
                                      _completedKeys.clear();
                                      _sessionRatings.clear();
                                      _activeMilliseconds = 0;
                                      _draftInitialized = false;
                                      _revealed = false;
                                    }),
                                    child: Text(
                                      widget.practice ? '再练一轮' : '继续下一轮',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExplanation() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '从收藏开始，慢慢记牢',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 20),
        for (final (IconData icon, String title, String body)
            in <(IconData, String, String)>[
              (
                Icons.bookmarks_outlined,
                '内容从哪里来？',
                '复习内容来自词书、推荐学习计划和已添加的记忆练习。',
              ),
              (
                Icons.event_repeat_rounded,
                '为什么不用每天全部重学？',
                'FSRS 会根据你每次的回忆情况，调整下次复习时间。忘记的早点再见，记得牢的间隔更久，让练习用在需要巩固的地方。',
              ),
              (
                Icons.style_outlined,
                '开始后怎么学？',
                '计划复习时，先回忆、显示答案核对，再如实评分，系统会安排下次复习时间。一天可以多次复习；暂时没有待复习内容时，也可以用“再次复习”自由练习已学内容，不改变计划或新学额度。',
              ),
              (
                Icons.checklist_rounded,
                '四个评分按钮怎么选？',
                '忘记：没想起来，或看了答案才认出来；会进入短间隔重学，更快再练。\n'
                    '费力想起：没看答案就答对了，但比较吃力；通常比“记得”更早巩固。\n'
                    '记得：能正确回忆，难度正常；按正常节奏安排，记得越稳，后续间隔通常越长。\n'
                    '很轻松：几乎不费力，立刻就能答对；通常安排更长的复习间隔。\n'
                    '按钮会显示这张卡片预计的下次复习间隔，具体时间由学习阶段和历史表现决定，不是固定天数。请如实评分，没想起来就选“忘记”。',
              ),
              (
                Icons.touch_app_outlined,
                '其他按钮有什么用？',
                '“上一张／下一张”只切换浏览，不会记成绩；喇叭播放原句，视频按钮回到原视频。点击“稍后继续”可以退出，已评分结果会保留，未完成的内容也不会丢。',
              ),
            ]) ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: AppDesignTokens.brandGreenDark, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
        ],
      ],
    ),
  );

  Widget _buildOverview(
    DailyReviewState state,
    List<ReviewSource> sources,
    ReviewPlan plan,
    DateTime now,
  ) {
    final bool empty = sources.isEmpty;
    final bool done = plan.next == null;
    final Map<ReviewKind, int> counts = <ReviewKind, int>{
      for (final ReviewKind kind in ReviewKind.values)
        kind: sources
            .where((ReviewSource source) => source.kind == kind)
            .length,
    };
    final bool canPractice = _practiceRecords(state, sources, now).isNotEmpty;
    final String title = empty
        ? '把想记住的表达带到这里'
        : done
        ? '今天暂时没有待复习内容'
        : plan.today.reviews > 0
        ? '继续今天的记忆练习'
        : '把学过的，真正记住';
    final MicroReviewUiState micro = ref.watch(microReviewProvider);
    return _ReviewSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (micro.active) ...<Widget>[
            _MicroReviewActiveCard(state: micro),
            const SizedBox(height: 16),
          ],
          const Icon(
            Icons.auto_awesome_rounded,
            size: 38,
            color: AppDesignTokens.brandGreenDark,
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            empty
                ? '单词、短语、听写错句、跟读低分都会进入同一套 FSRS 计划；考试错题也可回流。'
                : done
                ? _completionText(plan, state.dailyNewLimit, now)
                : '先尝试回忆，再揭晓答案。每次如实反馈，系统会安排适合它的下次见面时间。',
            style: TextStyle(
              fontSize: 15,
              height: 1.65,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (!empty && !done)
            Text(
              '约 ${(plan.remaining * 20 / 60).ceil()} 分钟 · 可随时暂停',
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 28,
            runSpacing: 20,
            children: <Widget>[
              _ReviewMetric(label: '待复习', value: '${plan.due.length}'),
              _ReviewMetric(label: '今日可新学', value: '${plan.newAvailable}'),
              _ReviewMetric(label: '今天已练习', value: '${plan.today.reviews} 次'),
            ],
          ),
          const SizedBox(height: 30),
          if (!empty && !done) ...<Widget>[
            FilledButton.icon(
              key: const Key('daily-review-start'),
              onPressed: () => context.push(_sessionRoute()),
              style: _primaryButtonStyle,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                _draftStore.load(now) != null
                    ? '继续上次复习'
                    : plan.today.reviews > 0
                    ? '再次复习'
                    : '开始今日复习',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('daily-review-micro'),
              onPressed: () => startMicroReviewFromUi(context, ref),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('碎片 5 分钟'),
            ),
          ]
          else if (empty)
            FilledButton.icon(
              onPressed: () => context.go(AppNavDestination.library.route),
              style: _primaryButtonStyle,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('去学习，收藏新表达'),
            )
          else if (canPractice) ...<Widget>[
            FilledButton.icon(
              key: const Key('daily-review-again'),
              onPressed: () => context.push(_sessionRoute(practice: true)),
              style: _primaryButtonStyle,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('再次复习'),
            ),
            const SizedBox(height: 10),
            Text(
              '当前没有待复习内容，可以自由练习已学内容，不改变复习计划或新学额度。',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
          if (!empty && done && plan.waiting.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('daily-review-vocab-bonus'),
              onPressed: () => unawaited(_addMoreNewWordsToday()),
              style: _primaryButtonStyle,
              icon: const Icon(Icons.add_rounded),
              label: const Text('再背几个'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _showSettings(state.dailyNewLimit),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('调整每天新学数量'),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ReviewKind kind in ReviewKind.values)
                Container(
                  width: 104,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.softGray,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${counts[kind]}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                      Text(
                        kind.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const Text('全部内容'),
                selected: _overviewKind == null,
                onSelected: (_) => setState(() => _overviewKind = null),
              ),
              for (final ReviewKind kind in ReviewKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: _overviewKind == kind,
                  onSelected: (_) => setState(() => _overviewKind = kind),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildLearningConnections(state, sources),
          const SizedBox(height: 20),
          Text(
            '本周坚持的痕迹',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (int day = 0; day < 7; day++)
                Builder(
                  builder: (BuildContext context) {
                    final DateTime date = DateTime(
                      now.year,
                      now.month,
                      now.day - now.weekday + 1 + day,
                    );
                    final bool studied =
                        (state.days[reviewDayKey(date)]?.reviews ?? 0) > 0;
                    return Column(
                      children: <Widget>[
                        Text(
                          const <String>[
                            '一',
                            '二',
                            '三',
                            '四',
                            '五',
                            '六',
                            '日',
                          ][day],
                          style: TextStyle(
                            fontSize: 12,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Icon(
                          studied ? Icons.check_circle : Icons.circle_outlined,
                          size: 24,
                          color: studied
                              ? AppDesignTokens.brandGreen
                              : AppDesignTokens.borderGray,
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: <Widget>[
              ActionChip(
                label: Text(
                  '推荐背词 ${ref.watch(recommendedWordsProvider).length}',
                ),
                onPressed: () => context.push(
                  ref.read(recommendedWordsProvider).isEmpty
                      ? SGRoute.vocabularyPlacement.route
                      : '${SGRoute.reviewSession.route}?deck=recommended',
                ),
              ),
              ActionChip(
                label: Text(
                  hasCompletedVocabularyPlacement(
                    ref.read(vocabularyPlacementProvider),
                  )
                      ? '重新测词汇量'
                      : '词汇量测试',
                ),
                onPressed: () => context.push(
                  hasCompletedVocabularyPlacement(
                    ref.read(vocabularyPlacementProvider),
                  )
                      ? '${SGRoute.vocabularyPlacement.route}?retest=1'
                      : SGRoute.vocabularyPlacement.route,
                ),
              ),
            ],
          ),
          if (!empty) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                ActionChip(
                  label: Text(
                    '背单词 / 短语 ${counts[ReviewKind.word]! + counts[ReviewKind.phrase]!}',
                  ),
                  onPressed:
                      counts[ReviewKind.word]! + counts[ReviewKind.phrase]! == 0
                      ? null
                      : () => context.push(
                          '${SGRoute.reviewSession.route}?practice=1&kind=expressions',
                        ),
                ),
                ActionChip(
                  label: Text('背句子 ${counts[ReviewKind.sentence]}'),
                  onPressed: counts[ReviewKind.sentence] == 0
                      ? null
                      : () => context.push(
                          '${SGRoute.reviewSession.route}?practice=1&kind=sentence',
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _completionText(ReviewPlan plan, int limit, DateTime now) {
    final String waiting = plan.waiting.isEmpty
        ? ''
        : '还有 ${plan.waiting.length} 条待学内容，收藏优先，其余按 i+1（贴近你当前水平）安排。';
    final String next = plan.nextDue == null
        ? ''
        : '下一条待复习：${_formatDue(plan.nextDue!, now)}。';
    if (limit == 0) return '新学已暂停，待复习内容会继续安排。$waiting$next';
    return '当前没有需要立即复习的内容。$waiting$next';
  }

  List<WordPracticeMode> _modesFor(ReviewSource source) {
    // Per-mode FSRS cards carry their own key; do not chain modes on one card.
    final WordPracticeMode? fromKey = WordPracticeModeX.tryParse(
      source.cardType,
    );
    if (fromKey != null) {
      return <WordPracticeMode>[fromKey];
    }
    if (source.kind != ReviewKind.word) {
      return const <WordPracticeMode>[WordPracticeMode.recognize];
    }
    return ref.read(wordReviewSettingsProvider).orderedModes;
  }

  WordPracticeMode _currentMode(ReviewSource source) {
    final List<WordPracticeMode> modes = _modesFor(source);
    if (modes.isEmpty) return WordPracticeMode.recognize;
    return modes[_modeStep.clamp(0, modes.length - 1)];
  }

  ReviewSource _displaySource(ReviewSource source) {
    final String? pick = _contextPick[source.key]?.trim();
    if (pick == null || pick.isEmpty) return source;
    final bool asEpisode = source.relatedSources.any(
      (ReviewSourceLink link) => link.episodeId == pick,
    );
    return source.forContext(
      episode: asEpisode ? pick : null,
      label: asEpisode ? null : pick,
    );
  }

  Widget _buildStudy(
    ReviewSource rawSource,
    ReviewRecord record, {
    bool fillViewport = false,
  }) {
    final ReviewSource source = _displaySource(rawSource);
    final WordReviewSettings options = ref.watch(wordReviewSettingsProvider);
    final bool word = source.kind == ReviewKind.word;
    final String answer = source.answer.trim().isNotEmpty
        ? source.answer
        : (_reviewMeanings[source.question] ?? '');
    final WordPracticeMode mode = _currentMode(source);
    final bool speakStage = word && mode == WordPracticeMode.speak;
    final bool listenStage = word && mode == WordPracticeMode.listen;
    final bool contrastStage = word && mode == WordPracticeMode.contrast;
    final List<ConfusablePair> contrastPairs = contrastStage
        ? confusablePairsFor(source.question)
        : const <ConfusablePair>[];
    final bool skill = source.kind == ReviewKind.skill;
    final List<String> skillChoices = skill &&
            source.skillLevel != null &&
            source.skillLevel! >= 0 &&
            source.skillLevel! < kCafeLevels.length
        ? List<String>.of(kCafeLevels[source.skillLevel!].answers)
        : const <String>[];
    final List<String> choices = skill
        ? skillChoices
        : word &&
                !speakStage &&
                options.recallStyle == WordRecallStyle.multipleChoice
            ? _choices.putIfAbsent(source.key, () => _meaningChoices(source, answer))
            : const <String>[];
    final bool choiceMode = choices.length >= 2;
    final int? passes = _freshPasses[source.key];
    final bool completed = _completedKeys.contains(source.key);
    final DateTime now = ref.read(reviewClockProvider)();
    final String letterCase = ref.watch(
      learningSettingsProvider.select(
        (LearningSettingsState settings) => settings.subtitleLetterCase,
      ),
    );
    final bool useCloze =
        word &&
        !speakStage &&
        !listenStage &&
        !contrastStage &&
        source.english.trim().isNotEmpty &&
        sentenceContainsWord(source.english, source.question);
    final String frontText = listenStage && !_revealed
        ? '♪ 听音识词'
        : contrastStage && !_revealed
        ? '辨异：选出正确用法对应的词'
        : speakStage
        ? source.question
        : useCloze && !_revealed
        ? clozeSentence(source.english, source.question)
        : source.question;
    final int encounterToday = word
        ? WordEncounterStore(
            account: ref.read(studyAccountProvider),
          ).todayCount(source.question, now)
        : 0;
    final List<WordPracticeMode> modes = _modesFor(source);
    final String stageLabel = word
        ? (modes.length > 1
              ? ' · ${mode.label} ${_modeStep + 1}/${modes.length}'
              : ' · ${mode.label}')
        : '';
    final bool compactPhone = MediaQuery.sizeOf(context).width < 600;
    final double sectionGap = fillViewport && compactPhone ? 10 : 20;
    final bool stickyRatings = fillViewport &&
        !completed &&
        !_retryWord &&
        !choiceMode &&
        ((_revealed && !widget.practice) || speakStage);
    final List<Widget> studyChildren = <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${source.kind.label} · ${widget.practice
                        ? '自由练习'
                        : record.isNew
                        ? '首次学习'
                        : '待复习'}$stageLabel',
                    style: const TextStyle(
                      color: ReviewRecallTheme.lime,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (completed)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppDesignTokens.brandGreenDark,
                  ),
              ],
            ),
            if (passes != null) Text('生词 · 今日已通过 $passes / 3 次'),
            if (encounterToday > 0)
              Text(
                '片中再遇 · 今日 $encounterToday 次',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF925600),
                  fontWeight: FontWeight.w700,
                ),
              ),
            SizedBox(height: sectionGap),
            Text(
              speakStage
                  ? '听示范后跟读，再自评发音把握'
                  : contrastStage
                  ? '对比易混词，分清形近 / 义近差异'
                  : useCloze && !_revealed
                  ? '根据原句回忆被挖空的单词'
                  : source.answer != source.english
                  ? '先回忆中文含义'
                  : '先试着用英语说出来',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF626262)),
            ),
            SizedBox(height: fillViewport && compactPhone ? 12 : 18),
            if (word &&
                (_revealed ||
                    (!listenStage && !useCloze && !contrastStage)))
              _wordPhonicsSurface(source.question, expandByDefault: false)
            else
              SelectableText(
                frontText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: source.kind == ReviewKind.word
                      ? (useCloze && !_revealed ? 22 : 34)
                      : 25,
                  height: 1.45,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            if (word && _revealed) ...<Widget>[
              const SizedBox(height: 10),
              WordRootBreakdownPanel(
                word: source.question,
                compact: true,
                allowGuess: false,
              ),
            ],
            if (word &&
                (source.english.trim().isNotEmpty ||
                    (source.episodeId?.trim().isNotEmpty ?? false) ||
                    source.sourceLabel.trim().isNotEmpty)) ...<Widget>[
              const SizedBox(height: 14),
              Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                key: ValueKey<String>('review-context-${source.key}'),
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: MediaQuery.sizeOf(context).width >= 600,
                title: const Text('原句与来源'),
                children: <Widget>[
                  ReviewSourceContextPanel(
                    source: source,
                    word: source.question,
                    speaking: _speaking,
                    compact: true,
                    hideSentence: !_revealed &&
                        (useCloze || listenStage || contrastStage),
                    onSpeakSentence: () => _speakSource(source),
                    onSelectRelatedSource: (ReviewSourceLink link) {
                      setState(() {
                        final String? episode = link.episodeId?.trim();
                        _contextPick[rawSource.key] =
                            (episode != null && episode.isNotEmpty)
                                ? episode
                                : link.label;
                      });
                    },
                  ),
                ],
                ),
              ),
            ],
            if (word && (_revealed || (!listenStage && !useCloze && !contrastStage)))
              TextButton.icon(
                onPressed: () => unawaited(showWordOccurrences(context, ref, source.question)),
                icon: const Icon(Icons.hub_outlined),
                label: const Text('查看已学素材中的出现记录'),
              ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                const Spacer(),
                if (word)
                  IconButton(
                    tooltip: '播放单词发音',
                    onPressed: _speaking ? null : () => _playWord(source),
                    icon: const Icon(Icons.volume_up_rounded),
                  ),
                if (word)
                  IconButton(
                    tooltip: _phonicsOpen ? '收起自然拼读' : '展开音节与自然拼读',
                    onPressed: () => setState(() => _phonicsOpen = !_phonicsOpen),
                    icon: Icon(
                      _phonicsOpen
                          ? Icons.spa_rounded
                          : Icons.spa_outlined,
                    ),
                  ),
                IconButton(
                  tooltip: _speaking ? '正在朗读' : '听原句',
                  onPressed: _speaking || source.english.isEmpty
                      ? null
                      : () => _speakSource(source),
                  icon: const Icon(Icons.volume_up_outlined),
                ),
                if (_foundationMediaFor(source)?.hasVideo ?? false)
                  IconButton(
                    tooltip: '看真人示范视频',
                    onPressed: () => unawaited(_openFoundationVideo(source)),
                    icon: const Icon(Icons.face_retouching_natural_rounded),
                  ),
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: (String action) {
                    switch (action) {
                      case 'skip':
                        _skipCard(source);
                      case 'hard':
                        _markDifficult(source);
                      case 'note':
                        unawaited(_editNote(source));
                      case 'archive':
                        _archiveFromSession(source);
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      const <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'skip',
                          child: Text('跳过本次'),
                        ),
                        PopupMenuItem<String>(
                          value: 'hard',
                          child: Text('标记疑难'),
                        ),
                        PopupMenuItem<String>(
                          value: 'note',
                          child: Text('补充笔记'),
                        ),
                        PopupMenuItem<String>(
                          value: 'archive',
                          child: Text('斩掉（熟悉）'),
                        ),
                      ],
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (speakStage && !completed) ...<Widget>[
              FilledButton.tonalIcon(
                onPressed: _speaking ? null : () => _playWord(source),
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('听示范发音'),
              ),
              if (_foundationMediaFor(source)?.hasVideo ?? false) ...<Widget>[
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(_openFoundationVideo(source)),
                  icon: const Icon(Icons.videocam_rounded),
                  label: const Text('看真人示范视频'),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('daily-review-speak-assess'),
                onPressed: _saving
                    ? null
                    : () => unawaited(_openSpeakAssessment(source, record)),
                style: _primaryButtonStyle,
                icon: const Icon(Icons.mic_rounded),
                label: const Text('录音并云端打分'),
              ),
              const SizedBox(height: 8),
              Text(
                '跟读分仅作参考；最终以你的自评档写入本卡独立 FSRS 曲线。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              if (!stickyRatings) ...<Widget>[
                const SizedBox(height: 16),
                _ratingButtons(
                  source: source,
                  record: record,
                  now: now,
                  practice: widget.practice,
                  speakHints: true,
                ),
              ],
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ] else if (!_revealed && !completed) ...<Widget>[
              if (contrastStage) ...<Widget>[
                Text(
                  '目标词与易混项',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                for (final String option in _contrastOptions(
                  source.question,
                  contrastPairs,
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () {
                        if (option.toLowerCase() ==
                            source.question.trim().toLowerCase()) {
                          setState(() => _revealed = true);
                        } else {
                          _markUnknown(source);
                        }
                      },
                      child: Text(option),
                    ),
                  ),
                if (contrastPairs.isEmpty)
                  TextButton(
                    onPressed: () => setState(() => _revealed = true),
                    child: const Text('暂无易混对，直接看解析'),
                  ),
              ] else if (listenStage) ...<Widget>[
                FilledButton.tonalIcon(
                  onPressed: _speaking ? null : () => _playWord(source),
                  icon: const Icon(Icons.hearing_rounded),
                  label: const Text('播放发音'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('daily-review-reveal'),
                  onPressed: () => setState(() => _revealed = true),
                  style: _primaryButtonStyle,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('显示单词与释义'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('daily-review-slash-listen'),
                  onPressed: _saving ? null : () => _slashFamiliar(source),
                  icon: const Icon(Icons.content_cut_rounded, size: 18),
                  label: const Text('熟悉，直接斩掉'),
                ),
              ] else if (choiceMode)
                for (final String choice in choices)
                  OutlinedButton(
                    onPressed: () {
                      if (choice == answer.trim()) {
                        setState(() => _revealed = true);
                      } else if (skill) {
                        unawaited(
                          _grade(source, record, fsrs.Rating.again),
                        );
                      } else {
                        _markUnknown(source);
                      }
                    },
                    child: Text(choice),
                  )
              else ...<Widget>[
                Text(
                  '没想起来也没关系，诚实反馈更有帮助。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: ReviewRecallTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('daily-review-reveal'),
                  onPressed: () => setState(() => _revealed = true),
                  style: ReviewRecallTheme.primaryButton,
                  child: Text(useCloze ? '显示答案与原词' : '显示答案'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('daily-review-slash'),
                  onPressed: _saving
                      ? null
                      : () => _slashFamiliar(source),
                  icon: const Icon(Icons.content_cut_rounded, size: 18),
                  label: const Text('熟悉，直接斩掉'),
                ),
              ],
              if (word && (record.isNew || choiceMode))
                TextButton(
                  onPressed: () => _markUnknown(source),
                  child: const Text('这是生词'),
                ),
            ] else ...<Widget>[
              const Divider(height: 24),
              // Headword + phonics live in the top surface when revealed.
              Text(
                answer.trim().isEmpty
                    ? '暂未找到中文释义'
                    : source.kind != ReviewKind.word &&
                          source.answer == source.english
                    ? formatSubtitleLetterCase(source.answer, letterCase)
                    : answer,
                style: TextStyle(
                  fontSize: 23,
                  height: 1.5,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              if (contrastStage && contrastPairs.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                for (final ConfusablePair pair in contrastPairs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${source.question} ↔ ${pair.foil}\n${pair.hintCn}',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ),
              ],
              // Word cards already show subtitle example in ReviewSourceContextPanel.
              if (!word &&
                  source.answer != source.english &&
                  source.english.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  formatSubtitleLetterCase(source.english, letterCase),
                  style: TextStyle(fontSize: 16, height: 1.6),
                ),
                if (source.chinese.isNotEmpty)
                  Text(
                    source.chinese,
                    style: TextStyle(
                      height: 1.6,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
              ],
              if (!completed && _retryWord)
                FilledButton(
                  onPressed: () => _nextCard(source.key, complete: false),
                  child: const Text('稍后再练这词'),
                )
              else if (!completed && choiceMode)
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () => _grade(source, record, fsrs.Rating.good),
                  child: const Text('继续'),
                ),
              if (!completed &&
                  !_retryWord &&
                  !choiceMode &&
                  widget.practice) ...<Widget>[
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('daily-review-practice-done'),
                  onPressed: () => _grade(source, record, fsrs.Rating.good),
                  style: _primaryButtonStyle,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('记得，下一张'),
                ),
                OutlinedButton(
                  onPressed: () {
                    if (word && (record.isNew || options.requireSpelling)) {
                      _markUnknown(source);
                    } else {
                      _missedKeys.add(source.key);
                      unawaited(
                        MissedReviewBook(
                          account: ref.read(studyAccountProvider),
                        ).markMissed(source.key),
                      );
                      _advanceCard(source.key);
                    }
                  },
                  child: const Text('没记住，稍后重练'),
                ),
                const SizedBox(height: 10),
                Text(
                  '自由练习不评分，不改变下次复习时间或新学额度。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
              if (!completed &&
                  !_retryWord &&
                  !choiceMode &&
                  !widget.practice &&
                  !stickyRatings) ...<Widget>[
                const SizedBox(height: 16),
                const Text(
                  '按真实回忆情况选择',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: ReviewRecallTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                _ratingButtons(
                  source: source,
                  record: record,
                  now: now,
                  practice: false,
                ),
                const SizedBox(height: 6),
                const Text(
                  '点一下即保存并进入下一条。',
                  style: TextStyle(
                    fontSize: 11,
                    color: ReviewRecallTheme.textMuted,
                  ),
                ),
                if (widget.journeyReview) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    '评完这张会自动下一张。也可以跳过剩余复习，直接去学新内容。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _leaveSession(journeyCompleted: true),
                    child: const Text('跳过剩余 · 去学新'),
                  ),
                ],
              ],
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
            if (!stickyRatings) ...<Widget>[
              const SizedBox(height: 20),
              Text(
                completed
                    ? (widget.practice
                          ? '本轮已练习，不影响原有复习计划'
                          : '已完成，这张卡片的进度已保存')
                    : widget.practice
                    ? '先回忆，再揭晓；随时都能再练一轮'
                    : '先回忆，再揭晓；如实反馈就好',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF626262)),
              ),
            ],
    ];

    final List<Widget> stickyFooter = stickyRatings
        ? <Widget>[
            const Divider(height: 16),
            Text(
              speakStage ? '按真实跟读情况选择' : '按真实回忆情况选择',
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: ReviewRecallTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _ratingButtons(
              source: source,
              record: record,
              now: now,
              practice: widget.practice,
              speakHints: speakStage,
            ),
            const SizedBox(height: 4),
            const Text(
              '点一下即保存并进入下一条。',
              style: TextStyle(
                fontSize: 11,
                color: ReviewRecallTheme.textMuted,
              ),
            ),
            if (widget.journeyReview && !speakStage) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => _leaveSession(journeyCompleted: true),
                child: const Text('跳过剩余 · 去学新'),
              ),
            ],
          ]
        : const <Widget>[];

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: studyChildren,
    );

    if (!fillViewport) {
      return _ReviewSurface(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: word
                ? 0
                : (compactPhone ? 320 : 380),
          ),
          child: body,
        ),
      );
    }

    return _ReviewSurface(
      compact: compactPhone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: stickyFooter.isEmpty ? 8 : 4),
              child: body,
            ),
          ),
          if (stickyFooter.isNotEmpty) ...stickyFooter,
        ],
      ),
    );
  }

  Future<void> _showResultPreview() async {
    final String text =
        '今天在爱快英语完成了 ${_sessionRatings.length} 条计划复习。\n一点点坚持，把学过的内容真正记住。';
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('学习成果预览'),
        content: Text('$text\n\n不含录音、具体词条或个人课程。复制后可自行编辑分享，不会自动发布。'),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(this.context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PublishLearningResultScreen(initialText: text),
                ),
              );
            },
            child: const Text('编辑与发布'),
          ),

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('复制文案'),
          ),
        ],
      ),
    );
  }

  Widget _buildLearningConnections(
    DailyReviewState state,
    List<ReviewSource> sources,
  ) {
    final Map<String, List<ReviewSource>> groups =
        <String, List<ReviewSource>>{};
    for (final ReviewSource source in sources) {
      for (final String label in <String>{
        source.sourceLabel,
        ...source.relatedSources.map((ReviewSourceLink link) => link.label),
      }) {
        groups
            .putIfAbsent(label, () => <ReviewSource>[])
            .add(source.forContext(label: label));
      }
    }
    return Material(
      color: AppDesignTokens.appWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '从你学过的内容中复习',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '视频里收藏的单词、句子和短语会保留来源。未收藏的内容不会自动加入计划。',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final MapEntry<String, List<ReviewSource>> group
              in groups.entries)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: Icon(
                group.value.any((ReviewSource s) => s.episodeId != null)
                    ? Icons.ondemand_video_outlined
                    : Icons.bookmark_outline,
                color: AppDesignTokens.brandGreenDark,
              ),
              title: Text(
                group.key,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              subtitle: Text(
                '${group.value.length} 条关联内容 · 已学 ${group.value.where((ReviewSource s) => (state.records[s.key]?.reviews ?? 0) > 0).length} 条',
                style: TextStyle(
                  fontSize: 12,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    TextButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始这组计划复习'),
                      onPressed: () =>
                          context.push(_sessionRoute(label: group.key)),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.replay),
                      label: const Text('自由练习这组'),
                      onPressed: () => context.push(
                        _sessionRoute(practice: true, label: group.key),
                      ),
                    ),
                  ],
                ),
                for (final ReviewSource source in group.value)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(
                      source.kind == ReviewKind.word
                          ? source.question
                          : source.english,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${source.kind.label} · ${source.time ?? '我的收藏'}',
                      style: TextStyle(color: AppDesignTokens.textSecondary),
                    ),
                    trailing: source.episodeId == null
                        ? null
                        : IconButton(
                            tooltip:
                                source.episodeId!.startsWith('reading:')
                                ? '回到阅读原文'
                                : '回到收藏时的视频',
                            icon: Icon(
                              source.episodeId!.startsWith('reading:')
                                  ? Icons.menu_book_outlined
                                  : Icons.play_circle_outline,
                            ),
                            onPressed: () {
                              final String episodeId = source.episodeId!;
                              if (episodeId.startsWith('reading:')) {
                                final String docId = episodeId
                                    .substring('reading:'.length)
                                    .trim();
                                if (docId.isEmpty) return;
                                context.push(
                                  '/reading/${Uri.encodeComponent(docId)}',
                                );
                                return;
                              }
                              context.pushNamed(
                                SGRoute.player.name,
                                pathParameters: <String, String>{
                                  'episodeId': episodeId,
                                },
                                queryParameters: <String, String>{
                                  if (source.time != null)
                                    'startTime': source.time!,
                                  'autoplay': '1',
                                  'loop': 'sentence',
                                },
                              );
                            },
                          ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (BuildContext context) => AlertDialog(
                        title: Text(source.question),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(source.answer),
                              if (source.english.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 16),
                                Text(source.english),
                              ],
                              if (source.chinese.isNotEmpty)
                                Text(source.chinese),
                              const SizedBox(height: 16),
                              Text(
                                '来源：${source.sourceLabel} ${source.time ?? ''}',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                (state.records[source.key]?.reviews ?? 0) > 0
                                    ? '已在你的复习计划中学习过'
                                    : '已收藏，等待新学安排',
                              ),
                            ],
                          ),
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                context.push('${SGRoute.reviewSession.route}?deck=recommended'),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('进入背词计划 · 推荐词库'),
          ),
          Text(
            '推荐背词与视频收藏分别标明来源；浏览词条不算完成，只有实际复习才更新计划。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingButtons({
    required ReviewSource source,
    required ReviewRecord record,
    required DateTime now,
    required bool practice,
    bool speakHints = false,
  }) {
    final List<(fsrs.Rating, String, String, Color)> options =
        <(fsrs.Rating, String, String, Color)>[
      (
        fsrs.Rating.again,
        speakHints ? '跟读困难' : '忘记',
        speakHints ? '读不准或读不出' : '没想起来',
        ReviewRecallTheme.rateAgain,
      ),
      (
        fsrs.Rating.hard,
        speakHints ? '勉强过关' : '吃力',
        speakHints ? '能读但吃力' : '想了很久',
        ReviewRecallTheme.rateHard,
      ),
      (
        fsrs.Rating.good,
        speakHints ? '跟读顺利' : '记得',
        speakHints ? '基本正确' : '能独立回忆',
        ReviewRecallTheme.rateGood,
      ),
      (
        fsrs.Rating.easy,
        speakHints ? '很流利' : '很轻松',
        speakHints ? '发音清晰' : '几乎不费力',
        ReviewRecallTheme.rateEasy,
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double gap = 8;
        final double width = ((constraints.maxWidth - gap) / 2).clamp(0.0, 240.0);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final (
                  fsrs.Rating rating,
                  String label,
                  String hint,
                  Color color,
                )
                in options)
              SizedBox(
                width: width,
                child: Tooltip(
                  message: practice || speakHints
                      ? hint
                      : '$hint · 下次 ${_formatReviewDelay(record.scheduledCard(rating, now).due, now)}',
                  child: FilledButton(
                    key: Key('daily-review-rate-${rating.name}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: ReviewRecallTheme.textPrimary,
                      disabledBackgroundColor: color.withValues(alpha: 0.45),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        _saving ? null : () => _grade(source, record, rating),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildQueueInfo(ReviewPlan plan, int limit) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '新学 ${plan.today.newLearned} / $limit 条 · 待学 ${plan.waiting.length} 条',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '待复习内容按等待时间优先；每完成 4 条待复习内容，穿插 1 条新学。新内容按入队顺序轮到，未完成的会保留。',
          style: TextStyle(fontSize: 13, height: 1.7, color: Color(0xFF626262)),
        ),
        if (plan.waiting.length > limit && limit > 0) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '如果收藏速度持续超过学习速度，待学会增加。可以调整新学数量，或先放慢新增节奏。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppDesignTokens.textSecondary,
            ),
          ),
        ],
      ],
    ),
  );

  void _advanceCard(String key) => _nextCard(key, complete: true);

  void _nextCard(String key, {required bool complete}) {
    _stopSpeech();
    if (_sessionScroll.hasClients) _sessionScroll.jumpTo(0);
    final bool wasFinished =
        (_deckKeys ?? <String>[]).isNotEmpty &&
        (_deckKeys!.every(_completedKeys.contains));
    setState(() {
      if (complete) _completedKeys.add(key);
      _retryWord = false;
      _playedWord = null;
      _phonicsOpen = false;
      _choices.remove(key);
      _stageRatings.remove(key);
      _modeStep = 0;
      final List<String> keys = _deckKeys ?? <String>[];
      final int index = keys.indexOf(key);
      final List<String> remaining = <String>[
        ...keys.skip(index + 1),
        ...keys.take(index),
      ].where((String item) => !_completedKeys.contains(item)).toList();
      _currentKey = remaining.firstOrNull ?? key;
      _forward = true;
      _revealed = false;
    });
    if (complete) {
      final List<String> keys = _deckKeys ?? <String>[];
      final bool nowFinished =
          keys.isNotEmpty && keys.every(_completedKeys.contains);
      if (nowFinished && !wasFinished) {
        playSuccessSfx(SuccessSfxKind.complete);
      } else {
        playSuccessSfx(SuccessSfxKind.nudge);
      }
    }
    unawaited(_persistDraft());
  }

  Future<SpellStageResult?> _runSpellStage(ReviewSource source) async {
    _stopSpeech();
    final bool preferListen =
        source.answer.trim().isEmpty && source.english.trim().isNotEmpty;
    final SpellStageResult? result = await Navigator.of(context)
        .push<SpellStageResult>(
          MaterialPageRoute<SpellStageResult>(
            builder: (_) => ReviewSpellingScreen(
              word: source.question,
              meaning: source.answer.trim().isEmpty
                  ? (_reviewMeanings[source.question] ?? '')
                  : source.answer,
              fillMissingLetters:
                  !ref.read(wordReviewSettingsProvider).requireSpelling,
              prompt: preferListen
                  ? SpellPromptKind.listen
                  : SpellPromptKind.meaning,
              onListen: () => unawaited(_playWord(source, silent: true)),
            ),
          ),
        );
    // Let the spelling route overlay finish disposing before Riverpod rebuilds.
    await Future<void>.delayed(Duration.zero);
    return result;
  }

  Future<void> _openSpeakAssessment(
    ReviewSource source,
    ReviewRecord record,
  ) async {
    _stopSpeech();
    final PronunciationAssessmentTarget target =
        PronunciationAssessmentTarget.wordOnly(source.question);
    await showPronunciationAssessmentDialog(
      context,
      target: target,
      episodeId: source.episodeId,
      onResult: (PronunciationAssessmentResult result) {
        final fsrs.Rating rating = ratingFromPronunciationScore(
          result.suggestedScore ?? result.accuracy,
        );
        unawaited(_grade(source, record, rating));
      },
    );
  }

  Future<void> _grade(
    ReviewSource source,
    ReviewRecord record,
    fsrs.Rating rating,
  ) async {
    if (_saving || _completedKeys.contains(source.key)) {
      return;
    }
    final List<fsrs.Rating>? previousStages = _stageRatings[source.key] == null
        ? null
        : List<fsrs.Rating>.of(_stageRatings[source.key]!);
    setState(() => _saving = true);
    try {
      // Independent FSRS per card type — no weakest-merge across modes.
      final WordReviewSettings options = ref.read(wordReviewSettingsProvider);
      final bool multiModeLegacy =
          source.kind == ReviewKind.word &&
          source.cardType == null &&
          options.orderedModes.length > 1;
      if (multiModeLegacy) {
        await _gradeWordPipeline(source, record, rating);
        return;
      }
      final bool spellGate =
          source.kind == ReviewKind.word &&
          options.requireSpelling &&
          !options.orderedModes.contains(WordPracticeMode.spell) &&
          (source.cardType == null || source.cardType == 'recognize');
      if (spellGate) {
        final SpellStageResult? spelled = await _runSpellStage(source);
        if (!mounted || spelled == null) return;
        if (spelled.rating == fsrs.Rating.again) {
          _setWordPasses(source.key, 0);
          _nextCard(source.key, complete: false);
          return;
        }
      }
      await _finishGrade(source, record, rating);
    } catch (_) {
      if (previousStages == null) {
        _stageRatings.remove(source.key);
      } else {
        _stageRatings[source.key] = previousStages;
      }
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('这条评分还没有保存'),
            content: const Text('当前内容仍保留，请关闭提示后重新评分。保存成功前不会计为完成。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回当前卡片'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _gradeWordPipeline(
    ReviewSource source,
    ReviewRecord record,
    fsrs.Rating rating,
  ) async {
    final WordReviewSettings options = ref.read(wordReviewSettingsProvider);
    final List<WordPracticeMode> modes = options.orderedModes;
    final WordPracticeMode mode = modes.isEmpty
        ? WordPracticeMode.recognize
        : modes[_modeStep.clamp(0, modes.length - 1)];
    final List<fsrs.Rating> collected = _stageRatings.putIfAbsent(
      source.key,
      () => <fsrs.Rating>[],
    );

    if (mode == WordPracticeMode.recognize || mode == WordPracticeMode.speak) {
      collected.add(rating);
    }

    // Advance through remaining modes (spell is a pushed stage).
    int step = _modeStep + 1;
    while (step < modes.length) {
      final WordPracticeMode next = modes[step];
      if (next == WordPracticeMode.spell) {
        final SpellStageResult? spelled = await _runSpellStage(source);
        if (!mounted) return;
        if (spelled == null) {
          // User cancelled spelling — keep card, drop this stage attempt.
          if (collected.isNotEmpty) collected.removeLast();
          return;
        }
        collected.add(spelled.rating);
        step += 1;
        continue;
      }
      if (next == WordPracticeMode.speak) {
        setState(() {
          _modeStep = step;
          _revealed = false;
          _retryWord = false;
        });
        return;
      }
      // recognize mid-pipeline shouldn't happen with orderedModes; skip.
      step += 1;
    }

    final bool spellAsStage = modes.contains(WordPracticeMode.spell);
    final bool spellingRequired = options.requireSpelling && !spellAsStage;
    final fsrs.Rating staged = collected.isEmpty
        ? rating
        : weakestRating(collected);

    if (spellingRequired && staged == fsrs.Rating.again) {
      _setWordPasses(source.key, 0);
      _stageRatings.remove(source.key);
      _nextCard(source.key, complete: false);
      return;
    }
    final bool passing =
        staged == fsrs.Rating.good || staged == fsrs.Rating.easy;
    final int? passes = _freshPasses[source.key];
    if (passes != null && !passing) {
      _setWordPasses(source.key, 0);
      _stageRatings.remove(source.key);
      _nextCard(source.key, complete: false);
      return;
    }
    if (spellingRequired) {
      final SpellStageResult? spelled = await _runSpellStage(source);
      if (!mounted || spelled == null) return;
      if (spelled.rating == fsrs.Rating.again) {
        _setWordPasses(source.key, 0);
        _stageRatings.remove(source.key);
        _nextCard(source.key, complete: false);
        return;
      }
      collected.add(spelled.rating);
    }

    final fsrs.Rating finalRating = collected.isEmpty
        ? staged
        : weakestRating(collected);

    if (passes != null && passes < 2) {
      _setWordPasses(source.key, passes + 1);
      _stageRatings.remove(source.key);
      _nextCard(source.key, complete: false);
      return;
    }
    await _finishGrade(source, record, finalRating);
  }

  void _skipCard(ReviewSource source) {
    _advanceCard(source.key);
  }

  void _markDifficult(ReviewSource source) {
    final String? lemma = lemmaFromReviewKey(source.key) ??
        (source.kind == ReviewKind.word ? source.question : null);
    if (lemma != null) {
      ref.read(wordBookProvider.notifier).addWordTag(lemma, '疑难');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已标记为疑难')),
    );
  }

  Future<void> _editNote(ReviewSource source) async {
    final String? lemma = lemmaFromReviewKey(source.key) ??
        (source.kind == ReviewKind.word ? source.question : null);
    if (lemma == null) return;
    final WordEntry? entry = ref
        .read(wordBookProvider)
        .where((WordEntry e) => e.word == lemma)
        .firstOrNull;
    final TextEditingController controller = TextEditingController(
      text: entry?.note ?? '',
    );
    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('补充笔记'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '写下联想或易混点…'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;
    ref.read(wordBookProvider.notifier).setWordNote(lemma, note);
  }

  void _archiveFromSession(ReviewSource source) {
    final String? lemma = lemmaFromReviewKey(source.key);
    if (lemma != null) {
      ref.read(wordBookProvider.notifier).archiveWord(lemma);
    } else if (source.key.startsWith('phrase:')) {
      final String id = source.key.substring('phrase:'.length);
      ref.read(phraseBookProvider.notifier).archivePhrase(id);
    }
    _advanceCard(source.key);
  }

  /// Familiar card: drop from the daily queue without revealing the answer.
  void _slashFamiliar(ReviewSource source) {
    _archiveFromSession(source);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已斩掉：保留在词书，不再进入今日复习')),
    );
  }

  Future<void> _finishGrade(
    ReviewSource source,
    ReviewRecord record,
    fsrs.Rating rating,
  ) async {
    final int? passes = _freshPasses[source.key];
    if (widget.practice) {
      if (passes != null) _setWordPasses(source.key, null);
      _stageRatings.remove(source.key);
      _advanceCard(source.key);
      return;
    }
    final bool passing =
        rating == fsrs.Rating.good || rating == fsrs.Rating.easy;
    if (passes != null && !passing) {
      _setWordPasses(source.key, 0);
      _stageRatings.remove(source.key);
      _nextCard(source.key, complete: false);
      return;
    }
    if (passes != null && passes < 2) {
      _setWordPasses(source.key, passes + 1);
      _stageRatings.remove(source.key);
      _nextCard(source.key, complete: false);
      return;
    }
    final bool wasNew = record.isNew;
    await ref
        .read(dailyReviewProvider.notifier)
        .grade(source.key, rating, expectedReviews: record.reviews);
    if (!mounted) return;
    if (wasNew &&
        source.kind == ReviewKind.word &&
        !widget.practice) {
      final String lemma = source.english.trim().toLowerCase();
      if (lemma.isNotEmpty) {
        unawaited(
          ref.read(learnerSkillProfileProvider.notifier).recordVocabProbe(
                lemma: lemma,
                correct:
                    rating == fsrs.Rating.good || rating == fsrs.Rating.easy,
              ),
        );
      }
    }
    unawaited(ref.read(studyActivityServiceProvider).touchReview());
    ref.read(learningActivityProvider.notifier).recordVocabDuration(
          duration: const Duration(seconds: 25),
        );
    _sessionRatings[source.key] = rating;
    if (rating == fsrs.Rating.again || rating == fsrs.Rating.hard) {
      _missedKeys.add(source.key);
    }
    if (passes != null) _setWordPasses(source.key, null);
    _stageRatings.remove(source.key);
    _advanceCard(source.key);
    final String? episodeId = widget.sourceEpisodeId;
    final String? taskId = widget.todayTaskId;
    if (!_reportedPlanProgress &&
        episodeId != null &&
        source.kind == ReviewKind.word &&
        taskId == 'video-words:$episodeId') {
      try {
        await ref.read(todayPathProvider.notifier).markDone(taskId!);
        _reportedPlanProgress = true;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('评分已保存，今日计划更新失败')),
          );
        }
      }
    }
  }

  void _restoreWordPasses(DateTime now) {
    final String account = ref
        .read(authSessionProvider)
        .email
        .trim()
        .toLowerCase();
    final String key = 'wordFirstDayPasses:${reviewDayKey(now)}:$account';
    if (key == _passStorageKey) return;
    _passStorageKey = key;
    _freshPasses.clear();
    if (!Hive.isBoxOpen('prefs')) return;
    final String? stored = Hive.box<String>('prefs').get(key);
    if (stored == null) return;
    for (final String row in stored.split('\n')) {
      final int tab = row.lastIndexOf('\t');
      if (tab < 0) continue;
      final int? count = int.tryParse(row.substring(tab + 1));
      if (count != null && count >= 0 && count <= 2) {
        _freshPasses[row.substring(0, tab)] = count;
      }
    }
  }

  void _setWordPasses(String source, int? count) {
    if (count == null) {
      _freshPasses.remove(source);
    } else {
      _freshPasses[source] = count;
    }
    final String? key = _passStorageKey;
    if (key != null && Hive.isBoxOpen('prefs')) {
      final String stored = _freshPasses.entries
          .map((MapEntry<String, int> entry) => '${entry.key}\t${entry.value}')
          .join('\n');
      unawaited(
        Hive.box<String>('prefs').put(key, stored).catchError((Object _) {}),
      );
    }
  }

  void _markUnknown(ReviewSource source) {
    setState(() {
      _setWordPasses(source.key, 0);
      _retryWord = true;
      _revealed = true;
    });
  }

  void _prepareReviewWord(ReviewSource source) {
    final String word = source.question;
    if (_prefetchedAudio.add(word)) {
      final resolver = ref.read(wordPronunciationServiceProvider).cloudAudioResolver;
      if (resolver != null) unawaited(resolver(word));
    }
    if (source.answer.trim().isEmpty && _requestedMeanings.add(word)) {
      unawaited(_loadReviewMeaning(word));
    }
  }

  Future<void> _loadReviewMeaning(String word) async {
    try {
      String meaning = (await _reviewDictionary.lookup(word))?.translation.trim() ?? '';
      if (!mounted) return;
      if (meaning.isEmpty) {
        final WordLookupEntry entry = await ref.read(wordLookupServiceProvider).lookupWord(
          rawWord: word,
          settings: ref.read(learningSettingsProvider),
        );
        if (entry.sourceLabel != '未配置') meaning = entry.definitionCn.trim();
      }
      if (!mounted || meaning.isEmpty) return;
      setState(() {
        _reviewMeanings[word] = meaning;
        _choices.removeWhere((String key, List<String> choices) => choices.isEmpty);
      });
    } catch (_) {}
  }

  List<String> _meaningChoices(ReviewSource source, String rawAnswer) {
    final String answer = rawAnswer.trim();
    if (answer.isEmpty) return const <String>[];
    final Set<String> distractors = ref
        .read(reviewSourcesProvider)
        .where(
          (ReviewSource candidate) =>
              candidate.kind == ReviewKind.word &&
              candidate.question != source.question,
        )
        .map((ReviewSource candidate) => candidate.answer.trim())
        .where(
          (String value) =>
              value.isNotEmpty &&
              value != answer &&
              !answer.contains(value) &&
              !value.contains(answer),
        )
        .toSet();
    final List<String> candidates = distractors.toList()..shuffle();
    if (candidates.length < 3) {
      for (final String meaning in const <String>[
        '安排会议',
        '解释原因',
        '选择路线',
        '收集证据',
        '减少开支',
        '维持秩序',
      ]) {
        if (meaning != answer && !candidates.contains(meaning))
          candidates.add(meaning);
      }
    }
    return <String>[answer, ...candidates.take(3)]..shuffle();
  }

  void _stopSpeech() {
    _speechSequence++;
    if (!_speaking) return;
    _speaking = false;
    unawaited(_speech?.stop());
  }

  FoundationMediaItem? _foundationMediaFor(ReviewSource source) {
    final AsyncValue<FoundationMediaManifest> async =
        ref.read(foundationMediaManifestProvider);
    final FoundationMediaManifest? manifest = async.asData?.value;
    if (manifest == null) return null;
    return foundationMediaForReviewKey(manifest, source.key);
  }

  Future<void> _openFoundationVideo(ReviewSource source) async {
    final FoundationMediaItem? item = _foundationMediaFor(source);
    final String? url = item?.videoUrl;
    if (url == null || url.isEmpty) {
      _message('暂无真人示范视频，可上传到服务器后自动出现。');
      return;
    }
    await showFoundationMediaVideoSheet(
      context,
      title: source.question,
      videoUrl: url,
    );
  }

  Future<void> _playWord(ReviewSource source, {bool silent = false}) async {
    final int sequence = _speechSequence;
    if (!mounted ||
        sequence != _speechSequence ||
        _currentKey != source.key ||
        _speaking) {
      return;
    }
    final FoundationMediaItem? foundation = _foundationMediaFor(source);
    final String? foundationAudio = foundation?.audioUrl;
    // Prefer real foundation recordings; otherwise go straight to Aliyun TTS
    // (skip public-lexicon eSpeak — quality is too low for card open).
    if (foundationAudio != null && foundationAudio.isNotEmpty) {
      setState(() => _speaking = true);
      try {
        _speech = ref.read(wordPronunciationServiceProvider);
        await _speech!.speak(
          source.question,
          recordedUrl: foundationAudio,
          allowSynthesisFallback: true,
          forceCloud: true,
          rate: 1.0,
        );
      } on WordPronunciationException catch (error) {
        if (mounted && sequence == _speechSequence && !silent) {
          _message(error.message);
        }
      } catch (_) {
        if (mounted && sequence == _speechSequence && !silent) {
          _message('示范音频播放失败。');
        }
      } finally {
        if (mounted && sequence == _speechSequence) {
          setState(() => _speaking = false);
        }
      }
      return;
    }
    await _speak(source.question);
  }

  List<String> _contrastOptions(String target, List<ConfusablePair> pairs) {
    final List<String> options = <String>[target.trim()];
    for (final ConfusablePair pair in pairs) {
      if (!options.any(
        (String o) => o.toLowerCase() == pair.foil.toLowerCase(),
      )) {
        options.add(pair.foil);
      }
    }
    if (options.length < 2) {
      options.add('${target.trim()}e');
    }
    options.shuffle();
    return options;
  }

  /// Headword with vowel tint + tappable syllable blocks + optional coach.
  Widget _wordPhonicsSurface(
    String word, {
    required bool expandByDefault,
  }) {
    final bool open = _phonicsOpen || expandByDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ColoredVowelHeadword(
          word: word,
          showLegend: open,
          enableSyllableToggle: true,
        ),
        if (open) ...<Widget>[
          const SizedBox(height: 10),
          PhonicsSyllableBlocks(
          word: word,
          compact: !open,
          onSegmentTap: (PhonicsSegment seg) {
            unawaited(_speak(seg.text));
            if (!_phonicsOpen) setState(() => _phonicsOpen = true);
          },
          ),
          const SizedBox(height: 12),
          PhonicsCoachPanel(
            word: word,
            speaking: _speaking,
            onSpeak: (String text) => _speak(text),
          ),
        ],
      ],
    );
  }

  Future<void> _speakSource(ReviewSource source) async {
    final FoundationMediaItem? foundation = _foundationMediaFor(source);
    final String? audio = foundation?.audioUrl;
    if (audio != null && audio.isNotEmpty) {
      if (_speaking) return;
      final int sequence = _speechSequence;
      setState(() => _speaking = true);
      try {
        _speech = ref.read(wordPronunciationServiceProvider);
        await _speech!.speak(
          source.english.isEmpty ? source.question : source.english,
          recordedUrl: audio,
          allowSynthesisFallback: true,
          forceCloud: true,
        );
      } on WordPronunciationException catch (error) {
        if (mounted) _message(error.message);
      } catch (_) {
        if (mounted) _message('示范音频播放失败。');
      } finally {
        if (mounted && sequence == _speechSequence) {
          setState(() => _speaking = false);
        }
      }
      return;
    }
    await _speak(
      source.english.isEmpty ? source.question : source.english,
    );
  }

  Future<void> _speak(String text) async {
    if (_speaking) return;
    final int sequence = _speechSequence;
    setState(() => _speaking = true);
    try {
      _speech = ref.read(wordPronunciationServiceProvider);
      // CosyVoice 龙安风悦 (default); fall back to on-device if CDN blips.
      await _speech!.speak(
        text,
        forceCloud: true,
        allowSynthesisFallback: true,
        rate: 1.0,
      );
    } on WordPronunciationException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message('阿里云发音失败，请确认已登录，或在设置里切换配音音色。');
      }
    } finally {
      if (mounted && sequence == _speechSequence)
        setState(() => _speaking = false);
    }
  }

  Future<void> _addMoreNewWordsToday() async {
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
                  '只增加今天的新学额度，明天仍按你设定的基础数量。',
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
    final TodayJourneyStore store = TodayJourneyStore(
      ref.read(studyAccountProvider),
      DateTime.now(),
    );
    final int effective;
    if (!store.studyPlan.quotasConfigured) {
      await store.saveQuotas(
        videoMinutes: 0,
        vocabCount: n,
        readingWords: 0,
      );
      effective = n;
    } else {
      effective = await store.addVocabBonus(n);
    }
    await ref.read(wordReviewSettingsProvider.notifier).setDailyNewLimit(
          effective.clamp(0, 150),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('今日新学额度 +$n，现在可继续背词')),
    );
    setState(() {});
  }

  Future<void> _showSettings(int currentLimit) async {
    final TextEditingController controller = TextEditingController(
      text: '$currentLimit',
    );
    final GlobalKey<FormState> form = GlobalKey<FormState>();
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '复习设置',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('daily-review-new-limit'),
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: '每天新学数量',
                    helperText: '每日 5–150 条，输入 0 可暂停新学。',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) {
                    final int? count = int.tryParse(value ?? '');
                    return count == null ||
                            (count != 0 && (count < 5 || count > 150))
                        ? '请输入 5–150 的整数，或输入 0 暂停'
                        : null;
                  },
                ),
                const SizedBox(height: 18),
                Text(
                  '更改设置不会清空收藏或已有进度。待复习内容不受新学数量限制。',
                  style: TextStyle(height: 1.6, color: Color(0xFF626262)),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) return;
                          setSheetState(() => saving = true);
                          try {
                            await ref
                                .read(dailyReviewProvider.notifier)
                                .setDailyNewLimit(int.parse(controller.text));
                            if (!mounted || !sheetContext.mounted) return;
                            Navigator.pop(sheetContext);
                            setState(() {
                              _currentKey = null;
                              _revealed = false;
                            });
                          } catch (_) {
                            if (sheetContext.mounted) {
                              setSheetState(() => saving = false);
                            }
                            if (mounted) _message('设置未能保存，请重试。');
                          }
                        },
                  style: _primaryButtonStyle,
                  child: Text(saving ? '正在保存…' : '保存设置'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // The sheet's exit animation may still reference the controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

final ButtonStyle _primaryButtonStyle = ReviewRecallTheme.primaryButton;

class _ReviewSurface extends StatelessWidget {
  const _ReviewSurface({required this.child, this.compact = false});
  final Widget child;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final bool narrow = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: EdgeInsets.all(
        compact || narrow ? (compact ? 14.0 : 18.0) : 32,
      ),
      decoration: BoxDecoration(
        color: ReviewRecallTheme.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: ReviewRecallTheme.border.withValues(alpha: 0.7),
        ),
      ),
      child: child,
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  const _ReviewMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        value,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: AppDesignTokens.textPrimary,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: TextStyle(fontSize: 13, color: AppDesignTokens.textSecondary),
      ),
    ],
  );
}

class _MicroReviewActiveCard extends ConsumerWidget {
  const _MicroReviewActiveCard({required this.state});

  final MicroReviewUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '碎片记忆 · ${state.remainingLabel}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '已记 ${state.ratedCount}',
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.word,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          if (state.gloss.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              state.gloss,
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed: () => ref
                    .read(microReviewProvider.notifier)
                    .rateCurrent(fsrs.Rating.good),
                child: const Text('认识'),
              ),
              OutlinedButton(
                onPressed: () => ref
                    .read(microReviewProvider.notifier)
                    .rateCurrent(fsrs.Rating.hard),
                child: const Text('模糊'),
              ),
              OutlinedButton(
                onPressed: () => ref
                    .read(microReviewProvider.notifier)
                    .rateCurrent(fsrs.Rating.again),
                child: const Text('忘记'),
              ),
              TextButton(
                onPressed: () => ref.read(microReviewProvider.notifier).stop(),
                child: const Text('结束'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDue(DateTime due, DateTime now) {
  final DateTime local = due.toLocal();
  final String time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return reviewDayKey(due) == reviewDayKey(now)
      ? '今天 $time'
      : '${local.month}月${local.day}日 $time';
}

String _formatReviewDelay(DateTime due, DateTime now) {
  final int seconds = due.difference(now).inSeconds;
  if (seconds < 60) return '不到 1 分钟后';
  if (seconds < 3600) return '${(seconds / 60).ceil()} 分钟后';
  if (seconds < 86400) return '${(seconds / 3600).ceil()} 小时后';
  return '${(seconds / 86400).ceil()} 天后';
}
