import 'dart:convert';

import 'package:hive_ce/hive.dart';

const String kIdleJobsEnabledKey = 'idle_jobs_enabled_v1';
const String kIdleJobQueueKey = 'idle_job_queue_v1';
const String kIdleJobsWakeKey = 'idle_jobs_wake_v1';

enum IdleJobKind { subtitleDrain, modelPrefetch, vocabEnrich, cloudSync }

extension IdleJobKindX on IdleJobKind {
  String get label => switch (this) {
    IdleJobKind.subtitleDrain => '字幕补全',
    IdleJobKind.modelPrefetch => '模型预取',
    IdleJobKind.vocabEnrich => '生词 AI 补全',
    IdleJobKind.cloudSync => '云同步',
  };
}

enum IdleJobStatus { pending, running, done, failed }

class IdleJob {
  const IdleJob({
    required this.kind,
    required this.key,
    required this.status,
    required this.createdAtMs,
    this.retries = 0,
    this.lastError,
  });

  factory IdleJob.fromJson(Map<String, dynamic> json) => IdleJob(
    kind: IdleJobKind.values.firstWhere(
      (IdleJobKind k) => k.name == json['kind'],
      orElse: () => IdleJobKind.vocabEnrich,
    ),
    key: json['key'] as String? ?? '',
    status: IdleJobStatus.values.firstWhere(
      (IdleJobStatus s) => s.name == json['status'],
      orElse: () => IdleJobStatus.pending,
    ),
    createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    retries: (json['retries'] as num?)?.toInt() ?? 0,
    lastError: json['lastError'] as String?,
  );

  final IdleJobKind kind;
  final String key;
  final IdleJobStatus status;
  final int createdAtMs;
  final int retries;
  final String? lastError;

  String get id => '${kind.name}:$key';

  IdleJob copyWith({
    IdleJobStatus? status,
    int? retries,
    String? lastError,
  }) => IdleJob(
    kind: kind,
    key: key,
    status: status ?? this.status,
    createdAtMs: createdAtMs,
    retries: retries ?? this.retries,
    lastError: lastError,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind.name,
    'key': key,
    'status': status.name,
    'createdAtMs': createdAtMs,
    'retries': retries,
    'lastError': lastError,
  };
}

bool idleJobsEnabled() {
  if (!Hive.isBoxOpen('prefs')) return true;
  final String? raw = Hive.box<String>('prefs').get(kIdleJobsEnabledKey);
  if (raw == null || raw.isEmpty) return true;
  return raw != '0' && raw.toLowerCase() != 'false';
}

Future<void> setIdleJobsEnabled(bool enabled) async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').put(kIdleJobsEnabledKey, enabled ? '1' : '0');
}

class IdleJobQueue {
  IdleJobQueue._();
  static final IdleJobQueue shared = IdleJobQueue._();

  List<IdleJob> load() {
    if (!Hive.isBoxOpen('prefs')) return const <IdleJob>[];
    final String? raw = Hive.box<String>('prefs').get(kIdleJobQueueKey);
    if (raw == null || raw.isEmpty) return const <IdleJob>[];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(IdleJob.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <IdleJob>[];
    }
  }

  Future<void> _save(List<IdleJob> jobs) async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      kIdleJobQueueKey,
      jsonEncode(jobs.map((IdleJob j) => j.toJson()).toList()),
    );
  }

  Future<void> enqueue({
    required IdleJobKind kind,
    required String key,
  }) async {
    final List<IdleJob> jobs = load().toList(growable: true);
    final String id = '${kind.name}:$key';
    final int existing = jobs.indexWhere((IdleJob j) => j.id == id);
    if (existing >= 0) {
      final IdleJob prev = jobs[existing];
      if (prev.status == IdleJobStatus.pending ||
          prev.status == IdleJobStatus.running) {
        return;
      }
      jobs[existing] = IdleJob(
        kind: kind,
        key: key,
        status: IdleJobStatus.pending,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      jobs.add(
        IdleJob(
          kind: kind,
          key: key,
          status: IdleJobStatus.pending,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    await _save(jobs);
  }

  Future<void> markDone(String id) async {
    final List<IdleJob> jobs = load().toList(growable: true);
    final int i = jobs.indexWhere((IdleJob j) => j.id == id);
    if (i < 0) return;
    jobs[i] = jobs[i].copyWith(status: IdleJobStatus.done);
    await _save(jobs);
  }

  Future<void> markFailed(String id, String error) async {
    final List<IdleJob> jobs = load().toList(growable: true);
    final int i = jobs.indexWhere((IdleJob j) => j.id == id);
    if (i < 0) return;
    final IdleJob prev = jobs[i];
    jobs[i] = prev.copyWith(
      status: IdleJobStatus.failed,
      retries: prev.retries + 1,
      lastError: error,
    );
    await _save(jobs);
  }

  Future<void> removeKeysStartingWith(String prefix) async {
    final List<IdleJob> jobs = load()
        .where((IdleJob j) => !j.key.startsWith(prefix))
        .toList(growable: false);
    await _save(jobs);
  }

  List<IdleJob> get pending =>
      load().where((IdleJob j) => j.status == IdleJobStatus.pending).toList();
}
