import 'package:common_learn_english/features/learner_model/domain/learner_skill_profile.dart';
import 'package:common_learn_english/features/learner_model/domain/skill_probe_bank.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picks current-band listening items and skips answered ones', () {
    final List<SkillProbeItem> picked = pickSkillProbes(
      skill: LearnerSkill.listening,
      band: 'B1',
      answeredIds: <String>{'listen-b1-meeting'},
      limit: 2,
    );
    expect(picked, isNotEmpty);
    expect(
      picked.every(
        (SkillProbeItem item) =>
            item.skill == LearnerSkill.listening &&
            item.id != 'listen-b1-meeting',
      ),
      isTrue,
    );
    expect(
      picked.every(
        (SkillProbeItem item) =>
            bandDistance(contentBand: item.band, skillBand: 'B1') <= 1,
      ),
      isTrue,
    );
  });

  test('summary keeps effort separate from skill labels', () {
    final LearnerSkillProfile profile = LearnerSkillProfile.initial(
      priorBand: 'B1',
    );
    final List<SkillProbeSummary> rows = summarizeProbes(
      profile: profile,
      probes: <ProbeAttempt>[
        ProbeAttempt(
          skill: LearnerSkill.reading,
          itemId: 'read-b1-bus',
          band: 'B1',
          day: DateTime(2026, 11, 20),
          correct: true,
        ),
        ProbeAttempt(
          skill: LearnerSkill.reading,
          itemId: 'read-b1-library',
          band: 'B1',
          day: DateTime(2026, 11, 21),
          correct: false,
        ),
      ],
    );
    final SkillProbeSummary reading = rows.firstWhere(
      (SkillProbeSummary row) => row.skill == LearnerSkill.reading,
    );
    expect(reading.attemptCount, 2);
    expect(reading.correctCount, 1);
    expect(reading.distinctDays, 2);
    expect(reading.label, contains('校准中'));
  });
}
