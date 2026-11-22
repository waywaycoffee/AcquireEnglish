/// Per-episode study stage for video / drama modules (four progress dots).
enum EpisodeStudyStage {
  notStarted,
  firstStudy,
  srsReview,
  mastered,
}

extension EpisodeStudyStageX on EpisodeStudyStage {
  String get storageKey => name;

  static EpisodeStudyStage fromStorage(String? raw) {
    for (final EpisodeStudyStage s in EpisodeStudyStage.values) {
      if (s.name == raw) return s;
    }
    return EpisodeStudyStage.notStarted;
  }

  /// Dot index 0..3 matching competitor UI.
  int get dotIndex => index;
}

class EpisodeStudyProgress {
  const EpisodeStudyProgress({
    required this.episodeId,
    this.watched = false,
    this.intensiveCoverage = 0,
    this.outputPassed = false,
    this.dueClipCount = 0,
    this.stage = EpisodeStudyStage.notStarted,
    this.updatedAtMs = 0,
  });

  final String episodeId;
  final bool watched;

  /// 0–1 fraction of sentences touched in intensive study.
  final double intensiveCoverage;
  final bool outputPassed;
  final int dueClipCount;
  final EpisodeStudyStage stage;
  final int updatedAtMs;

  EpisodeStudyProgress copyWith({
    bool? watched,
    double? intensiveCoverage,
    bool? outputPassed,
    int? dueClipCount,
    EpisodeStudyStage? stage,
    int? updatedAtMs,
  }) {
    return EpisodeStudyProgress(
      episodeId: episodeId,
      watched: watched ?? this.watched,
      intensiveCoverage: intensiveCoverage ?? this.intensiveCoverage,
      outputPassed: outputPassed ?? this.outputPassed,
      dueClipCount: dueClipCount ?? this.dueClipCount,
      stage: stage ?? this.stage,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'episodeId': episodeId,
        'watched': watched,
        'intensiveCoverage': intensiveCoverage,
        'outputPassed': outputPassed,
        'dueClipCount': dueClipCount,
        'stage': stage.storageKey,
        'updatedAtMs': updatedAtMs,
      };

  factory EpisodeStudyProgress.fromJson(Map<String, dynamic> json) {
    return EpisodeStudyProgress(
      episodeId: (json['episodeId'] as String? ?? '').trim(),
      watched: json['watched'] == true,
      intensiveCoverage: (json['intensiveCoverage'] as num?)?.toDouble() ?? 0,
      outputPassed: json['outputPassed'] == true,
      dueClipCount: (json['dueClipCount'] as num?)?.toInt() ?? 0,
      stage: EpisodeStudyStageX.fromStorage(json['stage'] as String?),
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// Recompute stage from flags (drama may gate harder than video).
  EpisodeStudyProgress recompute({bool requireOutput = false}) {
    EpisodeStudyStage next = EpisodeStudyStage.notStarted;
    if (watched || intensiveCoverage > 0.05 || outputPassed) {
      next = EpisodeStudyStage.firstStudy;
    }
    if (dueClipCount > 0) {
      next = EpisodeStudyStage.srsReview;
    }
    final bool intensiveOk = intensiveCoverage >= 0.6;
    final bool outputOk = !requireOutput || outputPassed;
    if (watched && intensiveOk && outputOk && dueClipCount == 0) {
      next = EpisodeStudyStage.mastered;
    }
    return copyWith(
      stage: next,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
