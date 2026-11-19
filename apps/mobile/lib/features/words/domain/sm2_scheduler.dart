/// Simplified SM-2 scheduler (Ebbinghaus-style spaced repetition).
enum Sm2Grade { again, hard, good, easy }

enum WordMastery { fresh, learning, known, mastered }

class Sm2State {
  const Sm2State({
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.dueAt,
    this.mastery = WordMastery.fresh,
  });

  final double ease;
  final int intervalDays;
  final int repetitions;
  final DateTime? dueAt;
  final WordMastery mastery;

  Sm2State copyWith({
    double? ease,
    int? intervalDays,
    int? repetitions,
    DateTime? dueAt,
    WordMastery? mastery,
  }) => Sm2State(
    ease: ease ?? this.ease,
    intervalDays: intervalDays ?? this.intervalDays,
    repetitions: repetitions ?? this.repetitions,
    dueAt: dueAt ?? this.dueAt,
    mastery: mastery ?? this.mastery,
  );
}

class Sm2Scheduler {
  const Sm2Scheduler();

  /// Classic day ladder: 1 → 2 → 4 → 7 → 15 → 30, then ease-based growth.
  static int _ebbinghausInterval({
    required int reps,
    required int previousInterval,
    required double ease,
    required double easyBoost,
  }) {
    const List<int> ladder = <int>[1, 2, 4, 7, 15, 30];
    if (reps < ladder.length) {
      final int base = ladder[reps];
      return (base * easyBoost).round().clamp(1, 3650);
    }
    final int grown = ((previousInterval <= 0 ? 30 : previousInterval) * ease * easyBoost)
        .round();
    return grown.clamp(1, 3650);
  }

  Sm2State review(Sm2State current, Sm2Grade grade, {DateTime? now}) {
    final DateTime today = now ?? DateTime.now();
    double ease = current.ease;
    int reps = current.repetitions;
    int interval = current.intervalDays;

    switch (grade) {
      case Sm2Grade.again:
        reps = 0;
        interval = 0;
        ease = (ease - 0.2).clamp(1.3, 3.0);
        return Sm2State(
          ease: ease,
          intervalDays: interval,
          repetitions: reps,
          dueAt: today,
          mastery: WordMastery.learning,
        );
      case Sm2Grade.hard:
        ease = (ease - 0.15).clamp(1.3, 3.0);
        interval = reps == 0 ? 1 : (interval * 1.2).round().clamp(1, 3650);
        reps += 1;
        break;
      case Sm2Grade.good:
        // Ebbinghaus-style day ladder, then ease growth.
        interval = _ebbinghausInterval(
          reps: reps,
          previousInterval: interval,
          ease: ease,
          easyBoost: 1.0,
        );
        reps += 1;
        break;
      case Sm2Grade.easy:
        ease = (ease + 0.15).clamp(1.3, 3.0);
        interval = _ebbinghausInterval(
          reps: reps,
          previousInterval: interval,
          ease: ease,
          easyBoost: 1.3,
        );
        reps += 1;
        break;
    }

    final WordMastery mastery;
    if (reps >= 5 && interval >= 21) {
      mastery = WordMastery.mastered;
    } else if (reps >= 3) {
      mastery = WordMastery.known;
    } else if (reps >= 1) {
      mastery = WordMastery.learning;
    } else {
      mastery = WordMastery.fresh;
    }

    return Sm2State(
      ease: ease,
      intervalDays: interval,
      repetitions: reps,
      dueAt: DateTime(today.year, today.month, today.day).add(
        Duration(days: interval),
      ),
      mastery: mastery,
    );
  }

  static String masteryLabel(WordMastery mastery) {
    switch (mastery) {
      case WordMastery.fresh:
        return '新词';
      case WordMastery.learning:
        return '学习中';
      case WordMastery.known:
        return '已认识';
      case WordMastery.mastered:
        return '已掌握';
    }
  }

  static WordMastery masteryFromName(String? raw) {
    switch (raw) {
      case 'learning':
        return WordMastery.learning;
      case 'known':
        return WordMastery.known;
      case 'mastered':
        return WordMastery.mastered;
      case 'new':
      case 'fresh':
      default:
        return WordMastery.fresh;
    }
  }
}
