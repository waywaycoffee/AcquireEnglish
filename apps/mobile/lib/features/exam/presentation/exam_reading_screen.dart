import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../community/data/community_models.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/exam_profile.dart';
import 'exam_profile_provider.dart';

class ExamReadingScreen extends ConsumerStatefulWidget {
  const ExamReadingScreen({super.key});

  @override
  ConsumerState<ExamReadingScreen> createState() => _ExamReadingScreenState();
}

class _ExamReadingScreenState extends ConsumerState<ExamReadingScreen> {
  List<ExamAssetDto> _items = const <ExamAssetDto>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ExamProfile profile = ref.read(examProfileProvider);
      final List<ExamAssetDto> all = await ref
          .read(acquireApiClientProvider)
          .listExamAssets(familyId: profile.familyId);
      final List<ExamAssetDto> texts = all
          .where(
            (ExamAssetDto e) =>
                e.kind == 'transcript' ||
                e.kind == 'answers' ||
                e.kind == 'notes' ||
                e.kind == 'reading' ||
                e.kind == 'other',
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = texts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('阅读专项')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(
                  profile.family == null
                      ? '可先打开爱快阅读库做泛读；选择考试族后优先展示社区阅读/脚本资料。'
                      : '${profile.family!.label} · 社区脚本与解析',
                  style: TextStyle(
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.push('/reading'),
                  icon: const Icon(Icons.chrome_reader_mode_outlined),
                  label: const Text('打开爱快阅读'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.push('/discover'),
                  child: const Text('社区上传阅读 / 解析资料'),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text('加载失败：$_error', style: const TextStyle(fontWeight: FontWeight.w700))
                else if (_items.isEmpty)
                  const Text(
                    '暂无社区阅读脚本。可上传 txt / srt / 解析后在此打开。',
                    style: TextStyle(fontWeight: FontWeight.w700, height: 1.45),
                  )
                else
                  for (final ExamAssetDto item in _items)
                    Card(
                      child: ListTile(
                        title: Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text('${item.kind} · ${item.uploaderName}'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () async {
                          final Uri? uri = Uri.tryParse(item.downloadUrl);
                          if (uri != null) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                      ),
                    ),
              ],
            ),
    );
  }
}
