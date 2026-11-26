import 'package:common_learn_english/features/learner_model/domain/learner_skill_profile.dart';
import 'package:common_learn_english/features/learner_model/domain/learning_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aimless next prefers video over vocab when both eligible', () {
    final LearnerSkillProfile fixed = LearnerSkillProfile(
      skills: <LearnerSkill, SkillEstimate>{
        for (final LearnerSkill skill in LearnerSkill.values)
          skill: const SkillEstimate(band: 'B1', calibrating: false),
      },
    );
    final List<ScoredLearnCandidate> ranked = rankLearnCandidates(
      candidates: const <LearnCandidate>[
        LearnCandidate(
          id: 'v',
          title: 'Episode',
          route: '/episodes/x',
          module: LearnModule.video,
          contentBand: 'B1',
        ),
        LearnCandidate(
          id: 'w',
          title: 'Words',
          route: '/words',
          module: LearnModule.vocab,
          contentBand: 'B1',
        ),
      ],
      profile: fixed,
    );
    final ScoredLearnCandidate? next = pickAimlessNext(ranked);
    expect(next, isNotNull);
    expect(next!.candidate.module, LearnModule.video);
    // Explicit vocab-first order still works for exam/vocab focus.
    expect(
      pickAimlessNext(
        ranked,
        preferOrder: const <LearnModule>[
          LearnModule.vocab,
          LearnModule.video,
        ],
      )?.candidate.module,
      LearnModule.vocab,
    );
  });
}
