import 'package:common_learn_english/features/learner_model/domain/learner_skill_profile.dart';
import 'package:common_learn_english/features/learner_model/domain/skill_trend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trend stays flat without probes and captions calmly', () {
    final List<SkillTrendDay> trend = buildSkillTrend(
      profile: LearnerSkillProfile.initial(priorBand: 'A2'),
      probes: const <ProbeAttempt>[],
      now: DateTime(2026, 11, 26),
      days: 7,
    );
    expect(trend, hasLength(7));
    expect(
      trend.every(
        (SkillTrendDay day) => day.bandBySkill[LearnerSkill.vocab] == 'A2',
      ),
      isTrue,
    );
    expect(skillTrendCaption(trend), contains('校准'));
  });

  test('enough first-attempt evidence lifts the later days', () {
    final List<ProbeAttempt> probes = <ProbeAttempt>[
      for (int i = 0; i < 5; i++)
        ProbeAttempt(
          skill: LearnerSkill.vocab,
          itemId: 'w$i',
          band: 'B1',
          day: DateTime(2026, 11, i.isEven ? 20 : 21),
          correct: i != 4,
        ),
    ];
    final List<SkillTrendDay> trend = buildSkillTrend(
      profile: LearnerSkillProfile.initial(priorBand: 'B1'),
      probes: probes,
      now: DateTime(2026, 11, 26),
      days: 7,
    );
    expect(trend.first.bandBySkill[LearnerSkill.vocab], 'B1');
    expect(trend.last.bandBySkill[LearnerSkill.vocab], 'B2');
    expect(skillTrendCaption(trend), contains('认词 B1→B2'));
  });
}
