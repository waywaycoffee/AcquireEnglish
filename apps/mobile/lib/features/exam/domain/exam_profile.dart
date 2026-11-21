import 'exam_registry.dart';

enum StudyMode { acquisition, exam }

class ExamProfile {
  const ExamProfile({
    this.mode = StudyMode.acquisition,
    this.familyId,
    this.targetScore,
    this.targetDateIso,
  });

  factory ExamProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ExamProfile();
    final String modeRaw = '${json['mode'] ?? 'acquisition'}';
    return ExamProfile(
      mode: modeRaw == StudyMode.exam.name
          ? StudyMode.exam
          : StudyMode.acquisition,
      familyId: (json['familyId'] as String?)?.trim(),
      targetScore: (json['targetScore'] as String?)?.trim(),
      targetDateIso: (json['targetDateIso'] as String?)?.trim(),
    );
  }

  final StudyMode mode;
  final String? familyId;
  final String? targetScore;
  final String? targetDateIso;

  bool get isExamMode => mode == StudyMode.exam;

  ExamFamily? get family => examFamilyById(familyId);

  String get resolvedCefr {
    final ExamFamily? f = family;
    if (f == null) return 'A2';
    if ((f.id == 'ielts_ac' || f.id == 'ielts_gt') &&
        targetScore != null &&
        targetScore!.isNotEmpty) {
      return cefrForIeltsBand(targetScore!);
    }
    return f.defaultCefr;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mode': mode.name,
    if (familyId != null && familyId!.isNotEmpty) 'familyId': familyId,
    if (targetScore != null && targetScore!.isNotEmpty)
      'targetScore': targetScore,
    if (targetDateIso != null && targetDateIso!.isNotEmpty)
      'targetDateIso': targetDateIso,
  };

  ExamProfile copyWith({
    StudyMode? mode,
    String? familyId,
    bool clearFamily = false,
    String? targetScore,
    bool clearTargetScore = false,
    String? targetDateIso,
    bool clearTargetDate = false,
  }) => ExamProfile(
    mode: mode ?? this.mode,
    familyId: clearFamily ? null : (familyId ?? this.familyId),
    targetScore: clearTargetScore ? null : (targetScore ?? this.targetScore),
    targetDateIso: clearTargetDate
        ? null
        : (targetDateIso ?? this.targetDateIso),
  );
}
