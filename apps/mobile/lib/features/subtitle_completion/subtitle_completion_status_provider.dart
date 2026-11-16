import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'subtitle_completion_enqueue.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_scheduler.dart';
import 'subtitle_completion_status_hub.dart';

/// Live snapshot of one episode's import-time subtitle fill job.
class SubtitleCompletionEpisodeUi {
  const SubtitleCompletionEpisodeUi({
    required this.episodeId,
    required this.status,
    required this.needEnglish,
    required this.needChinese,
    this.label,
    this.lastError,
    this.attempts = 0,
  });

  final String episodeId;
  final SubtitleCompletionStatus status;
  final bool needEnglish;
  final bool needChinese;
  final String? label;
  final String? lastError;
  final int attempts;

  bool get isActive =>
      status == SubtitleCompletionStatus.pending ||
      status == SubtitleCompletionStatus.running;

  bool get isFailed => status == SubtitleCompletionStatus.failed;

  String get displayLabel {
    final String? live = label?.trim();
    if (live != null && live.isNotEmpty) {
      return live;
    }
    switch (status) {
      case SubtitleCompletionStatus.running:
        if (needEnglish && needChinese) {
          return '正在补全中英文字幕…';
        }
        if (needEnglish) {
          return '正在用语音生成英文字幕…';
        }
        return '正在翻译中文字幕…';
      case SubtitleCompletionStatus.pending:
        if (needEnglish && needChinese) {
          return '等待补全中英文字幕…';
        }
        if (needEnglish) {
          return '等待语音生成英文字幕…';
        }
        return '等待翻译中文字幕…';
      case SubtitleCompletionStatus.failed:
        final String? err = lastError?.trim();
        if (err != null && err.isNotEmpty) {
          return '字幕补全失败：$err';
        }
        return '字幕补全失败，可重试';
      case SubtitleCompletionStatus.done:
        return '字幕已补全';
    }
  }

  /// 0–1 progress for list-page bars; null when idle/unknown.
  double? get progressFraction {
    if (!isActive) {
      return null;
    }
    final String live = (label ?? '').trim();
    final RegExpMatch? pct =
        RegExp(r'（(\d{1,3})%）').firstMatch(live) ??
        RegExp(r'(\d{1,3})%').firstMatch(live);
    if (pct != null) {
      final int value = int.tryParse(pct.group(1) ?? '') ?? 0;
      return (value / 100).clamp(0.0, 1.0);
    }
    final RegExpMatch? frac = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(live);
    if (frac != null) {
      final int done = int.tryParse(frac.group(1) ?? '') ?? 0;
      final int total = int.tryParse(frac.group(2) ?? '') ?? 0;
      if (total > 0) {
        return (done / total).clamp(0.0, 1.0);
      }
    }
    if (status == SubtitleCompletionStatus.running) {
      return 0.12;
    }
    return 0.05;
  }

  /// Progress text for the English fill chip (null = keep default chip label).
  String? get englishChipProgressLabel {
    if (!needEnglish || (!isActive && !isFailed)) {
      return null;
    }
    if (isFailed) {
      return '补英文失败，点重试';
    }
    final String live = (label ?? '').trim();
    if (live.isNotEmpty) {
      // Live worker label is about Chinese → English chip stays brief.
      if (needChinese &&
          (live.contains('中文') || live.contains('翻译')) &&
          !live.contains('英文') &&
          !live.contains('语音')) {
        return '英文已就绪';
      }
      return _chipSizedLabel(live, side: '英文');
    }
    if (status == SubtitleCompletionStatus.running) {
      return needChinese ? '正在补英文…' : '正在补英文字幕…';
    }
    return '排队补英文字幕…';
  }

  /// Progress text for the Chinese fill chip (null = keep default chip label).
  String? get chineseChipProgressLabel {
    if (!needChinese || (!isActive && !isFailed)) {
      return null;
    }
    if (isFailed) {
      return '补中文失败，点重试';
    }
    final String live = (label ?? '').trim();
    if (live.isNotEmpty) {
      if (live.contains('中文') || live.contains('翻译')) {
        return _chipSizedLabel(live, side: '中文');
      }
      if (needEnglish) {
        return '等待补中文…';
      }
      return _chipSizedLabel(live, side: '中文');
    }
    if (status == SubtitleCompletionStatus.running) {
      return needEnglish ? '等待补中文…' : '正在补中文字幕…';
    }
    return '排队补中文字幕…';
  }

  static String _chipSizedLabel(String live, {required String side}) {
    final String trimmed = live.trim();
    if (trimmed.length <= 22) {
      return trimmed;
    }
    // Prefer the percent / fraction tail so list chips stay readable.
    final RegExpMatch? pct = RegExp(r'（\d{1,3}%）').firstMatch(trimmed);
    final RegExpMatch? frac = RegExp(r'\d+\s*/\s*\d+').firstMatch(trimmed);
    if (pct != null && frac != null) {
      return '补$side ${frac.group(0)}${pct.group(0)}';
    }
    if (pct != null) {
      return '补$side${pct.group(0)}';
    }
    if (frac != null) {
      return '补$side ${frac.group(0)}';
    }
    return trimmed.substring(0, 20);
  }
}

/// Course-level rollup for the library detail banner.
class SubtitleCompletionCourseUi {
  const SubtitleCompletionCourseUi({
    required this.courseId,
    required this.message,
    required this.progress,
    required this.activeCount,
    required this.failedCount,
    required this.doneCount,
    required this.totalTracked,
    this.activeEpisodeId,
  });

  final String courseId;
  final String message;
  final double progress;
  final int activeCount;
  final int failedCount;
  final int doneCount;
  final int totalTracked;
  final String? activeEpisodeId;

  bool get showBanner => activeCount > 0 || failedCount > 0;
}

class SubtitleCompletionStatusState {
  const SubtitleCompletionStatusState({
    this.byEpisodeId = const <String, SubtitleCompletionEpisodeUi>{},
    this.activeEpisodeId,
    this.activeLabel,
  });

  final Map<String, SubtitleCompletionEpisodeUi> byEpisodeId;
  final String? activeEpisodeId;
  final String? activeLabel;

  SubtitleCompletionEpisodeUi? forEpisode(String episodeId) =>
      byEpisodeId[episodeId];

  SubtitleCompletionCourseUi? forCourse({
    required String courseId,
    required Iterable<String> episodeIds,
  }) {
    final Set<String> ids = episodeIds.toSet();
    if (ids.isEmpty) {
      return null;
    }
    final List<SubtitleCompletionEpisodeUi> jobs = byEpisodeId.values
        .where((SubtitleCompletionEpisodeUi e) => ids.contains(e.episodeId))
        .toList(growable: false);
    if (jobs.isEmpty) {
      return null;
    }
    final int active = jobs.where((SubtitleCompletionEpisodeUi e) => e.isActive).length;
    final int failed = jobs.where((SubtitleCompletionEpisodeUi e) => e.isFailed).length;
    final int done = jobs
        .where((SubtitleCompletionEpisodeUi e) => e.status == SubtitleCompletionStatus.done)
        .length;
    if (active == 0 && failed == 0) {
      return null;
    }
    SubtitleCompletionEpisodeUi? running;
    SubtitleCompletionEpisodeUi? pending;
    SubtitleCompletionEpisodeUi? failedJob;
    for (final SubtitleCompletionEpisodeUi job in jobs) {
      if (running == null && job.status == SubtitleCompletionStatus.running) {
        running = job;
      }
      if (pending == null && job.status == SubtitleCompletionStatus.pending) {
        pending = job;
      }
      if (failedJob == null && job.isFailed) {
        failedJob = job;
      }
    }
    // Prefer the live worker label for the course currently being processed.
    final SubtitleCompletionEpisodeUi? focus = () {
      if (activeEpisodeId != null) {
        for (final SubtitleCompletionEpisodeUi job in jobs) {
          if (job.episodeId == activeEpisodeId && job.isActive) {
            return job;
          }
        }
      }
      return running ?? pending;
    }();
    final String liveFocus = (focus?.label ?? activeLabel ?? '').trim();
    final String focusLabel = liveFocus.isNotEmpty
        ? liveFocus
        : (focus?.displayLabel ?? '');
    final String message;
    if (running != null || (focus != null && focus.status == SubtitleCompletionStatus.running)) {
      message = active > 1
          ? '补字幕中（排队 $active 集，已完成 $done 集）：$focusLabel'
          : '补字幕中：$focusLabel';
    } else if (pending != null || (focus != null && focus.isActive)) {
      message = active > 1
          ? '排队补字幕（$active 集待处理，已完成 $done 集）：$focusLabel'
          : '排队补字幕：$focusLabel';
    } else if (failedJob != null) {
      message = failed > 1
          ? '$failed 集字幕补全失败，可点重试'
          : failedJob.displayLabel;
    } else {
      message = '字幕补全进行中…';
    }
    // Mix job completion ratio with the live episode fraction when available.
    final double jobProgress = jobs.isEmpty
        ? 0
        : (done / jobs.length).clamp(0.0, 1.0);
    final double? liveFraction = focus?.progressFraction;
    final double blended = liveFraction == null
        ? jobProgress
        : (jobProgress * 0.7 + liveFraction.clamp(0.0, 1.0) * 0.3);
    final double shown = active > 0
        ? (blended < 0.08 ? 0.08 : blended).clamp(0.08, 0.95)
        : blended.clamp(0.0, 1.0);
    return SubtitleCompletionCourseUi(
      courseId: courseId,
      message: message,
      progress: shown,
      activeCount: active,
      failedCount: failed,
      doneCount: done,
      totalTracked: jobs.length,
      activeEpisodeId: focus?.episodeId ?? running?.episodeId ?? pending?.episodeId,
    );
  }

  SubtitleCompletionStatusState copyWith({
    Map<String, SubtitleCompletionEpisodeUi>? byEpisodeId,
    String? activeEpisodeId,
    String? activeLabel,
    bool clearActive = false,
  }) {
    return SubtitleCompletionStatusState(
      byEpisodeId: byEpisodeId ?? this.byEpisodeId,
      activeEpisodeId: clearActive ? null : (activeEpisodeId ?? this.activeEpisodeId),
      activeLabel: clearActive ? null : (activeLabel ?? this.activeLabel),
    );
  }
}

class SubtitleCompletionStatusNotifier
    extends Notifier<SubtitleCompletionStatusState> {
  Timer? _poll;

  @override
  SubtitleCompletionStatusState build() {
    void onHub() => unawaited(refresh());
    SubtitleCompletionStatusHub.instance.bind(onHub);
    ref.onDispose(() {
      _poll?.cancel();
      SubtitleCompletionStatusHub.instance.unbind(onHub);
    });
    // Initial load + light poll so import/enqueue from other code paths shows up.
    Future<void>.microtask(refresh);
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(refresh());
    });
    return const SubtitleCompletionStatusState();
  }

  Future<void> refresh() async {
    final List<SubtitleCompletionJob> jobs =
        await SubtitleCompletionQueue.shared.loadJobs();
    final Map<String, SubtitleCompletionEpisodeUi> next =
        <String, SubtitleCompletionEpisodeUi>{};
    for (final SubtitleCompletionJob job in jobs) {
      final SubtitleCompletionEpisodeUi? previous =
          state.byEpisodeId[job.episodeId];
      final bool jobActive =
          job.status == SubtitleCompletionStatus.pending ||
          job.status == SubtitleCompletionStatus.running;
      // Keep live worker labels across 2s polls; only clear when job leaves
      // the active states (done / failed without retry).
      String? label;
      if (jobActive) {
        if (state.activeEpisodeId == job.episodeId &&
            (state.activeLabel ?? '').trim().isNotEmpty) {
          label = state.activeLabel;
        } else if ((previous?.label ?? '').trim().isNotEmpty) {
          label = previous!.label;
        }
      }
      next[job.episodeId] = SubtitleCompletionEpisodeUi(
        episodeId: job.episodeId,
        status: job.status,
        needEnglish: job.needEnglish,
        needChinese: job.needChinese,
        label: label,
        lastError: job.lastError,
        attempts: job.attempts,
      );
    }
    // Keep optimistic chip/banner rows that were reported before the queue
    // file finished writing (avoids the course banner disappearing on tap).
    for (final MapEntry<String, SubtitleCompletionEpisodeUi> entry
        in state.byEpisodeId.entries) {
      if (next.containsKey(entry.key)) {
        continue;
      }
      if (entry.value.isActive) {
        next[entry.key] = entry.value;
      }
    }
    state = state.copyWith(
      byEpisodeId: Map<String, SubtitleCompletionEpisodeUi>.unmodifiable(next),
    );
  }

  void reportProgress(
    String episodeId,
    String label, {
    bool? needEnglish,
    bool? needChinese,
    SubtitleCompletionStatus? status,
  }) {
    final String trimmed = label.trim();
    if (episodeId.trim().isEmpty || trimmed.isEmpty) {
      return;
    }
    final Map<String, SubtitleCompletionEpisodeUi> next =
        Map<String, SubtitleCompletionEpisodeUi>.from(state.byEpisodeId);
    final SubtitleCompletionEpisodeUi? existing = next[episodeId];
    next[episodeId] = SubtitleCompletionEpisodeUi(
      episodeId: episodeId,
      status: status ??
          (existing?.status == SubtitleCompletionStatus.done
              ? SubtitleCompletionStatus.running
              : (existing?.status ?? SubtitleCompletionStatus.running)),
      needEnglish: needEnglish ?? existing?.needEnglish ?? true,
      needChinese: needChinese ?? existing?.needChinese ?? false,
      label: trimmed,
      lastError: existing?.lastError,
      attempts: existing?.attempts ?? 0,
    );
    final bool clearActive = trimmed.contains('已补全') || trimmed.contains('失败');
    state = SubtitleCompletionStatusState(
      byEpisodeId: Map<String, SubtitleCompletionEpisodeUi>.unmodifiable(next),
      activeEpisodeId: clearActive ? null : episodeId,
      activeLabel: clearActive ? null : trimmed,
    );
    if (clearActive) {
      unawaited(refresh());
    }
  }

  Future<void> retryCourse(Iterable<String> episodeIds) async {
    final Set<String> ids = episodeIds.toSet();
    for (final String id in ids) {
      final SubtitleCompletionEpisodeUi? ui = state.byEpisodeId[id];
      if (ui == null || !ui.isFailed) {
        continue;
      }
      await SubtitleCompletionQueue.shared.requeueFailedJobs(
        onlyConfigErrors: false,
      );
      break;
    }
    // Also re-detect + enqueue from catalog via scheduler bootstrap path.
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    await refresh();
  }

  Future<void> retryEpisode({
    required String episodeId,
    required String? videoPath,
    String? zhSubtitlePath,
    String? enSubtitlePath,
    String? sourceUrl,
  }) async {
    await enqueueSubtitleCompletionForEpisode(
      episodeId: episodeId,
      videoPath: videoPath,
      zhSubtitlePath: zhSubtitlePath,
      enSubtitlePath: enSubtitlePath,
      sourceUrl: sourceUrl,
      force: true,
    );
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    await refresh();
  }
}

final NotifierProvider<
  SubtitleCompletionStatusNotifier,
  SubtitleCompletionStatusState
>
subtitleCompletionStatusProvider =
    NotifierProvider<
      SubtitleCompletionStatusNotifier,
      SubtitleCompletionStatusState
    >(SubtitleCompletionStatusNotifier.new);
