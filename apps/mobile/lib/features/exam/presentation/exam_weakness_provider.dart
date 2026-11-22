import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/exam_error_book_store.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_weakness.dart';
import 'exam_profile_provider.dart';

final Provider<ExamWeaknessReport?> examWeaknessProvider =
    Provider<ExamWeaknessReport?>((Ref ref) {
  final ExamProfile profile = ref.watch(examProfileProvider);
  final String? familyId = profile.familyId;
  if (familyId == null || familyId.isEmpty) return null;
  final Map<String, int> progress =
      ref.watch(examProgressProvider).forFamily(familyId);
  final List<ExamErrorItem> errors = ref.watch(examErrorBookProvider);
  return diagnoseExamWeakness(
    familyId: familyId,
    progress: progress,
    errors: errors,
  );
});
