import 'learner_skill_profile.dart';

class OralScenarioPick {
  const OralScenarioPick({
    required this.id,
    required this.title,
    required this.goal,
    required this.prompt,
    required this.difficulty,
  });

  final String id;
  final String title;
  final String goal;
  final String prompt;
  final String difficulty;
}

/// Keep openings inside the speaking/listening i+1 window and drop lines
/// used in the last seven days.
List<OralScenarioPick> filterOralScenarios({
  required List<OralScenarioPick> pool,
  required LearnerSkillProfile profile,
  required Set<String> usedLineKeys,
}) {
  final SkillEstimate skill = profile.recommendationEstimate(
    LearnerSkill.speaking,
  );
  final List<OralScenarioPick> kept = <OralScenarioPick>[];
  for (final OralScenarioPick item in pool) {
    final String key = oralLineKey(item);
    if (usedLineKeys.contains(key)) continue;
    final int distance = bandDistance(
      contentBand: item.difficulty,
      skillBand: skill.band,
    );
    if (distance < 0 || distance > 2) continue;
    kept.add(item);
  }
  kept.sort((OralScenarioPick a, OralScenarioPick b) {
    final int da = bandDistance(
      contentBand: a.difficulty,
      skillBand: skill.band,
    );
    final int db = bandDistance(
      contentBand: b.difficulty,
      skillBand: skill.band,
    );
    return da.compareTo(db);
  });
  return kept;
}

String oralLineKey(OralScenarioPick item) =>
    '${item.id}|${item.prompt.trim().toLowerCase()}';

/// Opening text changes with band. Low bands get a shorter scaffold.
String buildOralOpening({
  required String coachName,
  required OralScenarioPick scenario,
  required SkillEstimate skill,
  required List<String> frontierChunks,
  required Set<String> usedLineKeys,
}) {
  final String frontier = frontierChunks
      .map((String chunk) => chunk.trim())
      .where((String chunk) => chunk.isNotEmpty)
      .take(2)
      .join(', ');
  final bool lowBand =
      learnerBandIndex(skill.band) <= learnerBandIndex('A2');
  final String levelNote = skill.calibrating
      ? 'Keep sentences short; the learner is around ${skill.band} (calibrating).'
      : 'Stay near ${skill.band}.';
  final String avoid = usedLineKeys.isEmpty
      ? ''
      : ' Do not reuse yesterday\'s opening line.';
  final String inject = frontier.isEmpty
      ? ''
      : ' Try to weave in: $frontier.';

  if (scenario.id == 'freechat') {
    if (lowBand) {
      return 'Hi, I\'m $coachName. Let\'s chat in easy English. '
          'Ask one short question, wait, then correct gently. '
          '$levelNote$inject$avoid '
          '(Say “用中文” anytime.)';
    }
    return 'Hi, I\'m $coachName! Let\'s just chat in English — anything you like. '
        'I\'ll correct grammar gently as we go. '
        '${scenario.prompt} $levelNote$inject$avoid '
        '(Say “用中文” anytime if you want Chinese.)';
  }

  if (lowBand) {
    return 'Hi, I\'m $coachName. Scene: ${scenario.title}. '
        'Ask one easy question about this: ${scenario.prompt} '
        '$levelNote$inject$avoid '
        '(Say “用中文” anytime.)';
  }

  return 'Hi, I\'m $coachName! Today\'s scene is “${scenario.title}”. '
      'Goal: ${scenario.goal}. '
      'I\'ll role-play with you and correct grammar as we go. '
      'Let\'s start: ${scenario.prompt} '
      '$levelNote$inject$avoid '
      '(Say “用中文” anytime if you want Chinese.)';
}

/// True when this exact opening was already used recently.
bool oralOpeningUsedRecently({
  required String opening,
  required Set<String> usedOpenings,
}) {
  final String key = opening.trim().toLowerCase();
  return usedOpenings.contains(key);
}
