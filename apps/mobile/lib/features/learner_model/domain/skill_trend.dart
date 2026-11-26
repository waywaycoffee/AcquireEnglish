import 'learner_skill_profile.dart';

class SkillTrendDay {
  const SkillTrendDay({
    required this.day,
    required this.label,
    required this.bandBySkill,
  });

  final DateTime day;
  final String label;
  final Map<LearnerSkill, String> bandBySkill;

  int indexOf(LearnerSkill skill) =>
      learnerBandIndex(bandBySkill[skill] ?? 'B1');
}

/// Rebuild the last [days] daily band estimates from first-attempt probes.
/// Days with no new evidence keep the previous band (flat until evidence moves).
List<SkillTrendDay> buildSkillTrend({
  required LearnerSkillProfile profile,
  required List<ProbeAttempt> probes,
  DateTime? now,
  int days = 7,
}) {
  final DateTime end = now ?? DateTime.now();
  final DateTime endDay = DateTime(end.year, end.month, end.day);
  final List<ProbeAttempt> first = firstAttemptsOnly(probes)
    ..sort((ProbeAttempt a, ProbeAttempt b) => a.day.compareTo(b.day));

  SkillEstimate seedFor(LearnerSkill skill) {
    for (final ProbeAttempt row in first) {
      if (row.skill == skill) {
        return SkillEstimate(band: row.band, calibrating: true);
      }
    }
    return profile.estimate(skill);
  }

  final Map<LearnerSkill, SkillEstimate> running =
      <LearnerSkill, SkillEstimate>{
        for (final LearnerSkill skill in <LearnerSkill>[
          LearnerSkill.vocab,
          LearnerSkill.listening,
          LearnerSkill.reading,
        ])
          skill: seedFor(skill),
      };

  // Warm start from all probes before the window so the first point is honest.
  final DateTime windowStart = endDay.subtract(Duration(days: days - 1));
  for (final LearnerSkill skill in running.keys) {
    running[skill] = _bandThrough(
      prior: seedFor(skill),
      probes: first.where(
        (ProbeAttempt row) =>
            row.skill == skill && row.dayOnly.isBefore(windowStart),
      ),
    );
  }

  final List<SkillTrendDay> out = <SkillTrendDay>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = windowStart.add(Duration(days: i));
    for (final LearnerSkill skill in running.keys) {
      running[skill] = _bandThrough(
        prior: seedFor(skill),
        probes: first.where(
          (ProbeAttempt row) =>
              row.skill == skill && !row.dayOnly.isAfter(day),
        ),
      );
    }
    out.add(
      SkillTrendDay(
        day: day,
        label: '${day.month}/${day.day}',
        bandBySkill: <LearnerSkill, String>{
          for (final MapEntry<LearnerSkill, SkillEstimate> entry
              in running.entries)
            entry.key: entry.value.band,
        },
      ),
    );
  }
  return out;
}

SkillEstimate _bandThrough({
  required SkillEstimate prior,
  required Iterable<ProbeAttempt> probes,
}) {
  final List<ProbeAttempt> list = probes.toList();
  if (list.isEmpty) {
    return SkillEstimate(band: prior.band, calibrating: prior.calibrating);
  }
  // Replay promotions from the earliest prior band seen in probes, else profile.
  SkillEstimate current = SkillEstimate(
    band: list.first.band,
    calibrating: true,
  );
  // Fold chronologically in chunks of days so minDays can unlock.
  final List<DateTime> orderedDays =
      list.map((ProbeAttempt row) => row.dayOnly).toSet().toList()
        ..sort((DateTime a, DateTime b) => a.compareTo(b));
  for (final DateTime day in orderedDays) {
    final BandUpdate update = updateBandFromProbes(
      current: current,
      probes: list
          .where((ProbeAttempt row) => !row.dayOnly.isAfter(day))
          .toList(),
    );
    current = update.next;
  }
  return current;
}

String skillTrendCaption(List<SkillTrendDay> trend) {
  if (trend.length < 2) return '继续抽测后，这里会画出近一周的水平变化。';
  final SkillTrendDay first = trend.first;
  final SkillTrendDay last = trend.last;
  final List<String> bits = <String>[];
  for (final LearnerSkill skill in <LearnerSkill>[
    LearnerSkill.vocab,
    LearnerSkill.listening,
    LearnerSkill.reading,
  ]) {
    final String a = first.bandBySkill[skill] ?? 'B1';
    final String b = last.bandBySkill[skill] ?? 'B1';
    if (a == b) continue;
    final String name = switch (skill) {
      LearnerSkill.vocab => '认词',
      LearnerSkill.listening => '听力',
      LearnerSkill.reading => '阅读',
      LearnerSkill.speaking => '口语',
    };
    bits.add('$name $a→$b');
  }
  if (bits.isEmpty) {
    return '近一周档位还在校准，多做几天抽测就会看见曲线上移。';
  }
  return '近一周：${bits.join(' · ')}';
}
