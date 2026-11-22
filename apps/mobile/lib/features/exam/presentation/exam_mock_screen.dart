import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/exam_pack.dart';
import '../domain/exam_profile.dart';
import 'exam_pack_provider.dart';
import 'exam_profile_provider.dart';

class ExamMockScreen extends ConsumerWidget {
  const ExamMockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final AsyncValue<ExamPack?> packAsync = ref.watch(examPackProvider);

    if (profile.family == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('限时客观卷')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '限时客观卷需先选择考试目标。',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/exam/select'),
                child: const Text('选择考试目标'),
              ),
            ],
          ),
        ),
      );
    }

    final ExamPack? pack = packAsync.asData?.value;
    final int minutes = pack?.mockMinutes ?? 60;
    final String sections =
        (pack?.mockSections ?? const <String>['vocab', 'listening', 'reading'])
            .where((String s) => s != 'writing' && s != 'speaking')
            .join(' → ');

    return Scaffold(
      appBar: AppBar(title: const Text('限时客观卷')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '${profile.family!.label} · 限时客观卷',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              pack == null
                  ? '加载题包后组卷：词汇 / 听力 / 阅读等客观题。写作与口语不在本卷内，请用专项。'
                  : '${pack.title}\n时长约 $minutes 分钟\n科目：$sections\n'
                      '这不是完整真题卷；写/说请去专项。错题进错题本并回流统一 FSRS。',
              style: TextStyle(
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: pack == null
                  ? null
                  : () => context.push('/exam/session?skill=mock&mock=1'),
              child: Text(pack == null ? '题包加载中…' : '开始限时客观卷'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push('/writing'),
              child: const Text('去做写作专项'),
            ),
            OutlinedButton(
              onPressed: () => context.push('/digital-human'),
              child: const Text('去做口语专项'),
            ),
          ],
        ),
      ),
    );
  }
}
