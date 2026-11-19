import 'package:common_learn_english/features/words/domain/sm2_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Sm2Scheduler scheduler = Sm2Scheduler();

  test('good grade follows Ebbinghaus day ladder', () {
    Sm2State state = const Sm2State();
    final List<int> intervals = <int>[];
    for (int i = 0; i < 6; i++) {
      state = scheduler.review(state, Sm2Grade.good);
      intervals.add(state.intervalDays);
    }
    expect(intervals, <int>[1, 2, 4, 7, 15, 30]);
  });

  test('again resets to learning due today', () {
    final Sm2State learned = scheduler.review(const Sm2State(), Sm2Grade.good);
    final Sm2State again = scheduler.review(learned, Sm2Grade.again);
    expect(again.repetitions, 0);
    expect(again.intervalDays, 0);
    expect(again.mastery, WordMastery.learning);
  });
}
