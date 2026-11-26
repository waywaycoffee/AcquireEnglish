import 'package:common_learn_english/features/learner_model/domain/journey_completion.dart';
import 'package:common_learn_english/features/learner_model/domain/learning_recommendation.dart';
import 'package:common_learn_english/features/learner_model/domain/oral_line_memory.dart';
import 'package:common_learn_english/features/learner_model/domain/learner_skill_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video needs a minute or three shadows', () {
    final JourneyCompletionResult short = evaluateJourneyCompletion(
      module: LearnModule.video,
      before: const JourneyProgressSnapshot(),
      after: const JourneyProgressSnapshot(videoWatchMs: 20000),
    );
    expect(short.allowed, isFalse);

    final JourneyCompletionResult ok = evaluateJourneyCompletion(
      module: LearnModule.video,
      before: const JourneyProgressSnapshot(shadowSentenceCount: 0),
      after: const JourneyProgressSnapshot(shadowSentenceCount: 3),
    );
    expect(ok.allowed, isTrue);
  });

  test('reading unlocks around 40 percent', () {
    final JourneyCompletionResult blocked = evaluateJourneyCompletion(
      module: LearnModule.reading,
      before: const JourneyProgressSnapshot(readingPercent: 0.1),
      after: const JourneyProgressSnapshot(readingPercent: 0.2),
    );
    expect(blocked.allowed, isFalse);

    final JourneyCompletionResult ok = evaluateJourneyCompletion(
      module: LearnModule.reading,
      before: const JourneyProgressSnapshot(),
      after: const JourneyProgressSnapshot(readingPercent: 0.45),
    );
    expect(ok.allowed, isTrue);
  });

  test('vocab needs five graded cards', () {
    expect(
      evaluateJourneyCompletion(
        module: LearnModule.vocab,
        before: const JourneyProgressSnapshot(vocabGraded: 1),
        after: const JourneyProgressSnapshot(vocabGraded: 4),
      ).allowed,
      isFalse,
    );
    expect(
      evaluateJourneyCompletion(
        module: LearnModule.vocab,
        before: const JourneyProgressSnapshot(vocabGraded: 1),
        after: const JourneyProgressSnapshot(vocabGraded: 6),
      ).allowed,
      isTrue,
    );
  });

  test('oral openings skip recent lines and stay near the band', () {
    final LearnerSkillProfile profile = LearnerSkillProfile(
      skills: <LearnerSkill, SkillEstimate>{
        for (final LearnerSkill skill in LearnerSkill.values)
          skill: const SkillEstimate(band: 'A2', calibrating: false),
      },
    );
    final List<OralScenarioPick> kept = filterOralScenarios(
      profile: profile,
      usedLineKeys: <String>{
        'weekend|tell me about your last weekend. what did you do, who with, and how did you feel?',
      },
      pool: const <OralScenarioPick>[
        OralScenarioPick(
          id: 'weekend',
          title: '描述周末',
          goal: 'g',
          prompt:
              'Tell me about your last weekend. What did you do, who with, and how did you feel?',
          difficulty: 'A2',
        ),
        OralScenarioPick(
          id: 'directions_a2',
          title: '问路',
          goal: 'g',
          prompt: 'Ask for directions to the nearest subway station.',
          difficulty: 'A2',
        ),
        OralScenarioPick(
          id: 'debate_b2',
          title: '辩论',
          goal: 'g',
          prompt: 'Take a side on remote work.',
          difficulty: 'B2',
        ),
      ],
    );
    expect(kept.map((OralScenarioPick item) => item.id).toList(), <String>[
      'directions_a2',
      'debate_b2',
    ]);
    final String opening = buildOralOpening(
      coachName: 'Mia',
      scenario: kept.first,
      skill: profile.estimate(LearnerSkill.speaking),
      frontierChunks: const <String>['apple', 'hope'],
      usedLineKeys: const <String>{'old'},
    );
    expect(opening.toLowerCase(), contains('apple'));
    expect(opening, contains('easy'));
    expect(opening, contains('Stay near A2'));
  });
}
