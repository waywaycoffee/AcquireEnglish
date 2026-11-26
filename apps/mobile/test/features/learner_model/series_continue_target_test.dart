import 'package:common_learn_english/features/learner_model/domain/journey_next_step.dart';
import 'package:common_learn_english/features/learner_model/domain/learning_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('after episode 3 completed, next button is episode 4', () {
    final JourneyTask? task = seriesContinueTarget(
      const SeriesProgress(
        itemCount: 6,
        lastIndex: 2,
        lastCompleted: true,
        confirmed: true,
        currentTitle: '继续第3集',
        currentRoute: '/episodes/e3',
        nextTitle: '继续第4集 · Next',
        nextRoute: '/episodes/e4',
      ),
      enabled: true,
      module: LearnModule.video,
    );
    expect(task?.route, '/episodes/e4');
    expect(task?.title, contains('第4集'));
  });

  test('unfinished episode 3 keeps resume on episode 3', () {
    final JourneyTask? task = seriesContinueTarget(
      const SeriesProgress(
        itemCount: 6,
        lastIndex: 2,
        lastCompleted: false,
        confirmed: true,
        currentTitle: '继续第3集',
        currentRoute: '/episodes/e3',
        nextTitle: '继续第4集',
        nextRoute: '/episodes/e4',
      ),
      enabled: true,
      module: LearnModule.video,
    );
    expect(task?.route, '/episodes/e3');
  });
}
