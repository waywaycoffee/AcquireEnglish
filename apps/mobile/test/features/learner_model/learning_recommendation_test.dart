import 'package:common_learn_english/features/learner_model/domain/journey_next_step.dart';
import 'package:common_learn_english/features/learner_model/domain/learner_skill_profile.dart';
import 'package:common_learn_english/features/learner_model/domain/learning_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first attempts ignore later reviews of the same word', () {
    final List<ProbeAttempt> kept = firstAttemptsOnly(<ProbeAttempt>[
      ProbeAttempt(
        skill: LearnerSkill.vocab,
        itemId: 'apple',
        band: 'A2',
        day: DateTime(2026, 11, 1, 9),
        correct: false,
      ),
      ProbeAttempt(
        skill: LearnerSkill.vocab,
        itemId: 'apple',
        band: 'A2',
        day: DateTime(2026, 11, 1, 18),
        correct: true,
      ),
    ]);
    expect(kept, hasLength(1));
    expect(kept.single.correct, isFalse);
  });

  test('band stays put until enough days and new items', () {
    final BandUpdate update = updateBandFromProbes(
      current: const SkillEstimate(band: 'B1', calibrating: true),
      probes: <ProbeAttempt>[
        for (int i = 0; i < 5; i++)
          ProbeAttempt(
            skill: LearnerSkill.vocab,
            itemId: 'w$i',
            band: 'B1',
            day: DateTime(2026, 11, 2),
            correct: true,
          ),
      ],
    );
    expect(update.changed, isFalse);
    expect(update.next.band, 'B1');
    expect(update.next.calibrating, isTrue);
  });

  test('enough first-attempt evidence promotes one band', () {
    final BandUpdate update = updateBandFromProbes(
      current: const SkillEstimate(band: 'B1', calibrating: true),
      probes: <ProbeAttempt>[
        for (int i = 0; i < 5; i++)
          ProbeAttempt(
            skill: LearnerSkill.vocab,
            itemId: 'w$i',
            band: 'B1',
            day: DateTime(2026, 11, i.isEven ? 2 : 3),
            correct: i != 4,
          ),
      ],
    );
    expect(update.changed, isTrue);
    expect(update.next.band, 'B2');
    expect(update.next.calibrating, isFalse);
  });

  test('aimless pick stays on vocab inside the new window', () {
    final LearnerSkillProfile profile = LearnerSkillProfile(
      skills: <LearnerSkill, SkillEstimate>{
        LearnerSkill.vocab: const SkillEstimate(band: 'B2', calibrating: false),
        LearnerSkill.listening: const SkillEstimate(
          band: 'A2',
          calibrating: false,
        ),
        LearnerSkill.reading: const SkillEstimate(
          band: 'B1',
          calibrating: false,
        ),
        LearnerSkill.speaking: const SkillEstimate(
          band: 'A2',
          calibrating: true,
        ),
      },
    );
    final List<ScoredLearnCandidate> ranked = rankLearnCandidates(
      profile: profile,
      candidates: const <LearnCandidate>[
        LearnCandidate(
          id: 'easy-word',
          title: 'A1 词',
          route: '/words',
          module: LearnModule.vocab,
          contentBand: 'A1',
        ),
        LearnCandidate(
          id: 'fit-word',
          title: 'B2 新词',
          route: '/review/session?kind=word',
          module: LearnModule.vocab,
          contentBand: 'B2',
        ),
        LearnCandidate(
          id: 'hard-video',
          title: 'C1 视频',
          route: '/episodes/c1',
          module: LearnModule.video,
          contentBand: 'C1',
        ),
        LearnCandidate(
          id: 'fit-video',
          title: 'A2 视频',
          route: '/episodes/a2',
          module: LearnModule.video,
          contentBand: 'A2',
          interestMatch: true,
        ),
      ],
    );
    final ScoredLearnCandidate? next = pickAimlessNext(ranked);
    expect(next?.candidate.id, 'fit-word');
    expect(ranked.any((ScoredLearnCandidate s) => s.candidate.id == 'easy-word'), isFalse);
    expect(ranked.any((ScoredLearnCandidate s) => s.candidate.id == 'hard-video'), isFalse);
  });

  test('after the vocab band rises, the old default drops out', () {
    final LearnerSkillProfile before = LearnerSkillProfile.initial(
      priorBand: 'A2',
    );
    final List<ScoredLearnCandidate> first = rankLearnCandidates(
      profile: before,
      candidates: const <LearnCandidate>[
        LearnCandidate(
          id: 'a2',
          title: 'A2',
          route: '/words',
          module: LearnModule.vocab,
          contentBand: 'A2',
        ),
      ],
    );
    expect(first.single.eligibleDefault, isTrue);

    final LearnerSkillProfile after = LearnerSkillProfile(
      skills: <LearnerSkill, SkillEstimate>{
        ...before.skills,
        LearnerSkill.vocab: const SkillEstimate(band: 'B2', calibrating: false),
      },
    );
    final List<ScoredLearnCandidate> second = rankLearnCandidates(
      profile: after,
      candidates: const <LearnCandidate>[
        LearnCandidate(
          id: 'a2',
          title: 'A2',
          route: '/words',
          module: LearnModule.vocab,
          contentBand: 'A2',
        ),
        LearnCandidate(
          id: 'b2',
          title: 'B2',
          route: '/words',
          module: LearnModule.vocab,
          contentBand: 'B2',
        ),
      ],
    );
    expect(second.map((ScoredLearnCandidate s) => s.candidate.id), ['b2']);
  });

  test('purposeful shortlist puts the pursuit first and keeps a harder swap', () {
    final List<ScoredLearnCandidate> ranked = rankLearnCandidates(
      profile: LearnerSkillProfile.initial(priorBand: 'B1'),
      candidates: const <LearnCandidate>[
        LearnCandidate(
          id: 'interest',
          title: '兴趣视频',
          route: '/episodes/1',
          module: LearnModule.video,
          contentBand: 'B1',
          interestMatch: true,
        ),
        LearnCandidate(
          id: 'series',
          title: '在追的剧',
          route: '/episodes/2',
          module: LearnModule.video,
          contentBand: 'B1',
          pursuit: true,
        ),
        LearnCandidate(
          id: 'stretch',
          title: '稍难阅读',
          route: '/reading/1',
          module: LearnModule.reading,
          contentBand: 'C1',
        ),
        LearnCandidate(
          id: 'repeat',
          title: '昨天的开场白',
          route: '/digital-human',
          module: LearnModule.oral,
          contentBand: 'B1',
          oralLineUsedRecently: true,
        ),
      ],
    );
    final List<ScoredLearnCandidate> list = purposefulShortlist(ranked);
    expect(list.first.candidate.id, 'series');
    expect(list.map((ScoredLearnCandidate s) => s.candidate.id), isNot(contains('repeat')));
    expect(
      list.firstWhere((ScoredLearnCandidate s) => s.candidate.id == 'stretch').slightlyHard,
      isTrue,
    );
  });

  test('due cards come first, then the next episode', () {
    const JourneyTask episode4 = JourneyTask(
      route: '/episodes/4',
      title: '继续第 4 集',
      module: LearnModule.video,
    );
    final JourneyNextStep before = resolveJourneyNext(
      const JourneyNextRequest(
        dueReviewCount: 12,
        pursuit: episode4,
      ),
    );
    expect(before.kind, JourneyNextKind.review);
    expect(before.title, '复习到期内容');

    final JourneyNextStep after = resolveJourneyNext(
      const JourneyNextRequest(
        dueReviewCount: 12,
        reviewFinished: true,
        pursuit: episode4,
      ),
    );
    expect(after.kind, JourneyNextKind.continuePursuit);
    expect(after.title, '继续第 4 集');
    expect(after.route, '/episodes/4');
    expect(after.reason, contains('昨天学到这里了'));
  });

  test('an unfinished explicit task stays ahead of due review', () {
    final JourneyNextStep step = resolveJourneyNext(
      const JourneyNextRequest(
        paused: JourneyTask(
          route: '/episodes/4',
          title: '第 4 集',
          module: LearnModule.video,
        ),
        dueReviewCount: 8,
        pursuit: JourneyTask(
          route: '/episodes/5',
          title: '继续第 5 集',
          module: LearnModule.video,
        ),
      ),
    );
    expect(step.kind, JourneyNextKind.paused);
    expect(step.route, '/episodes/4');
  });

  test('episode 3 continues to episode 4, a one-off does not', () {
    final JourneyTask? next = seriesContinueTarget(
      const SeriesProgress(
        itemCount: 10,
        lastIndex: 2,
        lastCompleted: true,
        confirmed: false,
        currentTitle: '继续第 3 集',
        currentRoute: '/episodes/3',
        nextTitle: '继续第 4 集',
        nextRoute: '/episodes/4',
      ),
      enabled: true,
      module: LearnModule.video,
    );
    expect(next?.title, '继续第 4 集');

    expect(
      seriesContinueTarget(
        const SeriesProgress(
          itemCount: 1,
          lastIndex: 0,
          lastCompleted: true,
          confirmed: false,
          currentTitle: '一条独立视频',
          currentRoute: '/episodes/solo',
          nextTitle: '',
          nextRoute: '',
        ),
        enabled: true,
        module: LearnModule.video,
      ),
      isNull,
    );

    expect(
      seriesContinueTarget(
        const SeriesProgress(
          itemCount: 10,
          lastIndex: 0,
          lastCompleted: true,
          confirmed: false,
          currentTitle: '第 1 集',
          currentRoute: '/episodes/1',
          nextTitle: '继续第 2 集',
          nextRoute: '/episodes/2',
        ),
        enabled: true,
        module: LearnModule.video,
      ),
      isNull,
    );
  });

  test('turning video off still leaves reading and review', () {
    expect(
      seriesContinueTarget(
        const SeriesProgress(
          itemCount: 10,
          lastIndex: 2,
          lastCompleted: true,
          confirmed: false,
          currentTitle: '继续第 3 集',
          currentRoute: '/episodes/3',
          nextTitle: '继续第 4 集',
          nextRoute: '/episodes/4',
        ),
        enabled: false,
        module: LearnModule.video,
      ),
      isNull,
    );
    final JourneyNextStep step = resolveJourneyNext(
      const JourneyNextRequest(
        dueReviewCount: 3,
        reviewFinished: true,
        pursuit: JourneyTask(
          route: '/reading/book',
          title: '继续读这本书',
          module: LearnModule.reading,
        ),
      ),
    );
    expect(step.kind, JourneyNextKind.continuePursuit);
    expect(step.route, '/reading/book');
  });

  test('no level match asks for a current-level pick', () {
    final JourneyNextStep step = resolveJourneyNext(
      const JourneyNextRequest(reviewFinished: true),
    );
    expect(step.kind, JourneyNextKind.chooseLevel);
    expect(step.title, '选一条适合你水平的内容');
  });

  test('swap is this choice only, dislike lasts a week, difficulty shifts', () {
    expect(effectFor(LearnFeedback.swap).sessionOnly, isTrue);
    expect(effectFor(LearnFeedback.swap).demoteDays, 0);
    expect(effectFor(LearnFeedback.notInterested).demoteDays, 7);
    expect(effectFor(LearnFeedback.tooHard).difficultyShift, -1);
    expect(effectFor(LearnFeedback.tooEasy).difficultyShift, 1);

    final LearnerSkillProfile profile = LearnerSkillProfile.initial(
      priorBand: 'B1',
    );
    const List<LearnCandidate> candidates = <LearnCandidate>[
      LearnCandidate(
        id: 'a2',
        title: 'A2 视频',
        route: '/episodes/a2',
        module: LearnModule.video,
        contentBand: 'A2',
      ),
      LearnCandidate(
        id: 'b1',
        title: 'B1 视频',
        route: '/episodes/b1',
        module: LearnModule.video,
        contentBand: 'B1',
      ),
      LearnCandidate(
        id: 'hidden',
        title: '不感兴趣',
        route: '/episodes/no',
        module: LearnModule.video,
        contentBand: 'B1',
        notInterested: true,
      ),
    ];
    final List<ScoredLearnCandidate> easier = rankLearnCandidates(
      profile: profile,
      candidates: candidates,
      difficultyShift: <LearnModule, int>{
        LearnModule.video: effectFor(LearnFeedback.tooHard).difficultyShift,
      },
    );
    expect(easier.first.candidate.id, 'a2');
    expect(
      easier.any((ScoredLearnCandidate item) => item.candidate.id == 'hidden'),
      isFalse,
    );
  });
}
