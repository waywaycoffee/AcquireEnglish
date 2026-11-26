import 'package:common_learn_english/features/learner_model/domain/journey_next_step.dart';
import 'package:common_learn_english/features/learner_model/domain/learning_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const JourneyTask plannedEp = JourneyTask(
    route: '/episodes/4',
    title: '继续第 4 集',
    module: LearnModule.video,
  );
  const JourneyTask cold = JourneyTask(
    route: '/episodes/cold',
    title: '冷推荐视频',
    module: LearnModule.video,
  );
  const JourneyTask pursuitEp = JourneyTask(
    route: '/episodes/4',
    title: '继续第 4 集',
    module: LearnModule.video,
  );

  test('planned beats cold recommend', () {
    final JourneyNextStep step = resolveJourneyNext(
      const JourneyNextRequest(
        reviewFinished: true,
        planned: plannedEp,
        plannedReason: '接着第4集',
        recommendation: cold,
        recommendationReason: '适合你听力档',
      ),
    );
    expect(step.route, '/episodes/4');
    expect(step.kind, anyOf(JourneyNextKind.planned, JourneyNextKind.continuePursuit));
    expect(step.reason, '接着第4集');
    expect(step.title, isNot(contains('冷推荐')));
  });

  test('paused beats planned', () {
    final JourneyNextStep step = resolveJourneyNext(
      const JourneyNextRequest(
        paused: JourneyTask(
          route: '/episodes/paused',
          title: '未做完的一集',
          module: LearnModule.video,
        ),
        reviewFinished: true,
        planned: plannedEp,
        plannedReason: '接着第4集',
        recommendation: cold,
      ),
    );
    expect(step.kind, JourneyNextKind.paused);
    expect(step.route, '/episodes/paused');
  });

  test('due review beats planned', () {
    final JourneyNextStep step = resolveJourneyNext(
      const JourneyNextRequest(
        dueReviewCount: 5,
        planned: plannedEp,
        plannedReason: '接着第4集',
        recommendation: cold,
      ),
    );
    expect(step.kind, JourneyNextKind.review);
    expect(step.route, contains('journeyReview=1'));
  });

  test('after reviewFinished planned shows ahead of cold', () {
    final JourneyNextStep step = resolveJourneyNext(
      const JourneyNextRequest(
        dueReviewCount: 5,
        reviewFinished: true,
        planned: plannedEp,
        plannedReason: '接着第4集',
        recommendation: cold,
        recommendationReason: '适合你听力档',
      ),
    );
    expect(step.route, '/episodes/4');
    expect(step.kind, isNot(JourneyNextKind.recommend));
    expect(step.kind, isNot(JourneyNextKind.review));
  });

  test('planned same route as pursuit uses chase title', () {
    final JourneyNextStep step = resolveJourneyNext(
      const JourneyNextRequest(
        reviewFinished: true,
        planned: JourneyTask(
          route: '/episodes/4',
          title: 'Travel Vlog',
          module: LearnModule.video,
        ),
        plannedReason: '接着第4集',
        pursuit: pursuitEp,
        recommendation: cold,
      ),
    );
    expect(step.kind, JourneyNextKind.continuePursuit);
    expect(step.title, '继续第 4 集');
    expect(step.route, '/episodes/4');
  });

  test('empty recommendation falls through to chooseLevel', () {
    final JourneyNextStep step = resolveJourneyNext(
      const JourneyNextRequest(
        reviewFinished: true,
        recommendation: JourneyTask(
          route: '',
          title: '交给系统推荐',
          module: LearnModule.video,
        ),
        recommendationReason: '明天再看适合你的内容',
      ),
    );
    expect(step.kind, JourneyNextKind.chooseLevel);
    expect(step.route, isEmpty);
  });
}
