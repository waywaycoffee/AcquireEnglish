import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../data/micro_review_island_bridge.dart';
import '../domain/micro_review_session.dart';

const String kMicroReviewIslandEnabledKey = 'micro_review_island_enabled_v1';

bool isMicroReviewIslandEnabled() {
  try {
    final String? raw =
        Hive.box<String>('prefs').get(kMicroReviewIslandEnabledKey);
    if (raw == null) return true;
    return raw != '0' && raw.toLowerCase() != 'false';
  } catch (_) {
    return true;
  }
}

Future<void> setMicroReviewIslandEnabled(bool enabled) async {
  await Hive.box<String>('prefs').put(
    kMicroReviewIslandEnabledKey,
    enabled ? '1' : '0',
  );
}

class MicroReviewIslandEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => isMicroReviewIslandEnabled();

  Future<void> setEnabled(bool enabled) async {
    await setMicroReviewIslandEnabled(enabled);
    state = enabled;
  }
}

final NotifierProvider<MicroReviewIslandEnabledNotifier, bool>
microReviewIslandEnabledProvider =
    NotifierProvider<MicroReviewIslandEnabledNotifier, bool>(
      MicroReviewIslandEnabledNotifier.new,
    );

class MicroReviewUiState {
  const MicroReviewUiState({
    this.active = false,
    this.word = '',
    this.gloss = '',
    this.remainingLabel = '05:00',
    this.ratedCount = 0,
    this.total = 0,
    this.message,
  });

  final bool active;
  final String word;
  final String gloss;
  final String remainingLabel;
  final int ratedCount;
  final int total;
  final String? message;

  MicroReviewUiState copyWith({
    bool? active,
    String? word,
    String? gloss,
    String? remainingLabel,
    int? ratedCount,
    int? total,
    String? message,
    bool clearMessage = false,
  }) {
    return MicroReviewUiState(
      active: active ?? this.active,
      word: word ?? this.word,
      gloss: gloss ?? this.gloss,
      remainingLabel: remainingLabel ?? this.remainingLabel,
      ratedCount: ratedCount ?? this.ratedCount,
      total: total ?? this.total,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

final NotifierProvider<MicroReviewController, MicroReviewUiState>
microReviewProvider =
    NotifierProvider<MicroReviewController, MicroReviewUiState>(
      MicroReviewController.new,
    );

class MicroReviewController extends Notifier<MicroReviewUiState> {
  MicroReviewSession? _session;
  MicroReviewIslandBridge? _bridge;
  StreamSubscription<MicroReviewIslandAction>? _actionSub;
  Timer? _tick;
  bool _busy = false;

  @override
  MicroReviewUiState build() {
    ref.onDispose(() {
      _tick?.cancel();
      unawaited(_actionSub?.cancel());
      _bridge?.dispose();
    });
    return const MicroReviewUiState();
  }

  Future<String?> start() async {
    if (_busy) return '正在启动碎片记忆…';
    if (_session != null && !_session!.ended) {
      return '碎片记忆进行中';
    }
    _busy = true;
    try {
      final DailyReviewState review = ref.read(dailyReviewProvider);
      final List<ReviewSource> sources = ref.read(reviewSourcesProvider);
      final DateTime now = ref.read(reviewClockProvider)();
      final ReviewPlan plan = review.plan(sources, now);
      final List<MicroReviewCard> cards = MicroReviewSession.snapshotFromPlan(
        plan: plan,
        sources: sources,
      );
      if (cards.isEmpty) {
        return '暂无到期内容，先去学习或收藏表达吧。';
      }
      final MicroReviewSession session = MicroReviewSession(cards: cards)
        ..markShown(now);
      _session = session;
      _bridge?.dispose();
      _bridge = createMicroReviewIslandBridge();
      await _actionSub?.cancel();
      _actionSub = _bridge!.actions.listen(_onIslandAction);
      _publishUi();
      if (isMicroReviewIslandEnabled()) {
        await _bridge!.start(MicroReviewIslandPayload.fromSession(session));
      }
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<void> stop({
    MicroReviewEndReason reason = MicroReviewEndReason.cancelled,
  }) async {
    final MicroReviewSession? session = _session;
    if (session == null) return;
    if (!session.ended) session.end(reason);
    _tick?.cancel();
    _tick = null;
    await _bridge?.end();
    final int rated = session.ratedCount;
    _session = null;
    state = MicroReviewUiState(active: false, message: '本轮记了 $rated 词');
  }

  Future<void> rateCurrent(fsrs.Rating rating) async {
    final MicroReviewSession? session = _session;
    final MicroReviewCard? card = session?.current;
    if (session == null || card == null || session.ended) return;
    final DailyReviewState review = ref.read(dailyReviewProvider);
    final ReviewRecord? record = review.records[card.key];
    final int expected = record?.reviews ?? 0;
    try {
      await ref
          .read(dailyReviewProvider.notifier)
          .grade(card.key, rating, expectedReviews: expected);
    } catch (_) {}
    session.rate(rating);
    await _afterAdvance();
  }

  Future<void> skipCurrent() async {
    final MicroReviewSession? session = _session;
    if (session == null || session.ended) return;
    session.skip(auto: false);
    await _afterAdvance();
  }

  void _onTick() {
    final MicroReviewSession? session = _session;
    if (session == null) return;
    final bool changed = session.tick(DateTime.now());
    if (session.ended) {
      unawaited(stop(reason: session.endReason ?? MicroReviewEndReason.timer));
      return;
    }
    _publishUi();
    // Always push so countdown / timerInfo stay fresh on OEM islands.
    unawaited(_pushIsland());
    if (changed) {
      // Card advanced via auto-skip.
    }
  }

  Future<void> _afterAdvance() async {
    final MicroReviewSession? session = _session;
    if (session == null) return;
    if (session.ended) {
      await stop(reason: session.endReason ?? MicroReviewEndReason.completed);
      return;
    }
    _publishUi();
    await _pushIsland();
  }

  Future<void> _pushIsland() async {
    final MicroReviewSession? session = _session;
    final MicroReviewIslandBridge? bridge = _bridge;
    if (session == null || bridge == null || !isMicroReviewIslandEnabled()) {
      return;
    }
    await bridge.update(MicroReviewIslandPayload.fromSession(session));
  }

  void _publishUi() {
    final MicroReviewSession? session = _session;
    if (session == null || session.ended) {
      state = state.copyWith(active: false);
      return;
    }
    final MicroReviewCard? card = session.current;
    state = MicroReviewUiState(
      active: true,
      word: card?.word ?? '',
      gloss: card?.gloss ?? '',
      remainingLabel: session.remainingLabel,
      ratedCount: session.ratedCount,
      total: session.cards.length,
    );
  }

  void _onIslandAction(MicroReviewIslandAction action) {
    switch (action.kind) {
      case MicroReviewIslandActionKind.know:
        unawaited(rateCurrent(fsrs.Rating.good));
      case MicroReviewIslandActionKind.fuzzy:
        unawaited(rateCurrent(fsrs.Rating.hard));
      case MicroReviewIslandActionKind.forget:
        unawaited(rateCurrent(fsrs.Rating.again));
      case MicroReviewIslandActionKind.end:
        unawaited(stop());
      case MicroReviewIslandActionKind.open:
        state = state.copyWith(message: 'open_review');
    }
  }
}

Future<void> startMicroReviewFromUi(
  BuildContext context,
  WidgetRef ref,
) async {
  final String? err = await ref.read(microReviewProvider.notifier).start();
  if (!context.mounted) return;
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    return;
  }
  final MicroReviewUiState ui = ref.read(microReviewProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ui.active
            ? '碎片记忆已开始 · ${ui.remainingLabel} · 可在灵动岛/通知栏操作'
            : '碎片记忆已开始',
      ),
    ),
  );
}

void handleMicroReviewOpenMessage(BuildContext context, WidgetRef ref) {
  final String? msg = ref.read(microReviewProvider).message;
  if (msg != 'open_review') return;
  context.go(AppNavDestination.review.route);
}
