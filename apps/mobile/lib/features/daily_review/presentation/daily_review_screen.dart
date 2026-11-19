import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/auth_session.dart';

import '../../../router/app_router.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/domain/word_lookup_entry.dart';
import '../../shared/domain/subtitle_letter_case.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../words/presentation/vocabulary_placement_provider.dart';
import '../../words/domain/word_review_settings.dart';
import '../../words/presentation/word_review_settings_provider.dart';
import '../../words/presentation/word_review_settings_sheet.dart';
import '../../authentication/presentation/account_storage.dart';
import '../data/missed_review_book.dart';
import '../domain/daily_review.dart';
import 'daily_review_provider.dart';
import 'review_spelling_screen.dart';

class DailyReviewScreen extends ConsumerStatefulWidget {
  const DailyReviewScreen({
    super.key,
    this.session = false,
    this.practice = false,
    this.practiceKind,
    this.expressions = false,
    this.recommended = false,
  });
  final bool session;
  final bool recommended;
  final bool practice;
  final bool expressions;
  final ReviewKind? practiceKind;
  @override
  ConsumerState<DailyReviewScreen> createState() => _DailyReviewScreenState();
}

class _DailyReviewScreenState extends ConsumerState<DailyReviewScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  final ScrollController _sessionScroll = ScrollController();
  String? _currentKey;
  List<String>? _deckKeys;
  final Set<String> _completedKeys = <String>{};
  final Set<String> _missedKeys = <String>{};
  final Map<String, int> _freshPasses = <String, int>{};
  String? _passStorageKey;
  final Map<String, List<String>> _choices = <String, List<String>>{};
  String? _playedWord;
  bool _retryWord = false;
  bool _forward = true;
  bool _revealed = false;
  bool _saving = false;
  bool _speaking = false;
  int _speechSequence = 0;
  WordPronunciationService? _speech;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(dailyReviewProvider.notifier).scheduleCloudBackup();
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      ref.read(dailyReviewProvider.notifier).scheduleCloudBackup();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sessionScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _stopSpeech();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DailyReviewState state = ref.watch(dailyReviewProvider);
    final List<ReviewSource> sources = ref
        .watch(reviewSourcesProvider)
        .where(
          (ReviewSource source) =>
              source.key.startsWith('recommended:') == widget.recommended,
        )
        .toList();
    final DateTime now = ref.read(reviewClockProvider)();
    if (widget.session) _restoreWordPasses(now);
    final ReviewPlan plan = state.plan(sources, now);
    return PadScaffold(
      currentDestination: AppNavDestination.review,
      showContinueLearning: false,
      showNavigation: !widget.session,
      topBar: PadTopBar(
        title: widget.recommended
            ? '推荐背词'
            : widget.session
            ? (widget.practice ? '自由复习' : '正在复习')
            : '每日复习',
        description: widget.session
            ? (widget.practice ? '随时再练，不改变复习计划。' : null)
            : '复习单词、短语和收藏句子。',
        leading: widget.session
            ? PadBackButton(onPressed: _leaveSession, tooltip: '返回每日概览')
            : null,
        actions: <Widget>[
          if (widget.session &&
              sources.any(
                (ReviewSource source) => source.kind == ReviewKind.word,
              ))
            IconButton(
              tooltip: '背词方式与拼写',
              onPressed: _saving
                  ? null
                  : () => showWordReviewSettingsSheet(context),
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
        trailing: widget.session
            ? TextButton(
                onPressed: _saving ? null : _leaveSession,
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
          ? _buildSessionBody(state, sources, plan, now)
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
                                  style: const TextStyle(
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

  void _leaveSession() {
    if (_saving) return;
    if (context.canPop()) {
      context.pop();
    } else {
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
    final ReviewKind? kind = widget.practiceKind;
    if (widget.practice && (kind != null || widget.expressions)) {
      _deckKeys = sources
          .where(
            (ReviewSource source) => widget.expressions
                ? source.kind != ReviewKind.sentence
                : source.kind == kind,
          )
          .map((ReviewSource source) => source.key)
          .where(state.records.containsKey)
          .toList();
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
    final List<ReviewRecord> due = <ReviewRecord>[...plan.due];
    final Set<String> activeKeys = sources
        .map((ReviewSource source) => source.key)
        .toSet();
    final List<String> missedPriority = MissedReviewBook(
      account: ref.read(studyAccountProvider),
    ).prioritize(activeKeys);
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
    final List<ReviewRecord> fresh = plan.waiting
        .take(plan.newAvailable)
        .toList();
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
      _retryWord = false;
      _revealed = _completedKeys.contains(_currentKey);
    });
  }

  Widget _buildSessionBody(
    DailyReviewState state,
    List<ReviewSource> sources,
    ReviewPlan plan,
    DateTime now,
  ) {
    _prepareDeck(plan, state, sources, now);
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
    if (visible?.kind == ReviewKind.word && _playedWord != visible?.key) {
      _playedWord = visible!.key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentKey == visible.key) {
          unawaited(_playWord(visible, silent: true));
        }
      });
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            key: const Key('daily-review-session-scroll'),
            controller: _sessionScroll,
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 32,
              16,
              compact ? 12 : 32,
              28,
            ),
            children: <Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 16 : 32,
                        ),
                        child: Column(
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  '${widget.practice ? '已练习' : '已完成'} $completed / ${keys.length}',
                                  key: const Key(
                                    'daily-review-session-progress',
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppDesignTokens.textPrimary,
                                  ),
                                ),
                                Text(
                                  finished
                                      ? '本轮已完成'
                                      : '还剩 ${keys.length - completed} 张',
                                  style: TextStyle(
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: keys.isEmpty ? 0 : completed / keys.length,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(6),
                              backgroundColor: AppDesignTokens.borderGray,
                              color: AppDesignTokens.brandGreen,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
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
                                  color: AppDesignTokens.brandGreenDark,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  keys.isEmpty
                                      ? '暂时没有可复习的卡片'
                                      : widget.practice
                                      ? '这轮自由复习完成了'
                                      : '这一轮，完成了',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.practice
                                      ? '这轮练习不会改变复习计划或新学额度，想巩固时可以随时再练。'
                                      : sources.isEmpty
                                      ? '在播放器收藏单词，或把表达加入短语库，它们就会进入统一的复习计划。'
                                      : plan.next == null
                                      ? _completionText(
                                          plan,
                                          state.dailyNewLimit,
                                          now,
                                        )
                                      : '本轮进度已保存，还有到期或新加入的内容可以继续。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    height: 1.7,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                FilledButton(
                                  onPressed: _leaveSession,
                                  style: _primaryButtonStyle,
                                  child: const Text('返回每日概览'),
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
                        )
                      else
                        Stack(
                          children: <Widget>[
                            Positioned.fill(
                              top: 24,
                              bottom: 24,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Expanded(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: AppDesignTokens.isDark
                                            ? const Color(0xFF1C3038)
                                            : const Color(0xFFE9F3E0),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 40),
                                  Expanded(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: AppDesignTokens.isDark
                                            ? const Color(0xFF1C3038)
                                            : const Color(0xFFE9F3E0),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 14 : 32,
                              ),
                              child: AnimatedSwitcher(
                                duration: duration,
                                layoutBuilder:
                                    (
                                      Widget? currentChild,
                                      List<Widget> previousChildren,
                                    ) =>
                                        currentChild ?? const SizedBox.shrink(),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeOutCubic,
                                transitionBuilder:
                                    (
                                      Widget child,
                                      Animation<double> animation,
                                    ) => FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: Offset(
                                            _forward ? 0.06 : -0.06,
                                            0,
                                          ),
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
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!finished)
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 24 : 40,
                12,
                compact ? 24 : 40,
                20,
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
                '只复习你收藏的单词和短语库里的表达。自动记录但没有收藏的单词不会加入；取消收藏或删除后，也会停止安排。',
              ),
              (
                Icons.event_repeat_rounded,
                '为什么不用每天全部重学？',
                'FSRS 会根据你每次的回忆情况，调整下次复习时间。忘记的早点再见，记得牢的间隔更久，让练习用在需要巩固的地方。',
              ),
              (
                Icons.style_outlined,
                '开始后怎么学？',
                '计划复习时，先回忆、显示答案核对，再如实评分，系统会安排下次复习时间。一天可以多次复习；暂时没有到期内容时，也可以用“再次复习”自由练习已学内容，不改变计划或新学额度。',
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
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        color: Color(0xFF626262),
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
        ? '这一轮，完成了'
        : plan.today.reviews > 0
        ? '继续今天的记忆练习'
        : '今天，也给记忆一点时间';
    return _ReviewSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
                ? '在播放器收藏单词，或把表达加入短语库，它们就会进入统一的复习计划。'
                : done
                ? _completionText(plan, state.dailyNewLimit, now)
                : '先尝试回忆，再揭晓答案。每次如实反馈，系统会安排适合它的下次见面时间。',
            style: const TextStyle(
              fontSize: 15,
              height: 1.65,
              color: Color(0xFF626262),
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 28,
            runSpacing: 20,
            children: <Widget>[
              _ReviewMetric(label: '到期复习', value: '${plan.due.length}'),
              _ReviewMetric(label: '今日可新学', value: '${plan.newAvailable}'),
              _ReviewMetric(label: '今天已练习', value: '${plan.today.reviews} 次'),
            ],
          ),
          const SizedBox(height: 30),
          if (!empty && !done)
            FilledButton.icon(
              key: const Key('daily-review-start'),
              onPressed: () => context.push(SGRoute.reviewSession.route),
              style: _primaryButtonStyle,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(plan.today.reviews > 0 ? '再次复习' : '开始今日复习'),
            )
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
              onPressed: () =>
                  context.push('${SGRoute.reviewSession.route}?practice=1'),
              style: _primaryButtonStyle,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('再次复习'),
            ),
            const SizedBox(height: 10),
            const Text(
              '当前没有到期内容，可以自由练习已学内容，不改变复习计划或新学额度。',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xFF626262),
              ),
            ),
          ],
          if (!empty && done && plan.waiting.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showSettings(state.dailyNewLimit),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('调整每天新学数量'),
            ),
          ],
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
                label: const Text('词汇量测试'),
                onPressed: () =>
                    context.push(SGRoute.vocabularyPlacement.route),
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
        : '还有 ${plan.waiting.length} 条待学内容，会按收藏入队顺序逐步安排。';
    final String next = plan.nextDue == null
        ? ''
        : '下一条到期：${_formatDue(plan.nextDue!, now)}。';
    if (limit == 0) return '新学已暂停，到期复习会继续安排。$waiting$next';
    return '当前没有需要立即复习的内容。$waiting$next';
  }

  Widget _buildStudy(ReviewSource source, ReviewRecord record) {
    final WordReviewSettings options = ref.watch(wordReviewSettingsProvider);
    final bool word = source.kind == ReviewKind.word;
    final List<String> choices =
        word && options.recallStyle == WordRecallStyle.multipleChoice
        ? _choices.putIfAbsent(source.key, () => _meaningChoices(source))
        : const <String>[];
    final bool choiceMode = choices.length == 4;
    final int? passes = _freshPasses[source.key];
    final bool completed = _completedKeys.contains(source.key);
    final DateTime now = ref.read(reviewClockProvider)();
    final String letterCase = ref.watch(
      learningSettingsProvider.select(
        (LearningSettingsState settings) => settings.subtitleLetterCase,
      ),
    );
    return _ReviewSurface(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).width < 600 ? 320 : 380,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${source.kind.label} · ${widget.practice
                        ? '自由练习'
                        : record.isNew
                        ? '首次学习'
                        : '到期复习'}',
                    style: const TextStyle(
                      color: Color(0xFF377D05),
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
            const SizedBox(height: 20),
            Text(
              source.answer != source.english ? '先回忆中文含义' : '先试着用英语说出来',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF626262)),
            ),
            const SizedBox(height: 18),
            SelectableText(
              source.question,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: source.kind == ReviewKind.word ? 34 : 25,
                height: 1.45,
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${source.sourceLabel}${source.time == null ? '' : ' · ${source.time}'}',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF626262),
                    ),
                  ),
                ),
                if (word)
                  IconButton(
                    tooltip: '播放单词发音',
                    onPressed: _speaking ? null : () => _playWord(source),
                    icon: const Icon(Icons.volume_up_rounded),
                  ),
                IconButton(
                  tooltip: _speaking ? '正在朗读' : '听原句',
                  onPressed: _speaking || source.english.isEmpty
                      ? null
                      : () => _speak(source.english),
                  icon: const Icon(Icons.volume_up_outlined),
                ),
                if (source.episodeId != null)
                  IconButton(
                    tooltip: '回到原视频',
                    onPressed: () => context.pushNamed(
                      SGRoute.player.name,
                      pathParameters: <String, String>{
                        'episodeId': source.episodeId!,
                      },
                      queryParameters: <String, String>{
                        if (source.time != null) 'startTime': source.time!,
                        'autoplay': '1',
                      },
                    ),
                    icon: const Icon(Icons.ondemand_video_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            if (!_revealed && !completed) ...<Widget>[
              if (choiceMode)
                for (final String choice in choices)
                  OutlinedButton(
                    onPressed: () {
                      if (choice == source.answer.trim()) {
                        setState(() => _revealed = true);
                      } else {
                        _markUnknown(source);
                      }
                    },
                    child: Text(choice),
                  )
              else
                FilledButton.icon(
                  key: const Key('daily-review-reveal'),
                  onPressed: () => setState(() => _revealed = true),
                  style: _primaryButtonStyle,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('显示答案'),
                ),
              if (word && (record.isNew || choiceMode))
                TextButton(
                  onPressed: () => _markUnknown(source),
                  child: const Text('这是生词'),
                ),
            ] else ...<Widget>[
              const Divider(height: 24),
              Text(
                source.answer.trim().isEmpty
                    ? '暂无单词释义，可以结合下方原句回忆，或在单词本补充。'
                    : source.kind != ReviewKind.word &&
                          source.answer == source.english
                    ? formatSubtitleLetterCase(source.answer, letterCase)
                    : source.answer,
                style: TextStyle(
                  fontSize: 23,
                  height: 1.5,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              if (source.answer != source.english &&
                  source.english.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  formatSubtitleLetterCase(source.english, letterCase),
                  style: const TextStyle(fontSize: 16, height: 1.6),
                ),
                if (source.chinese.isNotEmpty)
                  Text(
                    source.chinese,
                    style: const TextStyle(
                      height: 1.6,
                      color: Color(0xFF626262),
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
                const Text(
                  '自由练习不评分，不改变下次到期时间或新学额度。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: Color(0xFF626262),
                  ),
                ),
              ],
              if (!completed &&
                  !_retryWord &&
                  !choiceMode &&
                  !widget.practice) ...<Widget>[
                const SizedBox(height: 26),
                const Text(
                  '刚才回忆得怎么样？忘记了就选“忘记”，不要选“费力想起”。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: Color(0xFF626262),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: <Widget>[
                        for (final (
                              fsrs.Rating rating,
                              String label,
                              String hint,
                              Color color,
                            )
                            in <(fsrs.Rating, String, String, Color)>[
                              (
                                fsrs.Rating.again,
                                '忘记',
                                '没想起 · 重学',
                                const Color(0xFFAF3434),
                              ),
                              (
                                fsrs.Rating.hard,
                                '费力想起',
                                '想对了，但吃力',
                                const Color(0xFF925600),
                              ),
                              (
                                fsrs.Rating.good,
                                '记得',
                                '正常回忆出来',
                                const Color(0xFF377D05),
                              ),
                              (
                                fsrs.Rating.easy,
                                '很轻松',
                                '立刻轻松答对',
                                const Color(0xFF0874A8),
                              ),
                            ])
                          SizedBox(
                            width: constraints.maxWidth < 520
                                ? (constraints.maxWidth - 8) / 2
                                : (constraints.maxWidth - 24) / 4,
                            child: OutlinedButton(
                              key: Key('daily-review-rate-${rating.name}'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: color,
                                minimumSize: const Size(0, 84),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                              ),
                              onPressed: _saving
                                  ? null
                                  : () => _grade(source, record, rating),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    hint,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '预计 ${_formatReviewDelay(record.scheduledCard(rating, now).due, now)}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
            const SizedBox(height: 20),
            Text(
              completed
                  ? (widget.practice ? '本轮已练习，不影响原有复习计划' : '已完成，这张卡片的进度已保存')
                  : widget.practice
                  ? '先回忆，再揭晓；随时都能再练一轮'
                  : '先回忆，再揭晓；如实反馈就好',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF626262)),
            ),
          ],
        ),
      ),
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
        const Text(
          '到期内容按等待时间优先复习；每完成 4 次到期复习，穿插 1 条新学。新内容按入队顺序轮到，未完成的会保留。',
          style: TextStyle(fontSize: 13, height: 1.7, color: Color(0xFF626262)),
        ),
        if (plan.waiting.length > limit && limit > 0) ...<Widget>[
          const SizedBox(height: 8),
          const Text(
            '如果收藏速度持续超过学习速度，待学会增加。可以调整新学数量，或先放慢新增节奏。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Color(0xFF626262),
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
    setState(() {
      if (complete) _completedKeys.add(key);
      _retryWord = false;
      _playedWord = null;
      _choices.remove(key);
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
  }

  Future<void> _grade(
    ReviewSource source,
    ReviewRecord record,
    fsrs.Rating rating,
  ) async {
    if (_saving || _completedKeys.contains(source.key)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final bool spellingRequired =
          source.kind == ReviewKind.word &&
          ref.read(wordReviewSettingsProvider).requireSpelling;
      if (spellingRequired && rating == fsrs.Rating.again) {
        _setWordPasses(source.key, 0);
        _nextCard(source.key, complete: false);
        return;
      }
      final bool passing =
          rating == fsrs.Rating.good || rating == fsrs.Rating.easy;
      final int? passes = _freshPasses[source.key];
      if (passes != null && !passing) {
        _setWordPasses(source.key, 0);
        _nextCard(source.key, complete: false);
        return;
      }
      if (spellingRequired) {
        _stopSpeech();
        final bool? spelled = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => ReviewSpellingScreen(
              word: source.question,
              meaning: source.answer,
            ),
          ),
        );
        if (!mounted || spelled != true) return;
      }
      if (passes != null && passes < 2) {
        _setWordPasses(source.key, passes + 1);
        _nextCard(source.key, complete: false);
        return;
      }
      if (widget.practice) {
        if (passes != null) _setWordPasses(source.key, null);
        _advanceCard(source.key);
        return;
      }
      await ref
          .read(dailyReviewProvider.notifier)
          .grade(source.key, rating, expectedReviews: record.reviews);
      if (!mounted) return;
      if (passes != null) _setWordPasses(source.key, null);
      _advanceCard(source.key);
    } catch (_) {
      if (mounted) _message('这次进度未能保存，请重试；当前内容仍保留。');
    } finally {
      if (mounted) setState(() => _saving = false);
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

  List<String> _meaningChoices(ReviewSource source) {
    final String answer = source.answer.trim();
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

  Future<void> _playWord(ReviewSource source, {bool silent = false}) async {
    final int sequence = _speechSequence;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final WordLookupEntry? entry = await ref
        .read(wordLookupServiceProvider)
        .publicLookup
        ?.call(source.question, settings);
    if (!mounted ||
        sequence != _speechSequence ||
        _currentKey != source.key ||
        _speaking)
      return;
    final String? url = entry?.audioUrl;
    if (url == null) {
      if (!silent) _message('词库发音暂不可用。');
      return;
    }
    setState(() => _speaking = true);
    try {
      _speech = ref.read(wordPronunciationServiceProvider);
      await _speech!.speak(
        source.question,
        recordedUrl: url,
        allowSynthesisFallback: false,
      );
    } catch (_) {
      if (mounted && sequence == _speechSequence && !silent) {
        _message('词库发音暂不可用。');
      }
    } finally {
      if (mounted && sequence == _speechSequence)
        setState(() => _speaking = false);
    }
  }

  Future<void> _speak(String text) async {
    if (_speaking) return;
    final int sequence = _speechSequence;
    setState(() => _speaking = true);
    try {
      _speech = ref.read(wordPronunciationServiceProvider);
      await _speech!.speak(text);
    } catch (_) {
      if (mounted) _message('朗读失败，请检查设备的语音设置。');
    } finally {
      if (mounted && sequence == _speechSequence)
        setState(() => _speaking = false);
    }
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
                const Text(
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
                    helperText: '单词和短语合计，0–100 条；设为 0 可暂停新学。',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) {
                    final int? count = int.tryParse(value ?? '');
                    return count == null || count < 0 || count > 100
                        ? '请输入 0–100 的整数'
                        : null;
                  },
                ),
                const SizedBox(height: 18),
                const Text(
                  '更改设置不会清空收藏或已有进度。到期复习不受新学数量限制。',
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

final ButtonStyle _primaryButtonStyle = FilledButton.styleFrom(
  backgroundColor: AppDesignTokens.brandGreen,
  foregroundColor: Colors.white,
  minimumSize: const Size(0, 50),
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
);

class _ReviewSurface extends StatelessWidget {
  const _ReviewSurface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 22 : 32),
    decoration: BoxDecoration(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppDesignTokens.borderGray),
      boxShadow: AppDesignTokens.toyCardShadow,
    ),
    child: child,
  );
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
