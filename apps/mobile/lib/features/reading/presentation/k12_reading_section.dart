import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../constants/endpoints.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/reading_doc.dart';
import 'reading_library_provider.dart';

final FutureProvider<List<Map<String, dynamic>>> k12ReadingCatalogProvider =
    FutureProvider<List<Map<String, dynamic>>>((Ref ref) async {
      final String base = Endpoints.normalizeBaseUrl(
        ref.watch(learningSettingsProvider).resolvedCloudApiBaseUrl,
      );
      final Dio dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      try {
        final Response<dynamic> response = await dio.get<dynamic>(
          '${base}media/reading/k12/catalog.json',
        );
        final Map<String, dynamic> body = Map<String, dynamic>.from(
          response.data as Map<dynamic, dynamic>,
        );
        return (body['articles'] as List<dynamic>)
            .map(
              (dynamic e) =>
                  Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
            )
            .toList();
      } finally {
        dio.close();
      }
    });

class K12ReadingSection extends ConsumerWidget {
  const K12ReadingSection({super.key, required this.gradeId});
  final String gradeId;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> item,
  ) async {
    try {
      final Map<String, dynamic> article = Map<String, dynamic>.from(
        item['article'] as Map<dynamic, dynamic>,
      );
      final String id = 'k12-reading:$gradeId';
      final ReadingDoc doc = ReadingDoc(
        id: id,
        title: article['title'] as String? ?? 'English Reading',
        titleZh: article['title_zh'] as String? ?? '',
        sourceType: ReadingSourceType.catalog,
        plainText: article['passage'] as String,
        sourceLabel: '爱快英语官方资料 · ${item['level']} · AI原创/审校',
        courseTitle: '${item['level']}时文阅读',
        createdAt: DateTime.now().toUtc(),
      );
      await ref
          .read(readingLibraryProvider.notifier)
          .addDoc(doc, checkQuota: false);
      if (context.mounted) {
        await context.push('/reading/${Uri.encodeComponent(id)}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开阅读：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '官方资料 · 本年级时文阅读',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ref
            .watch(k12ReadingCatalogProvider)
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (Object error, StackTrace stack) => TextButton(
                onPressed: () => ref.invalidate(k12ReadingCatalogProvider),
                child: const Text('阅读目录暂不可用，点击重试'),
              ),
              data: (List<Map<String, dynamic>> items) {
                final List<Map<String, dynamic>> articles = items
                    .where(
                      (Map<String, dynamic> e) =>
                          e['grade_id'] == gradeId &&
                          e['collection'] == 'official_k12_reading' &&
                          e['review_status'] == 'ai_reviewed',
                    )
                    .toList();
                if (articles.isEmpty) return const Text('本年级阅读正在准备中');
                return Column(
                  children: <Widget>[
                    for (final Map<String, dynamic> item in articles)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(
                            '${(item['article'] as Map<dynamic, dynamic>)['title_zh'] ?? (item['article'] as Map<dynamic, dynamic>)['title'] ?? '主题阅读'}',
                          ),
                          subtitle: Text(
                            '${item['level']} · ${(item['article'] as Map<dynamic, dynamic>)['word_count']} 词 · AI 审校',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(context, ref, item),
                        ),
                      ),
                  ],
                );
              },
            ),
        const SizedBox(height: 18),
      ],
    );
  }
}
