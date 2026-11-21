/// First-open intake: focus (single) + filters for content inside that module.
class OnboardingInterest {
  const OnboardingInterest({required this.id, required this.label});
  final String id;
  final String label;
}

class LearningFocus {
  const LearningFocus({
    required this.id,
    required this.label,
    required this.route,
    required this.homeBlurb,
    required this.startLabel,
  });

  final String id;
  final String label;
  final String route;
  final String homeBlurb;
  final String startLabel;
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

const List<LearningFocus> kLearningFocuses = <LearningFocus>[
  LearningFocus(
    id: 'video',
    label: '视频精听',
    route: '/library',
    homeBlurb: '符合兴趣和水平的一段视频',
    startLabel: '开始视频精听',
  ),
  LearningFocus(
    id: 'reading',
    label: '阅读',
    route: '/reading',
    homeBlurb: '符合兴趣和水平的一篇短文',
    startLabel: '开始阅读',
  ),
  LearningFocus(
    id: 'oral',
    label: '日常口语',
    route: '/learn/dialogue',
    homeBlurb: '一个能立即开口的生活场景',
    startLabel: '开始口语练习',
  ),
  LearningFocus(
    id: 'vocab',
    label: '背单词',
    route: '/words/syllabus',
    homeBlurb: '一组符合目标和水平的词',
    startLabel: '打开统一词书',
  ),
];

/// Backward-compatible alias used by older call sites.
typedef OnboardingMode = LearningFocus;

const List<LearningFocus> kOnboardingModes = kLearningFocuses;

const List<({String id, String label, String level})> kOnboardingAbility =
    <({String id, String label, String level})>[
  (id: 'beginner', label: '刚开始学', level: '零基础'),
  (id: 'words', label: '能读懂简单句子', level: 'A2'),
  (id: 'daily', label: '能应付日常交流', level: 'B1'),
  (id: 'complex', label: '想练更复杂的表达', level: 'B2'),
  (id: 'unsure', label: '不确定', level: 'A2'),
];

const Object _unset = Object();

const String kFocusTagPrefix = 'mode_';
const String kAgeTagPrefix = 'age_';

String? focusIdFromTags(List<String> tags) {
  for (final String tag in tags) {
    if (tag.startsWith(kFocusTagPrefix)) {
      return tag.substring(kFocusTagPrefix.length);
    }
  }
  return null;
}

LearningFocus? focusById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final LearningFocus focus in kLearningFocuses) {
    if (focus.id == id) return focus;
  }
  return null;
}

List<String> prefsTagsForProfile({
  required List<String> interestIds,
  String? ageBandId,
  String? focusId,
  List<String> keepTags = const <String>[],
}) {
  final Set<String> next = <String>{};
  for (final String tag in keepTags) {
    if (tag.startsWith(kFocusTagPrefix) || tag.startsWith(kAgeTagPrefix)) {
      continue;
    }
    // Drop interest ids we manage so the list stays in sync.
    final bool isInterest = kOnboardingInterests.any(
      (OnboardingInterest i) => i.id == tag,
    );
    if (!isInterest) next.add(tag);
  }
  next.addAll(interestIds);
  if (ageBandId != null && ageBandId.isNotEmpty) {
    next.add('$kAgeTagPrefix$ageBandId');
  }
  if (focusId != null && focusId.isNotEmpty) {
    next.add('$kFocusTagPrefix$focusId');
  }
  if (next.isEmpty) next.add('daily');
  return next.take(12).toList(growable: false);
}

class OnboardingProfile {
  const OnboardingProfile({
    this.interestIds = const <String>[],
    this.ageBandId,
    this.focusId,
    this.abilityId,
    this.canSyllableSplit,
    this.learnedPhonics,
    this.completed = false,
    // Legacy fields kept for JSON migration.
    this.modeIds = const <String>[],
    this.primaryModeId,
  });

  factory OnboardingProfile.fromJson(Map<String, dynamic> json) {
    final List<dynamic> legacyModes =
        json['modeIds'] as List<dynamic>? ?? const <dynamic>[];
    final String? focus = json['focusId'] as String? ??
        json['primaryModeId'] as String? ??
        (legacyModes.isEmpty ? null : '${legacyModes.first}');
    return OnboardingProfile(
      interestIds: (json['interestIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => '$e')
          .toList(growable: false),
      ageBandId: json['ageBandId'] as String?,
      focusId: focus,
      abilityId: json['abilityId'] as String?,
      canSyllableSplit: json['canSyllableSplit'] as bool?,
      learnedPhonics: json['learnedPhonics'] as bool?,
      completed: json['completed'] == true,
      modeIds: focus == null ? const <String>[] : <String>[focus],
      primaryModeId: focus,
    );
  }

  final List<String> interestIds;
  final String? ageBandId;
  final String? focusId;
  final String? abilityId;
  final bool? canSyllableSplit;
  final bool? learnedPhonics;
  final bool completed;
  final List<String> modeIds;
  final String? primaryModeId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'interestIds': interestIds,
        'ageBandId': ageBandId,
        'focusId': focusId,
        'abilityId': abilityId,
        'canSyllableSplit': canSyllableSplit,
        'learnedPhonics': learnedPhonics,
        'completed': completed,
        // Keep legacy keys so older builds still restore focus.
        'modeIds': focusId == null ? const <String>[] : <String>[focusId!],
        'primaryModeId': focusId,
      };

  OnboardingProfile copyWith({
    List<String>? interestIds,
    String? ageBandId,
    bool clearAgeBand = false,
    Object? focusId = _unset,
    String? abilityId,
    bool? canSyllableSplit,
    bool? learnedPhonics,
    bool? completed,
  }) {
    final String? nextFocus = identical(focusId, _unset)
        ? this.focusId
        : focusId as String?;
    return OnboardingProfile(
      interestIds: interestIds ?? this.interestIds,
      ageBandId: clearAgeBand ? null : (ageBandId ?? this.ageBandId),
      focusId: nextFocus,
      abilityId: abilityId ?? this.abilityId,
      canSyllableSplit: canSyllableSplit ?? this.canSyllableSplit,
      learnedPhonics: learnedPhonics ?? this.learnedPhonics,
      completed: completed ?? this.completed,
      modeIds: nextFocus == null ? const <String>[] : <String>[nextFocus],
      primaryModeId: nextFocus,
    );
  }

  String get resolvedLevel {
    for (final ({String id, String label, String level}) row
        in kOnboardingAbility) {
      if (row.id == abilityId) return row.level;
    }
    return 'A2';
  }

  LearningFocus? get focus => focusById(focusId);

  /// Legacy getter.
  LearningFocus? get primaryMode => focus;

  List<LearningFocus> get otherModes => kLearningFocuses
      .where((LearningFocus m) => m.id != focusId)
      .toList(growable: false);

  bool get showSyllableHints => canSyllableSplit == false;
  bool get showPhonicsHints => learnedPhonics == false;

  List<String> get warmUpRoutes {
    final List<String> routes = <String>[];
    if (showSyllableHints) routes.add('/learn/ipa');
    if (showPhonicsHints) routes.add('/learn/phonics');
    return routes;
  }
}
