import 'learner_skill_profile.dart';

class SkillProbeItem {
  const SkillProbeItem({
    required this.id,
    required this.skill,
    required this.band,
    required this.passage,
    required this.question,
    required this.choices,
    required this.answer,
    this.speakPassage = false,
  });

  final String id;
  final LearnerSkill skill;
  final String band;

  /// Listening items are spoken with on-device TTS; reading items are shown.
  final String passage;
  final String question;
  final List<String> choices;
  final int answer;
  final bool speakPassage;
}

/// Short independent items. No media files in the APK.
const List<SkillProbeItem> kSkillProbeBank = <SkillProbeItem>[
  SkillProbeItem(
    id: 'listen-a2-bus',
    skill: LearnerSkill.listening,
    band: 'A2',
    speakPassage: true,
    passage:
        'The next bus to the museum leaves at three fifteen from gate four.',
    question: 'Where does the bus leave from?',
    choices: <String>['Gate four', 'Gate two', 'The museum'],
    answer: 0,
  ),
  SkillProbeItem(
    id: 'listen-a2-rain',
    skill: LearnerSkill.listening,
    band: 'A2',
    speakPassage: true,
    passage:
        'Tom wanted to walk home, but it started raining, so he took a taxi.',
    question: 'Why did Tom take a taxi?',
    choices: <String>['It was raining', 'He missed the bus', 'The walk was long'],
    answer: 0,
  ),
  SkillProbeItem(
    id: 'listen-b1-meeting',
    skill: LearnerSkill.listening,
    band: 'B1',
    speakPassage: true,
    passage:
        'The meeting was moved from Tuesday morning to Wednesday afternoon '
        'because two speakers were delayed.',
    question: 'When is the meeting now?',
    choices: <String>[
      'Tuesday morning',
      'Wednesday afternoon',
      'Wednesday morning',
    ],
    answer: 1,
  ),
  SkillProbeItem(
    id: 'listen-b1-library',
    skill: LearnerSkill.listening,
    band: 'B1',
    speakPassage: true,
    passage:
        'You can borrow up to four books, but magazines must stay in the reading room.',
    question: 'What must stay in the reading room?',
    choices: <String>['All books', 'Magazines', 'Student cards'],
    answer: 1,
  ),
  SkillProbeItem(
    id: 'listen-b2-policy',
    skill: LearnerSkill.listening,
    band: 'B2',
    speakPassage: true,
    passage:
        'Although night trains were cut, evening services were extended. '
        'The city says more people travel before midnight than after it.',
    question: 'What trade-off does the city describe?',
    choices: <String>[
      'Fewer night trains for longer evening service',
      'Cheaper tickets for slower trains',
      'More night trains and fewer daytime trains',
    ],
    answer: 0,
  ),
  SkillProbeItem(
    id: 'read-a2-bag',
    skill: LearnerSkill.reading,
    band: 'A2',
    passage: 'Mia has a red bag. She takes it to school every morning.',
    question: 'What does Mia take to school?',
    choices: <String>['A red bag', 'A blue coat', 'A lunch box'],
    answer: 0,
  ),
  SkillProbeItem(
    id: 'read-a2-hours',
    skill: LearnerSkill.reading,
    band: 'A2',
    passage:
        'The cafe opens at eight. On Sundays it opens one hour later.',
    question: 'When does the cafe open on Sunday?',
    choices: <String>['At seven', 'At eight', 'At nine'],
    answer: 2,
  ),
  SkillProbeItem(
    id: 'read-b1-bus',
    skill: LearnerSkill.reading,
    band: 'B1',
    passage:
        'Ben had planned to cycle to work. When he saw how heavily it was raining, '
        'he left his bike at home and caught the bus instead.',
    question: 'Why did Ben take the bus?',
    choices: <String>[
      'His bike was broken',
      'The weather changed his plan',
      'He was meeting a friend',
    ],
    answer: 1,
  ),
  SkillProbeItem(
    id: 'read-b1-library',
    skill: LearnerSkill.reading,
    band: 'B1',
    passage:
        'The library closes at six, except on Thursdays, when it stays open until eight.',
    question: 'When does the library close on Thursday?',
    choices: <String>['At six', 'At eight', 'At seven'],
    answer: 1,
  ),
  SkillProbeItem(
    id: 'read-b2-campaign',
    skill: LearnerSkill.reading,
    band: 'B2',
    passage:
        'The report attributes the rise in sales to the campaign. Yet a rival '
        'withdrew from the market during the same period, so the data do not '
        'isolate the campaign’s effect.',
    question: 'What is the main objection?',
    choices: <String>[
      'Sales actually fell',
      'Another event could explain part of the rise',
      'The campaign was never launched',
    ],
    answer: 1,
  ),
  SkillProbeItem(
    id: 'read-b2-archive',
    skill: LearnerSkill.reading,
    band: 'B2',
    passage:
        'The essay does not dispute that the archive contains omissions. It '
        'disputes the comfort of treating them as accidents: what was repeatedly '
        'left unrecorded is as revealing as what was carefully preserved.',
    question: 'What does the writer imply about the omissions?',
    choices: <String>[
      'Their pattern can reveal the priorities of those who kept the archive.',
      'They make the remaining records inherently unreliable.',
      'They can be explained by isolated administrative mistakes.',
    ],
    answer: 0,
  ),
];

/// Prefer the current band, then +1. Skip ids already answered once.
List<SkillProbeItem> pickSkillProbes({
  required LearnerSkill skill,
  required String band,
  required Set<String> answeredIds,
  int limit = 2,
}) {
  final List<SkillProbeItem> pool = kSkillProbeBank
      .where(
        (SkillProbeItem item) =>
            item.skill == skill && !answeredIds.contains(item.id),
      )
      .toList();
  int score(SkillProbeItem item) {
    final int distance = bandDistance(
      contentBand: item.band,
      skillBand: band,
    );
    if (distance < 0 || distance > 1) return 100;
    return distance;
  }

  pool.sort((SkillProbeItem a, SkillProbeItem b) {
    final int byScore = score(a).compareTo(score(b));
    if (byScore != 0) return byScore;
    return a.id.compareTo(b.id);
  });
  return pool.where((SkillProbeItem item) => score(item) < 100).take(limit).toList();
}

class SkillProbeSummary {
  const SkillProbeSummary({
    required this.skill,
    required this.band,
    required this.calibrating,
    required this.attemptCount,
    required this.correctCount,
    required this.distinctDays,
  });

  final LearnerSkill skill;
  final String band;
  final bool calibrating;
  final int attemptCount;
  final int correctCount;
  final int distinctDays;

  double? get rate =>
      attemptCount == 0 ? null : correctCount / attemptCount;

  String get label => calibrating
      ? '约 $band · 校准中'
      : '约 $band · App 内估计';
}

List<SkillProbeSummary> summarizeProbes({
  required LearnerSkillProfile profile,
  required List<ProbeAttempt> probes,
}) {
  final List<ProbeAttempt> first = firstAttemptsOnly(probes);
  return <SkillProbeSummary>[
    for (final LearnerSkill skill in <LearnerSkill>[
      LearnerSkill.vocab,
      LearnerSkill.listening,
      LearnerSkill.reading,
    ])
      () {
        final SkillEstimate estimate = profile.estimate(skill);
        final List<ProbeAttempt> rows = first
            .where((ProbeAttempt row) => row.skill == skill)
            .toList();
        return SkillProbeSummary(
          skill: skill,
          band: estimate.band,
          calibrating: estimate.calibrating,
          attemptCount: rows.length,
          correctCount: rows.where((ProbeAttempt row) => row.correct).length,
          distinctDays: rows.map((ProbeAttempt row) => row.dayOnly).toSet().length,
        );
      }(),
  ];
}
