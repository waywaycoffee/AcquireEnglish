import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum SubtitleCompletionStatus { pending, running, done, failed }

class SubtitleCompletionJob {
  const SubtitleCompletionJob({
    required this.episodeId,
    required this.videoPath,
    this.zhPath,
    this.enPath,
    this.sourceKey,
    this.needEnglish = true,
    this.needChinese = false,
    /// Spoken-language side that Whisper must produce before translation.
    /// `en` | `zh`
    this.asrPrimary = 'en',
    this.status = SubtitleCompletionStatus.pending,
    this.attempts = 0,
    this.lastError,
    this.updatedAtMs,
  });

  final String episodeId;
  final String videoPath;
  final String? zhPath;
  final String? enPath;
  final String? sourceKey;
  final bool needEnglish;
  final bool needChinese;
  final String asrPrimary;
  final SubtitleCompletionStatus status;
  final int attempts;
  final String? lastError;
  final int? updatedAtMs;

  SubtitleCompletionJob copyWith({
    String? videoPath,
    String? zhPath,
    String? enPath,
    String? sourceKey,
    bool? needEnglish,
    bool? needChinese,
    String? asrPrimary,
    SubtitleCompletionStatus? status,
    int? attempts,
    String? lastError,
    int? updatedAtMs,
    bool clearError = false,
  }) {
    return SubtitleCompletionJob(
      episodeId: episodeId,
      videoPath: videoPath ?? this.videoPath,
      zhPath: zhPath ?? this.zhPath,
      enPath: enPath ?? this.enPath,
      sourceKey: sourceKey ?? this.sourceKey,
      needEnglish: needEnglish ?? this.needEnglish,
      needChinese: needChinese ?? this.needChinese,
      asrPrimary: asrPrimary ?? this.asrPrimary,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastError: clearError ? null : (lastError ?? this.lastError),
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'episodeId': episodeId,
      'videoPath': videoPath,
      'zhPath': zhPath,
      'enPath': enPath,
      'sourceKey': sourceKey,
      'needEnglish': needEnglish,
      'needChinese': needChinese,
      'asrPrimary': asrPrimary,
      'status': status.name,
      'attempts': attempts,
      'lastError': lastError,
      'updatedAtMs': updatedAtMs,
    };
  }

  static SubtitleCompletionJob? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final String episodeId = '${raw['episodeId'] ?? ''}'.trim();
    final String videoPath = '${raw['videoPath'] ?? ''}'.trim();
    if (episodeId.isEmpty || videoPath.isEmpty) {
      return null;
    }
    final String statusName = '${raw['status'] ?? 'pending'}'.trim();
    final SubtitleCompletionStatus status = SubtitleCompletionStatus.values
        .firstWhere(
          (SubtitleCompletionStatus value) => value.name == statusName,
          orElse: () => SubtitleCompletionStatus.pending,
        );
    // Legacy jobs (pre needEnglish field) always meant "fill English via ASR".
    final bool needEnglish = raw.containsKey('needEnglish')
        ? raw['needEnglish'] == true || '${raw['needEnglish']}' == 'true'
        : true;
    final bool needChinese = raw.containsKey('needChinese')
        ? raw['needChinese'] == true || '${raw['needChinese']}' == 'true'
        : false;
    final String asrPrimaryRaw =
        '${raw['asrPrimary'] ?? 'en'}'.trim().toLowerCase();
    final String asrPrimary = asrPrimaryRaw.startsWith('zh')
        ? 'zh'
        : (asrPrimaryRaw == 'auto' || asrPrimaryRaw == 'mixed'
              ? 'auto'
              : 'en');
    return SubtitleCompletionJob(
      episodeId: episodeId,
      videoPath: videoPath,
      zhPath: _nullableString(raw['zhPath']),
      enPath: _nullableString(raw['enPath']),
      sourceKey: _nullableString(raw['sourceKey']),
      needEnglish: needEnglish,
      needChinese: needChinese,
      asrPrimary: asrPrimary,
      status: status,
      attempts: int.tryParse('${raw['attempts']}') ?? 0,
      lastError: _nullableString(raw['lastError']),
      updatedAtMs: int.tryParse('${raw['updatedAtMs']}'),
    );
  }
}

String? _nullableString(Object? value) {
  final String text = '$value'.trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}

class SubtitleCompletionQueue {
  SubtitleCompletionQueue({
    Future<Directory> Function()? appSupportDirectory,
    this.maxAttempts = 3,
  }) : _appSupportDirectory =
           appSupportDirectory ?? getApplicationSupportDirectory;

  /// Process-wide queue so import/scheduler/worker share one write lock.
  /// Chinese EN→ZH often needs many soft retries under free-API rate limits.
  static final SubtitleCompletionQueue shared = SubtitleCompletionQueue(
    maxAttempts: 12,
  );

  final Future<Directory> Function() _appSupportDirectory;
  final int maxAttempts;
  Future<void> _writeChain = Future<void>.value();

  /// Serialize read-modify-write so concurrent enqueue/mark* cannot drop jobs.
  Future<T> _withLock<T>(Future<T> Function() action) {
    final Future<T> next = _writeChain.then((_) => action());
    _writeChain = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<File> _queueFile() async {
    final Directory root = await _appSupportDirectory();
    final Directory dir = Directory(
      '${root.path}${Platform.pathSeparator}subtitle_completion',
    );
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}queue.json');
  }

  Future<List<SubtitleCompletionJob>> loadJobs() async {
    final File file = await _queueFile();
    if (!file.existsSync()) {
      return <SubtitleCompletionJob>[];
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return <SubtitleCompletionJob>[];
      }
      final List<SubtitleCompletionJob> jobs = <SubtitleCompletionJob>[];
      for (final Object? item in decoded) {
        final SubtitleCompletionJob? job = SubtitleCompletionJob.fromJson(item);
        if (job != null) {
          jobs.add(job);
        }
      }
      return jobs;
    } catch (_) {
      return <SubtitleCompletionJob>[];
    }
  }

  Future<void> _saveJobs(List<SubtitleCompletionJob> jobs) async {
    final File file = await _queueFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        jobs.map((SubtitleCompletionJob job) => job.toJson()).toList(),
      ),
      flush: true,
    );
  }

  /// Enqueue or refresh a pending job. Done jobs are re-queued only when forced.
  Future<SubtitleCompletionJob> enqueue({
    required String episodeId,
    required String videoPath,
    String? zhPath,
    String? enPath,
    String? sourceKey,
    bool needEnglish = true,
    bool needChinese = false,
    String asrPrimary = 'en',
    bool force = false,
  }) {
    return _withLock(() async {
      final List<SubtitleCompletionJob> jobs = await loadJobs();
      final int index = jobs.indexWhere(
        (SubtitleCompletionJob job) => job.episodeId == episodeId,
      );
      final int now = DateTime.now().millisecondsSinceEpoch;
      final String rawPrimary = asrPrimary.trim().toLowerCase();
      final String primary = rawPrimary.startsWith('zh')
          ? 'zh'
          : (rawPrimary == 'auto' || rawPrimary == 'mixed' ? 'auto' : 'en');
      if (index >= 0) {
        final SubtitleCompletionJob existing = jobs[index];
        if (existing.status == SubtitleCompletionStatus.done && !force) {
          // Done only sticks when detect says both sides are still fine.
          // Matching prior need flags is NOT enough: the same needEnglish=true
          // can fire again after a bad en.srt reappears or ASR output is wiped.
          if (!needEnglish && !needChinese) {
            return existing;
          }
        }
        // User tapped 停止 — do not revive via catalog scan until force/重试.
        if (!force &&
            existing.status == SubtitleCompletionStatus.failed &&
            (existing.lastError ?? '').contains(userStoppedError)) {
          return existing;
        }
        if (existing.status == SubtitleCompletionStatus.running) {
          // Never demote running → pending (that restarts ASR mid-flight when
          // the user re-taps 补英文 / 生成字幕). Merge paths/flags only.
          // Callers that truly need a fresh run must cancel the scheduler
          // token first, then enqueue after the job leaves `running`.
          final SubtitleCompletionJob next = existing.copyWith(
            videoPath: videoPath,
            zhPath: zhPath,
            enPath: enPath,
            sourceKey: sourceKey,
            needEnglish: existing.needEnglish || needEnglish,
            needChinese: existing.needChinese || needChinese,
            asrPrimary: primary,
            updatedAtMs: now,
          );
          jobs[index] = next;
          await _saveJobs(jobs);
          return next;
        }
        // Only reset attempts on explicit force or a fresh re-queue of a done
        // job. Failed→pending must keep attempts or "仍不完整" loops forever.
        final bool resetAttempts =
            force || existing.status == SubtitleCompletionStatus.done;
        final SubtitleCompletionJob next = existing.copyWith(
          videoPath: videoPath,
          zhPath: zhPath,
          enPath: enPath,
          sourceKey: sourceKey,
          needEnglish: needEnglish,
          needChinese: needChinese,
          asrPrimary: primary,
          status: SubtitleCompletionStatus.pending,
          attempts: resetAttempts ? 0 : existing.attempts,
          updatedAtMs: now,
          clearError: true,
        );
        jobs[index] = next;
        await _saveJobs(jobs);
        return next;
      }
      final SubtitleCompletionJob created = SubtitleCompletionJob(
        episodeId: episodeId,
        videoPath: videoPath,
        zhPath: zhPath,
        enPath: enPath,
        sourceKey: sourceKey,
        needEnglish: needEnglish,
        needChinese: needChinese,
        asrPrimary: primary,
        status: SubtitleCompletionStatus.pending,
        updatedAtMs: now,
      );
      jobs.add(created);
      await _saveJobs(jobs);
      return created;
    });
  }

  Future<SubtitleCompletionJob?> nextRunnable() async {
    final List<SubtitleCompletionJob> jobs = await loadJobs();
    final int now = DateTime.now().millisecondsSinceEpoch;
    SubtitleCompletionJob? cooling;
    for (final SubtitleCompletionJob job in jobs) {
      if (job.status == SubtitleCompletionStatus.pending) {
        // Soft defer after free-API rate limits / cloud-wait — skip briefly so
        // we do not hot-loop one stuck episode (notification stuck at 3/4).
        final String err = (job.lastError ?? '').toLowerCase();
        final bool rateLimited =
            err.contains('稍后继续') ||
            err.contains('限流') ||
            err.contains('已保留已译');
        final bool waitingCloud =
            err.contains('等待云端') || err.contains('云端生成');
        final int updated = job.updatedAtMs ?? 0;
        final int coolMs = waitingCloud ? 180000 : 45000;
        if ((rateLimited || waitingCloud) && now - updated < coolMs) {
          cooling ??= job;
          continue;
        }
        return job;
      }
      if (job.status == SubtitleCompletionStatus.failed &&
          job.attempts < maxAttempts) {
        return job;
      }
    }
    return cooling; // only rate-limited work left — caller may wait/heartbeat
  }

  Future<void> markRunning(String episodeId) async {
    await _update(episodeId, (SubtitleCompletionJob job) {
      // User tapped 停止 — do not let an in-flight worker revive the job.
      if (_isUserStopped(job)) {
        return job;
      }
      return job.copyWith(
        status: SubtitleCompletionStatus.running,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
      );
    });
  }

  Future<void> markDone(String episodeId) async {
    await _update(episodeId, (SubtitleCompletionJob job) {
      if (_isUserStopped(job)) {
        return job;
      }
      return job.copyWith(
        status: SubtitleCompletionStatus.done,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
      );
    });
  }

  Future<void> markFailed(String episodeId, String error) async {
    await _update(episodeId, (SubtitleCompletionJob job) {
      if (_isUserStopped(job)) {
        return job;
      }
      return job.copyWith(
        status: SubtitleCompletionStatus.failed,
        attempts: job.attempts + 1,
        lastError: error,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    });
  }

  /// Drop a side that is already satisfied (e.g. official ZH softsub present).
  Future<void> clearSatisfiedNeeds(
    String episodeId, {
    bool clearEnglish = false,
    bool clearChinese = false,
  }) {
    if (!clearEnglish && !clearChinese) {
      return Future<void>.value();
    }
    return _withLock(() async {
      final List<SubtitleCompletionJob> jobs = await loadJobs();
      final int index = jobs.indexWhere(
        (SubtitleCompletionJob job) => job.episodeId == episodeId,
      );
      if (index < 0) {
        return;
      }
      final SubtitleCompletionJob job = jobs[index];
      final bool needEnglish = clearEnglish ? false : job.needEnglish;
      final bool needChinese = clearChinese ? false : job.needChinese;
      if (!needEnglish && !needChinese) {
        jobs[index] = job.copyWith(
          needEnglish: false,
          needChinese: false,
          status: SubtitleCompletionStatus.done,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          clearError: true,
        );
      } else {
        jobs[index] = job.copyWith(
          needEnglish: needEnglish,
          needChinese: needChinese,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          clearError: true,
        );
      }
      await _saveJobs(jobs);
    });
  }

  /// After a partial success: keep attempt budget, narrow remaining sides.
  Future<void> markIncompleteRetry({
    required String episodeId,
    required bool needEnglish,
    required bool needChinese,
    required String error,
    String? asrPrimary,
  }) {
    return _withLock(() async {
      final List<SubtitleCompletionJob> jobs = await loadJobs();
      final int index = jobs.indexWhere(
        (SubtitleCompletionJob job) => job.episodeId == episodeId,
      );
      if (index < 0) {
        return;
      }
      final SubtitleCompletionJob job = jobs[index];
      if (_isUserStopped(job)) {
        return;
      }
      final int attempts = job.attempts + 1;
      final bool giveUp = attempts >= maxAttempts;
      jobs[index] = job.copyWith(
        needEnglish: needEnglish,
        needChinese: needChinese,
        asrPrimary: asrPrimary ?? job.asrPrimary,
        status: giveUp
            ? SubtitleCompletionStatus.failed
            : SubtitleCompletionStatus.pending,
        attempts: attempts,
        lastError: error,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveJobs(jobs);
    });
  }

  /// Pause a job without consuming an attempt (lifecycle cancel / lock screen).
  Future<void> markDeferred(String episodeId, String reason) async {
    await _update(episodeId, (SubtitleCompletionJob job) {
      // stopAndClearQueue marks failed first; cancel handlers must not reopen.
      if (_isUserStopped(job)) {
        return job;
      }
      return job.copyWith(
        status: SubtitleCompletionStatus.pending,
        lastError: reason,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    });
  }

  /// Reset interrupted "running" jobs back to pending (app killed mid-ASR).
  Future<void> recoverInterrupted() {
    return _withLock(() async {
      final List<SubtitleCompletionJob> jobs = await loadJobs();
      bool changed = false;
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < jobs.length; i++) {
        if (jobs[i].status == SubtitleCompletionStatus.running) {
          jobs[i] = jobs[i].copyWith(
            status: SubtitleCompletionStatus.pending,
            updatedAtMs: now,
          );
          changed = true;
        }
      }
      if (changed) {
        await _saveJobs(jobs);
      }
    });
  }

  /// Re-open failed jobs so a fixed ASR config (e.g. switch to local Whisper)
  /// can drain the import backlog again.
  Future<int> requeueFailedJobs({
    bool onlyConfigErrors = true,
    bool includeUserStopped = false,
  }) {
    return _withLock(() async {
      final List<SubtitleCompletionJob> jobs = await loadJobs();
      bool changed = false;
      final int now = DateTime.now().millisecondsSinceEpoch;
      int count = 0;
      for (int i = 0; i < jobs.length; i++) {
        final SubtitleCompletionJob job = jobs[i];
        if (job.status != SubtitleCompletionStatus.failed) {
          continue;
        }
        final String error = (job.lastError ?? '').toLowerCase();
        final bool userStopped = error.contains(userStoppedError.toLowerCase());
        if (userStopped && !includeUserStopped) {
          continue;
        }
        final bool configError =
            error.contains('api key') ||
            error.contains('密钥') ||
            error.contains('未配置') ||
            error.contains('missing-asr') ||
            error.contains('百炼') ||
            error.contains('whisper');
        final bool cancelError =
            error.contains('取消') || error.contains('cancel');
        if (onlyConfigErrors && !configError && !cancelError && !userStopped) {
          continue;
        }
        jobs[i] = job.copyWith(
          status: SubtitleCompletionStatus.pending,
          attempts: 0,
          updatedAtMs: now,
          clearError: true,
        );
        changed = true;
        count += 1;
      }
      if (changed) {
        await _saveJobs(jobs);
      }
      return count;
    });
  }

  Future<bool> hasPendingWork() async {
    return (await nextRunnable()) != null;
  }

  /// Move [episodeId] to the front of the pending queue.
  Future<void> prioritizeEpisode(String episodeId) {
    final String id = episodeId.trim();
    if (id.isEmpty) {
      return Future<void>.value();
    }
    return _withLock(() async {
      final List<SubtitleCompletionJob> jobs = await loadJobs();
      final int index = jobs.indexWhere(
        (SubtitleCompletionJob job) => job.episodeId == id,
      );
      if (index <= 0) {
        return;
      }
      final SubtitleCompletionJob job = jobs.removeAt(index);
      jobs.insert(0, job);
      await _saveJobs(jobs);
    });
  }

  /// Drop all jobs for [episodeId] (used when user resets subtitles).
  Future<void> removeEpisode(String episodeId) {
    final String id = episodeId.trim();
    if (id.isEmpty) {
      return Future<void>.value();
    }
    return _withLock(() async {
      final List<SubtitleCompletionJob> jobs = await loadJobs();
      final List<SubtitleCompletionJob> next = jobs
          .where((SubtitleCompletionJob job) => job.episodeId != id)
          .toList(growable: false);
      if (next.length == jobs.length) {
        return;
      }
      await _saveJobs(next);
    });
  }

  static const String userStoppedError = '用户已停止';

  static bool _isUserStopped(SubtitleCompletionJob job) {
    return job.status == SubtitleCompletionStatus.failed &&
        (job.lastError ?? '').contains(userStoppedError);
  }

  /// Mark pending/running jobs as failed so ASR/translation stops and will not
  /// auto-resume (catalog scan + enqueue respect [userStoppedError] until force).
  ///
  /// When [episodeIds] is null, stops the whole active queue.
  Future<int> clearActiveWork({Iterable<String>? episodeIds}) {
    final Set<String>? scope = episodeIds == null
        ? null
        : episodeIds
            .map((String id) => id.trim())
            .where((String id) => id.isNotEmpty)
            .toSet();
    return _withLock(() async {
      final List<SubtitleCompletionJob> jobs = await loadJobs();
      bool changed = false;
      int stopped = 0;
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < jobs.length; i++) {
        final SubtitleCompletionJob job = jobs[i];
        final bool inScope = scope == null || scope.contains(job.episodeId);
        final bool active =
            job.status == SubtitleCompletionStatus.pending ||
            job.status == SubtitleCompletionStatus.running;
        if (!inScope || !active) {
          continue;
        }
        jobs[i] = job.copyWith(
          status: SubtitleCompletionStatus.failed,
          attempts: maxAttempts,
          lastError: userStoppedError,
          updatedAtMs: now,
        );
        changed = true;
        stopped += 1;
      }
      if (changed) {
        await _saveJobs(jobs);
      }
      return stopped;
    });
  }

  Future<void> _update(
    String episodeId,
    SubtitleCompletionJob Function(SubtitleCompletionJob job) transform,
  ) {
    return _withLock(() async {
      final List<SubtitleCompletionJob> jobs = await loadJobs();
      final int index = jobs.indexWhere(
        (SubtitleCompletionJob job) => job.episodeId == episodeId,
      );
      if (index < 0) {
        return;
      }
      jobs[index] = transform(jobs[index]);
      await _saveJobs(jobs);
    });
  }
}
