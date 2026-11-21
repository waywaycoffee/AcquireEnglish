import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/data/acquire_api_client.dart';
import '../domain/exam_pack.dart';
import 'exam_profile_provider.dart';

final FutureProvider<ExamPack?> examPackProvider = FutureProvider<ExamPack?>((
  Ref ref,
) async {
  final String? familyId = ref.watch(examProfileProvider).familyId;
  if (familyId == null || familyId.isEmpty) return null;
  try {
    return await ref.read(acquireApiClientProvider).examPack(familyId);
  } catch (_) {
    return null;
  }
});
