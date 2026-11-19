import 'package:common_learn_english/features/player/data/dub_session_store.dart';
import 'package:common_learn_english/features/player/domain/shadow_episode_stats.dart';
import 'package:flutter_test/flutter_test.dart';

DubTake _take({
  required int index,
  int? score,
}) {
  return DubTake(
    episodeId: 'ep1',
    lineId: 'line-$index',
    startMs: index * 1000,
    endMs: index * 1000 + 800,
    english: 'Hello $index',
    userWavPath: '/tmp/fake-$index.wav',
    createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
    scorePercent: score,
  );
}

void main() {
  test('counts every take as a pass and aggregates scored stats', () {
    final ShadowEpisodeStats stats = ShadowEpisodeStats.fromTakes(<DubTake>[
      _take(index: 0, score: 60),
      _take(index: 1, score: 80),
      _take(index: 2),
      _take(index: 3, score: 40),
    ]);

    expect(stats.passCount, 4);
    expect(stats.remaining, ShadowEpisodeStats.goalPasses - 4);
    expect(stats.minScore, 40);
    expect(stats.maxScore, 80);
    expect(stats.avgScore, closeTo(60, 0.01));
    expect(stats.scoresChronological, <int>[60, 80, 40]);
  });

  test('goalReached when passCount hits 100', () {
    final List<DubTake> takes = <DubTake>[
      for (int i = 0; i < 100; i++) _take(index: i, score: 70),
    ];
    final ShadowEpisodeStats stats = ShadowEpisodeStats.fromTakes(takes);
    expect(stats.goalReached, isTrue);
    expect(stats.remaining, 0);
    expect(stats.progress, 1);
  });
}
