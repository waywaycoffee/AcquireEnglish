/// Answers from the first-open three-screen intake.
class OnboardingInterest {
  const OnboardingInterest({required this.id, required this.label});
  final String id;
  final String label;
}

class OnboardingMode {
  const OnboardingMode({
    required this.id,
    required this.label,
    required this.route,
    required this.blurb,
  });
  final String id;
  final String label;
  final String route;
  final String blurb;
}

const List<OnboardingInterest> kOnboardingInterests = <OnboardingInterest>[
  OnboardingInterest(id: 'travel', label: '旅行'),
  OnboardingInterest(id: 'drama', label: '影视'),
  OnboardingInterest(id: 'games', label: '游戏'),
  OnboardingInterest(id: 'campus', label: '校园'),
  OnboardingInterest(id: 'business', label: '职场'),
  OnboardingInterest(id: 'tech', label: '科技'),
  OnboardingInterest(id: 'daily', label: '日常生活'),
];

const List<({String id, String label})> kOnboardingAgeBands =
    <({String id, String label})>[
  (id: 'primary', label: '小学'),
  (id: 'junior', label: '初中'),
  (id: 'senior', label: '高中'),
  (id: 'college', label: '大学'),
  (id: 'adult', label: '职场成人'),
];

const List<OnboardingMode> kOnboardingModes = <OnboardingMode>[
  OnboardingMode(
    id: 'video',
    label: '视频精听',
    route: '/library',
    blurb: '跟视频听懂、跟读、收藏表达',
  ),
  OnboardingMode(
    id: 'reading',
    label: '阅读',
    route: '/reading',
    blurb: '逛书库、点词查义、积累阅读量',
  ),
  OnboardingMode(
    id: 'oral',
    label: '日常口语',
    route: '/learn/dialogue',
    blurb: '场景对话里开口练',
  ),
  OnboardingMode(
    id: 'vocab',
    label: '背单词',
    route: '/words/syllabus',
    blurb: '按词书与复习计划记词',
  ),
];

const List<({String id, String label, String level})> kOnboardingAbility =
    <({String id, String label, String level})>[
  (id: 'beginner', label: '刚开始学', level: '零基础'),
  (id: 'words', label: '能看懂简单词句', level: 'A2'),
  (id: 'daily', label: '能应付日常交流', level: 'B1'),
  (id: 'complex', label: '想练更复杂的表达', level: 'B2'),
  (id: 'unsure', label: '不确定', level: 'A2'),
];

const Object _unset = Object();

class OnboardingProfile {
  const OnboardingProfile({
    this.interestIds = const <String>[],
    this.ageBandId,
    this.modeIds = const <String>[],
    this.primaryModeId,
    this.abilityId,
    this.canSyllableSplit,
    this.learnedPhonics,
    this.completed = false,
  });

  factory OnboardingProfile.fromJson(Map<String, dynamic> json) {
    return OnboardingProfile(
      interestIds: (json['interestIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      ageBandId: json['ageBandId'] as String?,
      modeIds: (json['modeIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      primaryModeId: json['primaryModeId'] as String?,
      abilityId: json['abilityId'] as String?,
      canSyllableSplit: json['canSyllableSplit'] as bool?,
      learnedPhonics: json['learnedPhonics'] as bool?,
      completed: json['completed'] == true,
    );
  }

  final List<String> interestIds;
  final String? ageBandId;
  final List<String> modeIds;
  final String? primaryModeId;
  final String? abilityId;
  final bool? canSyllableSplit;
  final bool? learnedPhonics;
  final bool completed;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'interestIds': interestIds,
        'ageBandId': ageBandId,
        'modeIds': modeIds,
        'primaryModeId': primaryModeId,
        'abilityId': abilityId,
        'canSyllableSplit': canSyllableSplit,
        'learnedPhonics': learnedPhonics,
        'completed': completed,
      };

  OnboardingProfile copyWith({
    List<String>? interestIds,
    String? ageBandId,
    bool clearAgeBand = false,
    List<String>? modeIds,
    Object? primaryModeId = _unset,
    String? abilityId,
    bool? canSyllableSplit,
    bool? learnedPhonics,
    bool? completed,
  }) {
    return OnboardingProfile(
      interestIds: interestIds ?? this.interestIds,
      ageBandId: clearAgeBand ? null : (ageBandId ?? this.ageBandId),
      modeIds: modeIds ?? this.modeIds,
      primaryModeId: identical(primaryModeId, _unset)
          ? this.primaryModeId
          : primaryModeId as String?,
      abilityId: abilityId ?? this.abilityId,
      canSyllableSplit: canSyllableSplit ?? this.canSyllableSplit,
      learnedPhonics: learnedPhonics ?? this.learnedPhonics,
      completed: completed ?? this.completed,
    );
  }

  String get resolvedLevel {
    for (final ({String id, String label, String level}) row
        in kOnboardingAbility) {
      if (row.id == abilityId) return row.level;
    }
    return 'A2';
  }

  OnboardingMode? get primaryMode {
    final String? id = primaryModeId;
    if (id == null) return null;
    for (final OnboardingMode mode in kOnboardingModes) {
      if (mode.id == id) return mode;
    }
    return null;
  }

  List<OnboardingMode> get otherModes {
    final String? primary = primaryModeId;
    return kOnboardingModes
        .where(
          (OnboardingMode m) => modeIds.contains(m.id) && m.id != primary,
        )
        .toList(growable: false);
  }

  List<String> get warmUpRoutes {
    final List<String> routes = <String>[];
    if (canSyllableSplit == false) routes.add('/learn/ipa');
    if (learnedPhonics == false) routes.add('/learn/phonics');
    return routes;
  }
}
