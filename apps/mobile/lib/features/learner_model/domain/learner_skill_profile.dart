/// App-internal skill bands. Not an official CEFR claim.
const List<String> kLearnerBands = <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

enum LearnerSkill { vocab, listening, reading, speaking }

int learnerBandIndex(String band) {
  final int index = kLearnerBands.indexOf(band.trim().toUpperCase());
  return index < 0 ? 2 : index;
}

String learnerBandAt(int index) =>
    kLearnerBands[index.clamp(0, kLearnerBands.length - 1)];

/// One step up is i+1. Two steps up is "稍难". Further is out of window.
int bandDistance({required String contentBand, required String skillBand}) =>
    learnerBandIndex(contentBand) - learnerBandIndex(skillBand);

class SkillEstimate {
  const SkillEstimate({required this.band, required this.calibrating});

  final String band;
  final bool calibrating;

  String get label => calibrating ? '约 $band · 校准中' : '约 $band · App 内估计';

  SkillEstimate copyWith({String? band, bool? calibrating}) => SkillEstimate(
    band: band ?? this.band,
    calibrating: calibrating ?? this.calibrating,
  );
}

class LearnerSkillProfile {
  const LearnerSkillProfile({required this.skills});

  factory LearnerSkillProfile.initial({String priorBand = 'B1'}) {
    final String band = learnerBandAt(learnerBandIndex(priorBand));
    final SkillEstimate seed = SkillEstimate(band: band, calibrating: true);
    return LearnerSkillProfile(
      skills: <LearnerSkill, SkillEstimate>{
        for (final LearnerSkill skill in LearnerSkill.values) skill: seed,
      },
    );
  }

  final Map<LearnerSkill, SkillEstimate> skills;

  SkillEstimate estimate(LearnerSkill skill) =>
      skills[skill] ?? const SkillEstimate(band: 'B1', calibrating: true);

  /// Listening/reading/speaking still calibrating fall back to vocab for
  /// recommendations, and the UI must say so.
  SkillEstimate recommendationEstimate(LearnerSkill skill) {
    final SkillEstimate own = estimate(skill);
    if (!own.calibrating || skill == LearnerSkill.vocab) return own;
    final SkillEstimate vocab = estimate(LearnerSkill.vocab);
    return SkillEstimate(band: vocab.band, calibrating: true);
  }
}

class ProbeAttempt {
  const ProbeAttempt({
    required this.skill,
    required this.itemId,
    required this.band,
    required this.day,
    required this.correct,
  });

  final LearnerSkill skill;
  final String itemId;
  final String band;
  final DateTime day;
  final bool correct;

  DateTime get dayOnly => DateTime(day.year, day.month, day.day);
}

/// First attempt per item only. Same item later the same day does not count.
List<ProbeAttempt> firstAttemptsOnly(Iterable<ProbeAttempt> attempts) {
  final Map<String, ProbeAttempt> first = <String, ProbeAttempt>{};
  final List<ProbeAttempt> ordered = attempts.toList()
    ..sort((ProbeAttempt a, ProbeAttempt b) => a.day.compareTo(b.day));
  for (final ProbeAttempt attempt in ordered) {
    final String key = '${attempt.skill.name}|${attempt.itemId}';
    first.putIfAbsent(key, () => attempt);
  }
  return first.values.toList();
}

class BandUpdate {
  const BandUpdate({required this.next, required this.changed});

  final SkillEstimate next;
  final bool changed;
}

/// Promote or demote only after enough distinct days and lemmas.
///
/// About 80% first-attempt correct on the current band is the trial line.
/// A single weak day does not move the band.
BandUpdate updateBandFromProbes({
  required SkillEstimate current,
  required List<ProbeAttempt> probes,
  int minItems = 5,
  int minDays = 2,
  double promoteAt = 0.8,
  double demoteAt = 0.4,
}) {
  final List<ProbeAttempt> onBand = firstAttemptsOnly(probes)
      .where(
        (ProbeAttempt attempt) =>
            learnerBandIndex(attempt.band) == learnerBandIndex(current.band),
      )
      .toList();
  final Set<String> items = onBand.map((ProbeAttempt a) => a.itemId).toSet();
  final Set<DateTime> days = onBand.map((ProbeAttempt a) => a.dayOnly).toSet();
  if (items.length < minItems || days.length < minDays) {
    return BandUpdate(next: current, changed: false);
  }
  final int correct = onBand.where((ProbeAttempt a) => a.correct).length;
  final double rate = correct / onBand.length;
  if (rate >= promoteAt) {
    final String next = learnerBandAt(learnerBandIndex(current.band) + 1);
    final bool changed = next != current.band || current.calibrating;
    return BandUpdate(
      next: SkillEstimate(band: next, calibrating: false),
      changed: changed,
    );
  }
  if (rate <= demoteAt) {
    final String next = learnerBandAt(learnerBandIndex(current.band) - 1);
    final bool changed = next != current.band || current.calibrating;
    return BandUpdate(
      next: SkillEstimate(band: next, calibrating: false),
      changed: changed,
    );
  }
  if (current.calibrating) {
    return BandUpdate(
      next: current.copyWith(calibrating: false),
      changed: true,
    );
  }
  return BandUpdate(next: current, changed: false);
}
