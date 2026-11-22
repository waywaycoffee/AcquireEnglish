import 'exam_registry.dart';

/// Kept for persisted JSON compatibility. Product is unified under acquisition;
/// exam tools use [hasExamTarget] (selected family), not a separate mode.
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
    return ExamProfile(
      // Always acquisition — dual study-mode switch was removed.
      mode: StudyMode.acquisition,
      familyId: (json['familyId'] as String?)?.trim(),
      targetScore: (json['targetScore'] as String?)?.trim(),
      targetDateIso: (json['targetDateIso'] as String?)?.trim(),
    );
  }

  final StudyMode mode;
  final String? familyId;
  final String? targetScore;
  final String? targetDateIso;

  /// True when an exam family is selected (not a separate "exam mode").
  bool get hasExamTarget => family != null;

  /// Legacy alias for call sites that used mode switching.
  bool get isExamMode => hasExamTarget;

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
    'mode': StudyMode.acquisition.name,
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
    mode: StudyMode.acquisition,
    familyId: clearFamily ? null : (familyId ?? this.familyId),
    targetScore: clearTargetScore ? null : (targetScore ?? this.targetScore),
    targetDateIso: clearTargetDate
        ? null
        : (targetDateIso ?? this.targetDateIso),
  );
}
