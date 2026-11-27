import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../import_course/data/bilibili_episode_prepare.dart';
import '../sync/data/acquire_api_client.dart';
import 'cloud_subtitle_job_tracker.dart';
import 'shared_bilibili_subtitle_sync.dart';
import 'shared_subtitle_api.dart';
import 'subtitle_completion_enqueue.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_runtime.dart';
import 'subtitle_completion_scheduler.dart';
import 'subtitle_completion_status_hub.dart';
import 'subtitle_fill_label.dart';

export 'subtitle_fill_label.dart';

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
    final String live = (label ?? '').trim();
    if (isSubtitleSharedCacheReadyLabel(live)) {
      return 1.0;
    }
    if (!isActive) {
      return null;
    }
    // Lookup / partial shared-cache labels are not Whisper % — keep a modest bar.
    if (live.contains('校验字幕缓存')) {
      return live.contains('正在补齐') ? 0.55 : 0.18;
    }
    return progressFractionFromSubtitleLabel(live);
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

/// Compact progress: `已完成(当前任务%)/总任务数` e.g. `3(7%)/16`.
class SubtitleFillProgressSummary {
  const SubtitleFillProgressSummary({
    required this.doneCount,
    required this.totalCount,
    required this.currentPercent,
    required this.overallProgress,
    required this.compactLabel,
    required this.detailLabel,
  });

  final int doneCount;
  final int totalCount;
  final int currentPercent;
  final double overallProgress;
  final String compactLabel;
  final String detailLabel;
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

  bool get showBanner =>
      activeCount > 0 ||
      failedCount > 0 ||
      isSubtitleSharedCacheReadyLabel(message);

  String get compactProgressLabel {
    final int pct = ((progress.clamp(0.0, 1.0)) * 100).round().clamp(0, 99);
    // Prefer parsing live message current-task % when present.
    final RegExpMatch? livePct =
        RegExp(r'（(\d{1,3})%）').firstMatch(message) ??
        RegExp(r'(\d{1,3})%').firstMatch(message);
    final int current = livePct == null
        ? pct
        : (int.tryParse(livePct.group(1) ?? '') ?? pct).clamp(0, 99);
    return formatSubtitleFillCompactLabel(
      doneCount: doneCount,
      totalCount: totalTracked,
      currentPercent: current,
    );
  }
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

  /// Global fill progress for FAB / system overlay.
  SubtitleFillProgressSummary? get activeFillProgress {
    final List<SubtitleCompletionEpisodeUi> jobs = byEpisodeId.values.toList(
      growable: false,
    );
    if (jobs.isEmpty) {
      return null;
    }
    final List<SubtitleCompletionEpisodeUi> active = jobs
        .where((SubtitleCompletionEpisodeUi e) => e.isActive)
        .toList(growable: false);
    if (active.isEmpty) {
      return null;
    }
    final int done = jobs
        .where(
          (SubtitleCompletionEpisodeUi e) =>
              e.status == SubtitleCompletionStatus.done,
        )
        .length;
    final int total = jobs.length;
    SubtitleCompletionEpisodeUi? focus;
    for (final SubtitleCompletionEpisodeUi row in active) {
      if (row.status == SubtitleCompletionStatus.running) {
        focus = row;
        break;
      }
    }
    focus ??= active.first;
    if (activeEpisodeId != null) {
      for (final SubtitleCompletionEpisodeUi row in active) {
        if (row.episodeId == activeEpisodeId) {
          focus = row;
          break;
        }
      }
    }
    final SubtitleCompletionEpisodeUi focused = focus!;
    final double currentFrac = (focused.progressFraction ?? 0.08).clamp(
      0.0,
      0.99,
    );
    final int currentPercent = (currentFrac * 100).round().clamp(0, 99);
    final String live = (focused.label ?? activeLabel ?? '').trim();
    return SubtitleFillProgressSummary(
      doneCount: done,
      totalCount: total,
      currentPercent: currentPercent,
      overallProgress: subtitleFillOverallProgress(
        doneCount: done,
        totalCount: total,
        currentFraction: currentFrac,
      ),
      compactLabel: formatSubtitleFillCompactLabel(
        doneCount: done,
        totalCount: total,
        currentPercent: currentPercent,
      ),
      detailLabel: live.isNotEmpty ? live : focused.displayLabel,
    );
  }

  SubtitleCompletionCourseUi? forCourse({
    required String courseId,
    required Iterable<String> episodeIds,
    Map<String, String> episodeNumbers = const <String, String>{},
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
    final int active = jobs
        .where((SubtitleCompletionEpisodeUi e) => e.isActive)
        .length;
    final int failed = jobs
        .where((SubtitleCompletionEpisodeUi e) => e.isFailed)
        .length;
    final int done = jobs
        .where(
          (SubtitleCompletionEpisodeUi e) =>
              e.status == SubtitleCompletionStatus.done,
        )
        .length;
    SubtitleCompletionEpisodeUi? sharedReady;
    for (final SubtitleCompletionEpisodeUi job in jobs) {
      if (isSubtitleSharedCacheReadyLabel(job.label)) {
        sharedReady = job;
        break;
      }
    }
    if (active == 0 && failed == 0 && sharedReady == null) {
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
      return running ?? pending ?? sharedReady;
    }();
    final String liveFocus = (focus?.label ??
        (focus?.episodeId == activeEpisodeId ? activeLabel : null) ?? '').trim();
    final String focusLabel = liveFocus.isNotEmpty
        ? liveFocus
        : (focus?.displayLabel ?? '');
    final String? number = episodeNumbers[focus?.episodeId];
    final String episodePrefix = number == null || number.isEmpty
        ? ''
        : '第 $number 集 · ';
    final String message;
    if (focusLabel == kSubtitleSharedCacheLookupLabel) {
      message = '${episodePrefix}正在查公共字幕库…';
    } else if (running != null ||
        (focus != null && focus.status == SubtitleCompletionStatus.running)) {
      message = active > 1
          ? '补字幕中（$active 集待处理，已完成 $done 集）：$episodePrefix$focusLabel'
          : '补字幕中：$episodePrefix$focusLabel';
    } else if (pending != null || (focus != null && focus.isActive)) {
      message = active > 1
          ? '排队补字幕（$active 集待处理，已完成 $done 集）：$episodePrefix$focusLabel'
          : '排队补字幕：$episodePrefix$focusLabel';
    } else if (failedJob != null) {
      message = failed > 1 ? '$failed 集字幕补全失败，可点重试' : failedJob.displayLabel;
    } else if (sharedReady != null) {
      message = sharedReady.displayLabel;
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
      activeEpisodeId:
          focus?.episodeId ?? running?.episodeId ?? pending?.episodeId,
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
      activeEpisodeId: clearActive
          ? null
          : (activeEpisodeId ?? this.activeEpisodeId),
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
    SubtitleCompletionStatusHub.instance.bindProgress(
      (
        String episodeId,
        String label, {
        SubtitleCompletionStatus? status,
        bool? needEnglish,
        bool? needChinese,
      }) {
        reportProgress(
          episodeId,
          label,
          status: status,
          needEnglish: needEnglish,
          needChinese: needChinese,
        );
      },
    );
    ref.onDispose(() {
      _poll?.cancel();
      SubtitleCompletionStatusHub.instance.unbind(onHub);
      SubtitleCompletionStatusHub.instance.bindProgress(null);
    });
    // Initial load + light poll so import/enqueue from other code paths shows up.
    Future<void>.microtask(refresh);
    _poll?.cancel();
    void startPolling() {
      _poll?.cancel();
      if (!ref.mounted) return;
      _poll = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!ref.mounted) {
          _poll?.cancel();
          return;
        }
        unawaited(refresh());
      });
    }

    ref.onCancel(() => _poll?.cancel());
    ref.onResume(startPolling);
    startPolling();
    return const SubtitleCompletionStatusState();
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    try {
      await _pollTrackedCloudJobs();
      if (!ref.mounted) return;
      final List<SubtitleCompletionJob> jobs = await SubtitleCompletionQueue
          .shared
          .loadJobs();
      if (!ref.mounted) return;
      await _applyRefreshJobs(jobs);
    } catch (_) {
      // AutoDispose + Timer can finish after the provider is gone.
    }
  }

  Future<void> _applyRefreshJobs(List<SubtitleCompletionJob> jobs) async {
    if (!ref.mounted) return;
    final Map<String, SubtitleCompletionEpisodeUi> next =
        <String, SubtitleCompletionEpisodeUi>{};
    for (final SubtitleCompletionJob job in jobs) {
      final SubtitleCompletionEpisodeUi? previous =
          state.byEpisodeId[job.episodeId];
      final CloudSubtitleJobTrack? cloud =
          CloudSubtitleJobTracker.instance.forEpisode(job.episodeId);
      final bool jobActive =
          job.status == SubtitleCompletionStatus.pending ||
          job.status == SubtitleCompletionStatus.running;
      // Keep live worker labels across 2s polls; only clear when job leaves
      // the active states (done / failed without retry).
      String? label;
      if (jobActive || cloud != null) {
        if (state.activeEpisodeId == job.episodeId &&
            (state.activeLabel ?? '').trim().isNotEmpty) {
          label = state.activeLabel;
        } else if ((previous?.label ?? '').trim().isNotEmpty) {
          label = previous!.label;
        }
      }
      // Chinese-only local queue rows must not wipe cloud EN needEnglish.
      next[job.episodeId] = SubtitleCompletionEpisodeUi(
        episodeId: job.episodeId,
        status: jobActive
            ? job.status
            : (cloud != null
                  ? SubtitleCompletionStatus.running
                  : job.status),
        needEnglish: job.needEnglish ||
            (cloud?.needEnglish ?? false) ||
            ((previous?.needEnglish ?? false) && cloud != null),
        needChinese: job.needChinese || (cloud?.needChinese ?? false),
        label: label,
        lastError: job.lastError,
        attempts: job.attempts,
      );
    }
    // Keep optimistic chip/banner rows that were reported before the queue
    // file finished writing (avoids the course banner disappearing on tap).
    // Also keep shared-cache "秒开" done rows so honest UX is visible briefly.
    for (final MapEntry<String, SubtitleCompletionEpisodeUi> entry
        in state.byEpisodeId.entries) {
      if (next.containsKey(entry.key)) {
        continue;
      }
      if (entry.value.isActive ||
          isSubtitleSharedCacheReadyLabel(entry.value.label)) {
        next[entry.key] = entry.value;
      }
    }
    // Cloud-only EN jobs never enter the local Whisper queue — keep tracker
    // rows visible so the player does not fall back to「准备音频」placeholder.
    for (final CloudSubtitleJobTrack track
        in CloudSubtitleJobTracker.instance.activeTracks) {
      final SubtitleCompletionEpisodeUi? existing = next[track.episodeId];
      if (existing == null) {
        next[track.episodeId] = SubtitleCompletionEpisodeUi(
          episodeId: track.episodeId,
          status: SubtitleCompletionStatus.running,
          needEnglish: track.needEnglish,
          needChinese: track.needChinese,
          label: kSubtitleCloudGenerationQueuedLabel,
        );
        continue;
      }
      if ((track.needEnglish && !existing.needEnglish) ||
          (track.needChinese && !existing.needChinese) ||
          ((existing.label ?? '').trim().isEmpty)) {
        next[track.episodeId] = SubtitleCompletionEpisodeUi(
          episodeId: existing.episodeId,
          status: existing.isActive
              ? existing.status
              : SubtitleCompletionStatus.running,
          needEnglish: existing.needEnglish || track.needEnglish,
          needChinese: existing.needChinese || track.needChinese,
          label: (existing.label ?? '').trim().isNotEmpty
              ? existing.label
              : kSubtitleCloudGenerationQueuedLabel,
          lastError: existing.lastError,
          attempts: existing.attempts,
        );
      }
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      byEpisodeId: Map<String, SubtitleCompletionEpisodeUi>.unmodifiable(next),
    );
  }

  /// Refresh cloud-only EN jobs that never enter the local Whisper queue.
  Future<void> _pollTrackedCloudJobs() async {
    if (!ref.mounted) return;
    final List<CloudSubtitleJobTrack> tracks =
        CloudSubtitleJobTracker.instance.activeTracks;
    if (tracks.isEmpty) {
      return;
    }
    final AcquireApiClient? api = resolveSharedBilibiliSubtitleApi();
    if (api == null) {
      return;
    }
    for (final CloudSubtitleJobTrack track in tracks) {
      try {
        SharedSubtitleGpuJob? job;
        if (track.jobId.trim().isNotEmpty) {
          job = await api.getSharedSubtitleJob(track.jobId);
        }
        if (CloudSubtitleJobTracker.instance.forEpisode(track.episodeId) != track) {
          continue;
        }
        job ??= await api.enqueueSharedSubtitleJob(
          bvid: track.bvid,
          page: track.page,
        );
        if (job == null ||
            CloudSubtitleJobTracker.instance.forEpisode(track.episodeId) != track) {
          continue;
        }
        final String label = labelForGpuSubtitleJobState(
          job.state,
          progressMessage: job.progressMessage,
          progressPct: job.progressPct,
        );
        final String state = job.state.trim().toLowerCase();
        if (state == 'failed') {
          reportProgress(
            track.episodeId,
            label,
            status: SubtitleCompletionStatus.failed,
            needEnglish: track.needEnglish,
            needChinese: track.needChinese,
          );
          CloudSubtitleJobTracker.instance.clear(track.episodeId);
          continue;
        }
        if (state == 'completed') {
          final ({String? enPath, String? zhPath})? shared =
              await tryApplySharedBilibiliSubtitles(
            api: api,
            ids: BilibiliSharedSubtitleIds(
              bvid: track.bvid,
              page: track.page,
            ),
          );
          if (shared != null &&
              (isUsableSubtitlePath(shared.enPath) ||
                  isUsableSubtitlePath(shared.zhPath))) {
            SubtitleCompletionStatusHub.instance.reportSharedApplied(
              episodeId: track.episodeId,
              enPath: shared.enPath,
              zhPath: shared.zhPath,
            );
            reportProgress(
              track.episodeId,
              kSubtitleSharedCacheReadyDetailLabel,
              status: SubtitleCompletionStatus.done,
              needEnglish: false,
              needChinese: false,
            );
            CloudSubtitleJobTracker.instance.clear(track.episodeId);
            SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
            continue;
          }
        }
        reportProgress(
          track.episodeId,
          label,
          status: SubtitleCompletionStatus.running,
          needEnglish: track.needEnglish,
          needChinese: track.needChinese,
        );
      } catch (_) {}
    }
  }

  void reportProgress(
    String episodeId,
    String label, {
    bool? needEnglish,
    bool? needChinese,
    SubtitleCompletionStatus? status,
  }) {
    if (!ref.mounted) {
      return;
    }
    final String trimmed = label.trim();
    if (episodeId.trim().isEmpty || trimmed.isEmpty) {
      return;
    }
    final Map<String, SubtitleCompletionEpisodeUi> next =
        Map<String, SubtitleCompletionEpisodeUi>.from(state.byEpisodeId);
    final SubtitleCompletionEpisodeUi? existing = next[episodeId];
    next[episodeId] = SubtitleCompletionEpisodeUi(
      episodeId: episodeId,
      status:
          status ??
          (existing?.status == SubtitleCompletionStatus.done
              ? SubtitleCompletionStatus.running
              : (existing?.status ?? SubtitleCompletionStatus.running)),
      needEnglish: needEnglish ?? existing?.needEnglish ?? true,
      needChinese: needChinese ?? existing?.needChinese ?? false,
      label: trimmed,
      lastError: existing?.lastError,
      attempts: existing?.attempts ?? 0,
    );
    final bool clearActive = isSubtitleFillTerminalLabel(trimmed);
    if (!ref.mounted) {
      return;
    }
    state = SubtitleCompletionStatusState(
      byEpisodeId: Map<String, SubtitleCompletionEpisodeUi>.unmodifiable(next),
      activeEpisodeId: clearActive ? null : episodeId,
      activeLabel: clearActive ? null : trimmed,
    );
    final SubtitleFillProgressSummary? summary = state.activeFillProgress;
    if (summary != null) {
      unawaited(
        SubtitleCompletionRuntime.instance.updateProgress(
          label: summary.compactLabel,
          progress: summary.overallProgress,
        ),
      );
    }
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
        includeUserStopped: true,
      );
      break;
    }
    // Also re-detect + enqueue from catalog via scheduler bootstrap path.
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    await refresh();
  }

  /// Stop in-flight ASR/translation and clear pending jobs (optionally scoped).
  Future<int> stopAll({Iterable<String>? episodeIds}) async {
    final int removed = await SubtitleCompletionScheduler.instance
        .stopAndClearQueue(episodeIds: episodeIds);
    if (!ref.mounted) {
      return removed;
    }
    state = state.copyWith(clearActive: true);
    await refresh();
    return removed;
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
    >(SubtitleCompletionStatusNotifier.new, isAutoDispose: true);
