import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../constants/endpoints.dart';
import '../../authentication/presentation/account_storage.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';

final readingColdStartProvider = FutureProvider<void>((ref) async {
  final account = ref.watch(studyAccountProvider);
  final base = ref.watch(learningSettingsProvider).resolvedCloudApiBaseUrl;
  ref.read(readingLibraryProvider);
  for (int i = 0; i < 40 && !ref.read(readingLibraryProvider).ready; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!ref.mounted) return;
  }
  if (!ref.mounted ||
      !ref.read(readingLibraryProvider).ready ||
      ref.read(readingLibraryProvider).userDocs.isNotEmpty)
    return;
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  try {
    final response = await dio.get<dynamic>(
      Uri.parse(
        Endpoints.normalizeBaseUrl(base),
      ).resolve('api/reading/starter').toString(),
    );
    if (!ref.mounted || account != ref.read(studyAccountProvider)) return;
    final docs = (response.data['documents'] as List<dynamic>)
        .map((d) => ReadingDoc.fromJson(Map<String, dynamic>.from(d as Map)))
        .take(3)
        .toList();
    final notifier = ref.read(readingLibraryProvider.notifier);
    for (final doc in docs) {
      if (!ref.mounted || account != ref.read(studyAccountProvider)) return;
      await notifier.addDoc(doc, checkQuota: false);
    }
  } finally {
    dio.close();
  }
});
