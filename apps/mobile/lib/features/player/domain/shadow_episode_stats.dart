import '../data/dub_session_store.dart';

/// 「100 遍学习法」：按集累计每一次跟读录音为一遍。
class ShadowEpisodeStats {
  const ShadowEpisodeStats({
    required this.passCount,
    required this.scoresChronological,
  });

  static const int goalPasses = 100;

  factory ShadowEpisodeStats.fromTakes(List<DubTake> history) {
    final List<DubTake> ordered = <DubTake>[...history]
      ..sort((DubTake a, DubTake b) => a.createdAt.compareTo(b.createdAt));
    final List<int> scores = <int>[
      for (final DubTake take in ordered)
        if (take.scorePercent != null) take.scorePercent!.clamp(0, 100),
    ];
    return ShadowEpisodeStats(
      passCount: ordered.length,
      scoresChronological: scores,
    );
  }

  final int passCount;
  final List<int> scoresChronological;

  int get remaining =>
      (goalPasses - passCount).clamp(0, goalPasses);

  double get progress =>
      (passCount / goalPasses).clamp(0.0, 1.0);

  bool get goalReached => passCount >= goalPasses;

  int? get minScore {
    if (scoresChronological.isEmpty) return null;
    return scoresChronological.reduce(
      (int a, int b) => a < b ? a : b,
    );
  }

  int? get maxScore {
    if (scoresChronological.isEmpty) return null;
    return scoresChronological.reduce(
      (int a, int b) => a > b ? a : b,
    );
  }

  double? get avgScore {
    if (scoresChronological.isEmpty) return null;
    final int sum = scoresChronological.fold<int>(
      0,
      (int total, int score) => total + score,
    );
    return sum / scoresChronological.length;
  }

  /// Chart shows at most the latest [limit] scored passes (keeps UI readable).
  List<({int passIndex, int score})> chartPoints({int limit = 40}) {
    if (scoresChronological.isEmpty) {
      return const <({int passIndex, int score})>[];
    }
    final int start = scoresChronological.length > limit
        ? scoresChronological.length - limit
        : 0;
    return <({int passIndex, int score})>[
      for (int i = start; i < scoresChronological.length; i++)
        (passIndex: i + 1, score: scoresChronological[i]),
    ];
  }
}
