import '../data/exam_error_book_store.dart';

/// Skills we diagnose for prep assistant (K12 / 中高考 / CET objective + cloze).
const List<String> kExamDiagnoseSkills = <String>[
  'listening',
  'reading',
  'vocab',
  'grammar',
  'cloze',
];

String examSkillLabel(String skill) => switch (skill) {
      'listening' => '听力',
      'reading' => '阅读',
      'vocab' => '词汇',
      'grammar' => '语法',
      'cloze' => '完形',
      'writing' => '写作',
      'speaking' => '口语',
      'mock' => '模考',
      _ => skill,
    };

String examSkillRoute(String skill) => switch (skill) {
      'cloze' => '/exam/cloze',
      'grammar' => '/exam/grammar',
      'listening' => '/exam/listening',
      'reading' => '/exam/reading',
      'writing' => '/writing',
      'speaking' => '/digital-human',
      _ => '/exam/session?skill=$skill',
    };

class ExamSkillWeakness {
  const ExamSkillWeakness({
    required this.skill,
    required this.weakScore,
    required this.errorCount,
    required this.route,
  });

  final String skill;

  /// 0 = solid, 1 = weakest.
  final double weakScore;
  final int errorCount;
  final String route;

  String get label => examSkillLabel(skill);
}

class ExamWeaknessReport {
  const ExamWeaknessReport({
    required this.familyId,
    this.skills = const <ExamSkillWeakness>[],
    this.errorTotal = 0,
    this.practiced = 0,
    this.correct = 0,
    this.wrong = 0,
  });

  final String familyId;
  final List<ExamSkillWeakness> skills;
  final int errorTotal;
  final int practiced;
  final int correct;
  final int wrong;

  double get accuracy {
    final int n = correct + wrong;
    if (n <= 0) return 0;
    return correct / n;
  }

  ExamSkillWeakness? get topWeak {
    if (skills.isEmpty) return null;
    return skills.first;
  }

  List<ExamSkillWeakness> get actionable =>
      skills.where((ExamSkillWeakness s) => s.weakScore >= 0.25).toList();
}

/// Pure diagnosis from local progress + error book (no network).
ExamWeaknessReport diagnoseExamWeakness({
  required String familyId,
  required Map<String, int> progress,
  required List<ExamErrorItem> errors,
}) {
  final List<ExamErrorItem> familyErrors = errors
      .where(
        (ExamErrorItem e) =>
            e.familyId == familyId ||
            (familyId.isNotEmpty && e.familyId.isEmpty),
      )
      .toList(growable: false);

  final Map<String, int> bySkill = <String, int>{};
  for (final ExamErrorItem e in familyErrors) {
    final String skill = _normalizeSkill(e.skill);
    bySkill[skill] = (bySkill[skill] ?? 0) + 1;
  }

  final int practiced = progress['practiced'] ?? 0;
  final int correct = progress['correct'] ?? 0;
  final int wrong = progress['wrong'] ?? 0;
  final int errorTotal = familyErrors.length;
  final double globalMiss = practiced <= 0
      ? (errorTotal > 0 ? 0.55 : 0.0)
      : (wrong / practiced).clamp(0.0, 1.0);

  final List<ExamSkillWeakness> skills = <ExamSkillWeakness>[];
  for (final String skill in kExamDiagnoseSkills) {
    final int count = bySkill[skill] ?? 0;
    final double share =
        errorTotal <= 0 ? 0.0 : (count / errorTotal).clamp(0.0, 1.0);
    // Blend error concentration with overall miss rate so empty books
    // after a bad mock still surface a mild global signal on vocab/reading.
    final double weak = errorTotal == 0
        ? (skill == 'vocab' || skill == 'reading' ? globalMiss * 0.5 : 0.0)
        : (0.65 * share + 0.35 * globalMiss * (count > 0 ? 1.0 : 0.15))
            .clamp(0.0, 1.0);
    skills.add(
      ExamSkillWeakness(
        skill: skill,
        weakScore: weak,
        errorCount: count,
        route: examSkillRoute(skill),
      ),
    );
  }
  skills.sort(
    (ExamSkillWeakness a, ExamSkillWeakness b) =>
        b.weakScore.compareTo(a.weakScore),
  );

  return ExamWeaknessReport(
    familyId: familyId,
    skills: List<ExamSkillWeakness>.unmodifiable(skills),
    errorTotal: errorTotal,
    practiced: practiced,
    correct: correct,
    wrong: wrong,
  );
}

String _normalizeSkill(String raw) {
  final String s = raw.trim().toLowerCase();
  if (s.contains('listen')) return 'listening';
  if (s.contains('read')) return 'reading';
  if (s.contains('vocab') || s.contains('word')) return 'vocab';
  if (s.contains('grammar') || s.contains('语法')) return 'grammar';
  if (s.contains('cloze') || s.contains('完形')) return 'cloze';
  if (s.contains('writ')) return 'writing';
  if (s.contains('speak') || s.contains('oral')) return 'speaking';
  return s.isEmpty ? 'vocab' : s;
}
