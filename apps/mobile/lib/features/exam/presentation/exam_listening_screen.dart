import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../community/data/community_models.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/exam_error_book_store.dart';
import '../domain/exam_profile.dart';
import 'exam_profile_provider.dart';

class ExamListeningScreen extends ConsumerStatefulWidget {
  const ExamListeningScreen({super.key});

  @override
  ConsumerState<ExamListeningScreen> createState() =>
      _ExamListeningScreenState();
}

class _ExamListeningScreenState extends ConsumerState<ExamListeningScreen> {
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
      final List<ExamAssetDto> audio = all
          .where(
            (ExamAssetDto e) =>
                e.kind == 'audio' || e.kind == 'transcript' || e.kind == 'other',
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = audio;
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

  Future<void> _open(ExamAssetDto item) async {
    final Uri? uri = Uri.tryParse(item.downloadUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _markHard(ExamAssetDto item) async {
    final ExamProfile profile = ref.read(examProfileProvider);
    await ref.read(examErrorBookProvider.notifier).add(
          ExamErrorItem(
            id: 'listen_${item.id}_${DateTime.now().millisecondsSinceEpoch}',
            familyId: profile.familyId ?? item.familyId,
            skill: 'listening',
            prompt: '听力资料需再练：${item.title}',
            wrongAnswer: '未掌握',
            correctAnswer: item.title,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
            note: item.downloadUrl,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已记入错题本')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('听力专项'),
        actions: <Widget>[
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(
                  profile.family == null
                      ? '登录后可拉取社区真题听力；建议先选择考试族以便筛选。'
                      : '当前考试：${profile.family!.label}。资料来自社区 ECS exam 命名空间。',
                  style: TextStyle(
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.push('/discover'),
                  child: const Text('去社区上传 / 浏览更多资料'),
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Text(
                    '加载失败：$_error',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  )
                else if (_items.isEmpty)
                  const Text(
                    '暂无听力/脚本资料。可在社区「考试」Tab 上传 mp3 / 字幕后在此练习。',
                    style: TextStyle(fontWeight: FontWeight.w700, height: 1.45),
                  )
                else
                  for (final ExamAssetDto item in _items) ...<Widget>[
                    Card(
                      child: ListTile(
                        title: Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${item.kind} · ${item.uploaderName} · '
                          '${(item.sizeBytes / 1024).toStringAsFixed(0)} KB',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (String v) {
                            if (v == 'open') unawaited(_open(item));
                            if (v == 'hard') unawaited(_markHard(item));
                          },
                          itemBuilder: (_) => const <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'open',
                              child: Text('打开 / 下载'),
                            ),
                            PopupMenuItem<String>(
                              value: 'hard',
                              child: Text('记入错题本'),
                            ),
                          ],
                        ),
                        onTap: () => unawaited(_open(item)),
                      ),
                    ),
                  ],
              ],
            ),
    );
  }
}
