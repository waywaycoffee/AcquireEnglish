import 'learner_skill_profile.dart';

enum LearnModule { vocab, video, reading, oral }

class LearnCandidate {
  const LearnCandidate({
    required this.id,
    required this.title,
    required this.route,
    required this.module,
    required this.contentBand,
    this.pursuit = false,
    this.interestMatch = false,
    this.notInterested = false,
    this.oralLineUsedRecently = false,
  });

  final String id;
  final String title;
  final String route;
  final LearnModule module;
  final String contentBand;
  final bool pursuit;
  final bool interestMatch;

  /// 「不感兴趣」: hide for the demote window. A one-off swap does not set this.
  final bool notInterested;
  final bool oralLineUsedRecently;
}

class ScoredLearnCandidate {
  const ScoredLearnCandidate({
    required this.candidate,
    required this.score,
    required this.distance,
    required this.eligibleDefault,
    required this.slightlyHard,
    required this.reason,
  });

  final LearnCandidate candidate;
  final double score;
  final int distance;
  final bool eligibleDefault;
  final bool slightlyHard;
  final String reason;
}

LearnerSkill _skillFor(LearnModule module) => switch (module) {
  LearnModule.vocab => LearnerSkill.vocab,
  LearnModule.video => LearnerSkill.listening,
  LearnModule.reading => LearnerSkill.reading,
  LearnModule.oral => LearnerSkill.speaking,
};

/// Recall keeps i+1 (current or +1). +2 may appear as 稍难. The ranker only
/// orders what recall kept.
List<ScoredLearnCandidate> rankLearnCandidates({
  required List<LearnCandidate> candidates,
  required LearnerSkillProfile profile,
  Map<LearnModule, int> difficultyShift = const <LearnModule, int>{},
}) {
  final List<ScoredLearnCandidate> scored = <ScoredLearnCandidate>[];
  for (final LearnCandidate candidate in candidates) {
    if (candidate.notInterested || candidate.oralLineUsedRecently) {
      continue;
    }
    final SkillEstimate skill = profile.recommendationEstimate(
      _skillFor(candidate.module),
    );
    final int shifted = learnerBandIndex(skill.band) +
        (difficultyShift[candidate.module] ?? 0);
    final int distance = bandDistance(
      contentBand: candidate.contentBand,
      skillBand: learnerBandAt(shifted),
    );
    if (distance < 0 || distance > 2) continue;
    final bool slightlyHard = distance == 2;
    final bool eligibleDefault = distance <= 1;
    double score = eligibleDefault ? 3 : 0;
    if (candidate.pursuit) score += 2.5;
    if (candidate.interestMatch) score += 2;
    if (slightlyHard) score -= 1;
    score -= distance * 0.15;
    scored.add(
      ScoredLearnCandidate(
        candidate: candidate,
        score: score,
        distance: distance,
        eligibleDefault: eligibleDefault,
        slightlyHard: slightlyHard,
        reason: _reason(candidate, skill, distance),
      ),
    );
  }
  scored.sort((ScoredLearnCandidate a, ScoredLearnCandidate b) {
    final int byPursuit = (b.candidate.pursuit ? 1 : 0).compareTo(
      a.candidate.pursuit ? 1 : 0,
    );
    if (byPursuit != 0) return byPursuit;
    return b.score.compareTo(a.score);
  });
  return scored;
}

String _reason(LearnCandidate candidate, SkillEstimate skill, int distance) {
  final String level = skill.calibrating
      ? '约 ${skill.band} · 校准中'
      : '适合约 ${skill.band}';
  if (candidate.pursuit) return '你正在追这个 · $level';
  if (distance == 2) return '稍难 · $level';
  if (candidate.interestMatch) return '接近你的兴趣 · $level';
  if (distance == 1) return '比当前略难一点 · $level';
  return level;
}

/// Aimless path: vocab, then video, then reading. Each step uses only the
/// i+1 window for that skill.
ScoredLearnCandidate? pickAimlessNext(List<ScoredLearnCandidate> ranked) {
  for (final LearnModule module in <LearnModule>[
    LearnModule.vocab,
    LearnModule.video,
    LearnModule.reading,
  ]) {
    final List<ScoredLearnCandidate> pool =
        ranked
            .where(
              (ScoredLearnCandidate item) =>
                  item.candidate.module == module && item.eligibleDefault,
            )
            .toList()
          ..sort(
            (ScoredLearnCandidate a, ScoredLearnCandidate b) =>
                b.score.compareTo(a.score),
          );
    if (pool.isNotEmpty) return pool.first;
  }
  return null;
}

/// Purposeful path: user still chooses. Highest pursuit / interest first.
List<ScoredLearnCandidate> purposefulShortlist(
  List<ScoredLearnCandidate> ranked, {
  int limit = 4,
}) {
  final List<ScoredLearnCandidate> pool = ranked
      .where(
        (ScoredLearnCandidate item) =>
            item.candidate.pursuit || item.eligibleDefault || item.slightlyHard,
      )
      .toList();
  if (pool.length <= limit) return pool;
  return pool.take(limit).toList();
}
