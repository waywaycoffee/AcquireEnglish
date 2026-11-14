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
    return SubtitleCompletionJob(
      episodeId: episodeId,
      videoPath: videoPath,
      zhPath: _nullableString(raw['zhPath']),
      enPath: _nullableString(raw['enPath']),
      sourceKey: _nullableString(raw['sourceKey']),
      needEnglish: needEnglish,
      needChinese: needChinese,
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

  final Future<Directory> Function() _appSupportDirectory;
  final int maxAttempts;

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
    bool force = false,
  }) async {
    final List<SubtitleCompletionJob> jobs = await loadJobs();
    final int index = jobs.indexWhere(
      (SubtitleCompletionJob job) => job.episodeId == episodeId,
    );
    final int now = DateTime.now().millisecondsSinceEpoch;
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
      if (existing.status == SubtitleCompletionStatus.running && !force) {
        // Must persist path/flag refreshes — a bare return left disk stale and
        // dropped newly discovered missing sides until the next cold start.
        final SubtitleCompletionJob next = existing.copyWith(
          videoPath: videoPath,
          zhPath: zhPath,
          enPath: enPath,
          sourceKey: sourceKey,
          needEnglish: existing.needEnglish || needEnglish,
          needChinese: existing.needChinese || needChinese,
          updatedAtMs: now,
        );
        jobs[index] = next;
        await _saveJobs(jobs);
        return next;
      }
      final bool resetAttempts =
          force ||
          existing.status == SubtitleCompletionStatus.failed ||
          existing.status == SubtitleCompletionStatus.done;
      final SubtitleCompletionJob next = existing.copyWith(
        videoPath: videoPath,
        zhPath: zhPath,
        enPath: enPath,
        sourceKey: sourceKey,
        needEnglish: needEnglish,
        needChinese: needChinese,
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
      status: SubtitleCompletionStatus.pending,
      updatedAtMs: now,
    );
    jobs.add(created);
    await _saveJobs(jobs);
    return created;
  }

  Future<SubtitleCompletionJob?> nextRunnable() async {
    final List<SubtitleCompletionJob> jobs = await loadJobs();
    for (final SubtitleCompletionJob job in jobs) {
      if (job.status == SubtitleCompletionStatus.pending) {
        return job;
      }
      if (job.status == SubtitleCompletionStatus.failed &&
          job.attempts < maxAttempts) {
        return job;
      }
    }
    return null;
  }

  Future<void> markRunning(String episodeId) async {
    await _update(
      episodeId,
      (SubtitleCompletionJob job) => job.copyWith(
        status: SubtitleCompletionStatus.running,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
      ),
    );
  }

  Future<void> markDone(String episodeId) async {
    await _update(
      episodeId,
      (SubtitleCompletionJob job) => job.copyWith(
        status: SubtitleCompletionStatus.done,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
      ),
    );
  }

  Future<void> markFailed(String episodeId, String error) async {
    await _update(
      episodeId,
      (SubtitleCompletionJob job) => job.copyWith(
        status: SubtitleCompletionStatus.failed,
        attempts: job.attempts + 1,
        lastError: error,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Pause a job without consuming an attempt (lifecycle cancel / lock screen).
  Future<void> markDeferred(String episodeId, String reason) async {
    await _update(
      episodeId,
      (SubtitleCompletionJob job) => job.copyWith(
        status: SubtitleCompletionStatus.pending,
        lastError: reason,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Reset interrupted "running" jobs back to pending (app killed mid-ASR).
  Future<void> recoverInterrupted() async {
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
  }

  /// Re-open failed jobs so a fixed ASR config (e.g. switch to local Whisper)
  /// can drain the import backlog again.
  Future<int> requeueFailedJobs({bool onlyConfigErrors = true}) async {
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
      final bool configError =
          error.contains('api key') ||
          error.contains('密钥') ||
          error.contains('未配置') ||
          error.contains('missing-asr') ||
          error.contains('百炼') ||
          error.contains('whisper');
      final bool cancelError =
          error.contains('取消') || error.contains('cancel');
      if (onlyConfigErrors && !configError && !cancelError) {
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
  }

  Future<bool> hasPendingWork() async {
    return (await nextRunnable()) != null;
  }

  Future<void> _update(
    String episodeId,
    SubtitleCompletionJob Function(SubtitleCompletionJob job) transform,
  ) async {
    final List<SubtitleCompletionJob> jobs = await loadJobs();
    final int index = jobs.indexWhere(
      (SubtitleCompletionJob job) => job.episodeId == episodeId,
    );
    if (index < 0) {
      return;
    }
    jobs[index] = transform(jobs[index]);
    await _saveJobs(jobs);
  }
}
