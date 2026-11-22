import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../library/presentation/library_catalog_provider.dart';
import '../shared/presentation/pad/app_design_tokens.dart';
import 'module_drill_entry_card.dart';
import 'module_screen.dart';
import 'phonics_nessy_course.dart';

/// Home「自然拼读」入口：Nessy 趣味拼读跟读（BV1Qg4mzKENh）。
class PhonicsNessyCourseScreen extends ConsumerStatefulWidget {
  const PhonicsNessyCourseScreen({super.key});

  @override
  ConsumerState<PhonicsNessyCourseScreen> createState() =>
      _PhonicsNessyCourseScreenState();
}

class _PhonicsNessyCourseScreenState
    extends ConsumerState<PhonicsNessyCourseScreen> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCatalog());
  }

  Future<void> _ensureCatalog() async {
    try {
      await ref.read(libraryCatalogProvider.notifier).ensurePhonicsNessyCourse();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(PhonicsNessyCourse.kTitle)),
      body: !_ready && _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: <Widget>[
                Text(
                  '${PhonicsNessyCourse.lessons.length} 集 Nessy 自然拼读跟读',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '来源 B站 ${PhonicsNessyCourse.kBvid} · 点进单集后用播放器「跟读」即可。'
                  '视频不进 APK。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppDesignTokens.textSecondary,
                        height: 1.4,
                      ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    '目录写入失败：$_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 16),
                ModuleDrillEntryCard(
                  title: '基础练习 · 拼读规则与测验',
                  subtitle:
                      '保留原有 ${moduleLessons['phonics']?.length ?? 0} 课字母组合与示范词，'
                      '适合先吃透规则再看 Nessy 动画。',
                  route: '/learn/phonics',
                ),
                Text(
                  '视频跟读',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                ...PhonicsNessyCourse.lessons.map((PhonicsNessyLesson lesson) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppDesignTokens.brandGreenDark
                            .withValues(alpha: 0.12),
                        child: Text(
                          '${lesson.page}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      title: Text(
                        '第 ${lesson.page} 课 · ${lesson.title}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('趣味动画 + 跟读练习'),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () {
                        final String id =
                            PhonicsNessyCourse.episodeIdForPage(lesson.page);
                        context.push(
                          '/episodes/${Uri.encodeComponent(id)}'
                          '?autoplay=1',
                        );
                      },
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
