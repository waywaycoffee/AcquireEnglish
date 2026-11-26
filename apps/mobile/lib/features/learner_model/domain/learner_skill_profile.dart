/// App-internal skill bands. Not an official CEFR claim.
const List<String> kLearnerBands = <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

enum LearnerSkill { vocab, listening, reading, speaking }

int learnerBandIndex(String band) {
  final int index = kLearnerBands.indexOf(band.trim().toUpperCase());
  return index < 0 ? 2 : index;
}

String learnerBandAt(int index) =>
    kLearnerBands[index.clamp(0, kLearnerBands.length - 1)];

/// Map free-form catalog labels onto app bands. Returns null when unknown
/// so callers do not pretend A1 K12 text is the learner's C2 band.
String? tryParseLearnerBand(String raw) {
  final String upper = raw.trim().toUpperCase();
  if (upper.isEmpty) return null;
  if (kLearnerBands.contains(upper)) return upper;
  return switch (upper) {
    'ELE' || 'ELEMENTARY' || 'BEGINNER' || '初级' || '零基础' => 'A1',
    'PRE-INT' || 'PREINT' || 'PRE-INTERMEDIATE' => 'A2',
    'INT' || 'INTERMEDIATE' || '中级' => 'B1',
    'UPPER-INT' || 'UPPERINT' || 'UPPER-INTERMEDIATE' => 'B2',
    'ADV' || 'ADVANCED' || '高级' => 'C1',
    'PROFICIENCY' || '精通' => 'C2',
    _ => null,
  };
}

String contentBandOrFallback(String raw, String fallback) =>
    tryParseLearnerBand(raw) ??
    (tryParseLearnerBand(fallback) ?? learnerBandAt(learnerBandIndex(fallback)));

/// Map syllabus book examTag / title hints onto an App vocab band.
///
/// Active word books strongly set [LearnerSkill.vocab]; unknown tags return null
/// so callers can keep the current estimate.
String? bandFromSyllabusExamTag(String examTag, {String title = ''}) {
  final String raw = '${examTag.trim()} ${title.trim()}'.toUpperCase();
  if (raw.trim().isEmpty) return null;
  final String? direct = tryParseLearnerBand(examTag);
  if (direct != null) return direct;
  if (RegExp(r'FOUNDATION|零基础|PHONIC|IPA|PRIMARY|小学|一年级|二年级|三年级')
      .hasMatch(raw)) {
    return 'A1';
  }
  if (RegExp(r'四年级|五年级|六年级|初一|七年级').hasMatch(raw)) {
    return 'A2';
  }
  if (RegExp(r'中考|ZHONGKAO|JK\b|JUNIOR|初中|初二|初三|八年级|九年级')
      .hasMatch(raw)) {
    return 'A2';
  }
  if (RegExp(r'高考|GK\b|SENIOR|高中|高一|高二|高三|CET[-_]?4|四级')
      .hasMatch(raw)) {
    return 'B1';
  }
  if (RegExp(r'CET[-_]?6|六级|KAOYAN|考研|IELTS|雅思|TOEFL|托福|GRE')
      .hasMatch(raw)) {
    return 'B2';
  }
  if (RegExp(r'C1|专八|高级|ADV').hasMatch(raw)) return 'C1';
  if (RegExp(r'C2|精通|PROF').hasMatch(raw)) return 'C2';
  if (RegExp(r'PATTERN|句型').hasMatch(raw)) return 'B1';
  return null;
}

/// Score how well [contentLevel] fits [learnerLevel] for ranking.
/// Strongly rejects material more than one band below the learner
/// (e.g. 小学三年级 A1 for a C2 profile).
int levelFitScore(String contentLevel, String learnerLevel) {
  final String? content = tryParseLearnerBand(contentLevel);
  final String skill =
      tryParseLearnerBand(learnerLevel) ?? learnerBandAt(learnerBandIndex(learnerLevel));
  if (content == null) return 0;
  final int distance = bandDistance(contentBand: content, skillBand: skill);
  if (distance < -1) return -25;
  if (distance == -1) return 0;
  if (distance == 0) return 3;
  if (distance == 1) return 5;
  if (distance == 2) return 1;
  return -25;
}

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
