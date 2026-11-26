import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../domain/learner_skill_profile.dart';

class LearnerSkillProfileStore {
  LearnerSkillProfileStore(this.account);

  final String account;

  Box<String>? get _prefs =>
      Hive.isBoxOpen('prefs') ? Hive.box<String>('prefs') : null;

  String get _key => 'learnerSkillProfile:${Uri.encodeComponent(account)}';

  LearnerSkillProfile load({String priorBand = 'B1'}) {
    final String? raw = _prefs?.get(_key);
    if (raw == null) {
      return LearnerSkillProfile.initial(priorBand: priorBand);
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return LearnerSkillProfile.initial(priorBand: priorBand);
      }
      final Map<LearnerSkill, SkillEstimate> skills =
          <LearnerSkill, SkillEstimate>{};
      for (final LearnerSkill skill in LearnerSkill.values) {
        final Object? row = decoded[skill.name];
        if (row is Map<String, dynamic>) {
          skills[skill] = SkillEstimate(
            band: '${row['band'] ?? priorBand}',
            calibrating: row['calibrating'] as bool? ?? true,
          );
        }
      }
      if (skills.length != LearnerSkill.values.length) {
        final LearnerSkillProfile seed = LearnerSkillProfile.initial(
          priorBand: priorBand,
        );
        return LearnerSkillProfile(
          skills: <LearnerSkill, SkillEstimate>{...seed.skills, ...skills},
        );
      }
      return LearnerSkillProfile(skills: skills);
    } on FormatException {
      return LearnerSkillProfile.initial(priorBand: priorBand);
    }
  }

  Future<void> save(LearnerSkillProfile profile) async {
    final Map<String, Object?> json = <String, Object?>{
      for (final MapEntry<LearnerSkill, SkillEstimate> entry
          in profile.skills.entries)
        entry.key.name: <String, Object?>{
          'band': entry.value.band,
          'calibrating': entry.value.calibrating,
        },
    };
    await _prefs?.put(_key, jsonEncode(json));
  }

  List<ProbeAttempt> loadProbes() {
    final String? raw = _prefs?.get('$_key:probes');
    if (raw == null) return const <ProbeAttempt>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <ProbeAttempt>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> row) => ProbeAttempt(
              skill: LearnerSkill.values.firstWhere(
                (LearnerSkill skill) => skill.name == row['skill'],
                orElse: () => LearnerSkill.vocab,
              ),
              itemId: '${row['itemId'] ?? ''}',
              band: '${row['band'] ?? 'B1'}',
              day: DateTime.tryParse('${row['day'] ?? ''}') ?? DateTime.now(),
              correct: row['correct'] as bool? ?? false,
            ),
          )
          .where((ProbeAttempt attempt) => attempt.itemId.isNotEmpty)
          .toList();
    } on FormatException {
      return const <ProbeAttempt>[];
    }
  }

  Future<void> saveProbes(List<ProbeAttempt> probes) async {
    final List<Map<String, Object?>> rows = probes
        .map(
          (ProbeAttempt attempt) => <String, Object?>{
            'skill': attempt.skill.name,
            'itemId': attempt.itemId,
            'band': attempt.band,
            'day': attempt.day.toIso8601String(),
            'correct': attempt.correct,
          },
        )
        .toList();
    await _prefs?.put('$_key:probes', jsonEncode(rows));
  }

  /// Strongly align vocab band with an active syllabus book (not a weak prior).
  Future<LearnerSkillProfile> setVocabBandStrongly({
    required String band,
    String priorBand = 'B1',
  }) async {
    final String nextBand = learnerBandAt(learnerBandIndex(band));
    final LearnerSkillProfile current = load(priorBand: priorBand);
    final SkillEstimate currentVocab = current.estimate(LearnerSkill.vocab);
    if (currentVocab.band == nextBand && !currentVocab.calibrating) {
      return current;
    }
    final LearnerSkillProfile next = LearnerSkillProfile(
      skills: <LearnerSkill, SkillEstimate>{
        ...current.skills,
        LearnerSkill.vocab: SkillEstimate(band: nextBand, calibrating: false),
      },
    );
    await save(next);
    return next;
  }

  Future<LearnerSkillProfile> recordProbe({
    required ProbeAttempt attempt,
    String priorBand = 'B1',
  }) async {
    final List<ProbeAttempt> probes = <ProbeAttempt>[
      ...loadProbes(),
      attempt,
    ];
    await saveProbes(probes);
    final LearnerSkillProfile current = load(priorBand: priorBand);
    final SkillEstimate skill = current.estimate(attempt.skill);
    final BandUpdate update = updateBandFromProbes(
      current: skill,
      probes: firstAttemptsOnly(
        probes.where((ProbeAttempt row) => row.skill == attempt.skill),
      ),
    );
    if (!update.changed) return current;
    final LearnerSkillProfile next = LearnerSkillProfile(
      skills: <LearnerSkill, SkillEstimate>{
        ...current.skills,
        attempt.skill: update.next,
      },
    );
    await save(next);
    return next;
  }
}
