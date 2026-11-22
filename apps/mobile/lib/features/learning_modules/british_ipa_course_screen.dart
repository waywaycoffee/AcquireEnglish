import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../library/presentation/library_catalog_provider.dart';
import '../shared/presentation/pad/app_design_tokens.dart';
import 'british_ipa_course.dart';
import 'module_drill_entry_card.dart';
import 'module_screen.dart';

/// Home「国际音标」入口：BBC 英式音标跟读（BV127411n7nj，有字幕分集）。
class BritishIpaCourseScreen extends ConsumerStatefulWidget {
  const BritishIpaCourseScreen({super.key});

  @override
  ConsumerState<BritishIpaCourseScreen> createState() =>
      _BritishIpaCourseScreenState();
}

class _BritishIpaCourseScreenState
    extends ConsumerState<BritishIpaCourseScreen> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCatalog());
  }

  Future<void> _ensureCatalog() async {
    try {
      await ref.read(libraryCatalogProvider.notifier).ensureBritishIpaCourse();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(BritishIpaCourse.kTitle)),
      body: !_ready && _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: <Widget>[
                Text(
                  'BBC 英式音标 · 跟读为主',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '来源 B站 ${BritishIpaCourse.kBvid} · 共 ${BritishIpaCourse.lessons.length} 集（已去掉无字幕重复分 P）。'
                  '点进单集后用播放器「跟读」即可。',
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
                  title: '基础练习 · 音素口型与测验',
                  subtitle:
                      '保留原有 ${moduleLessons['ipa']?.length ?? 0} 课 TTS 示范与选择题，'
                      '适合先练口型再跟读视频。',
                  route: '/learn/ipa',
                ),
                Text(
                  '视频跟读',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                ...BritishIpaCourse.lessons.map((BritishIpaLesson lesson) {
                  final String leading = lesson.symbol.isNotEmpty
                      ? lesson.symbol
                      : lesson.page.toString();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppDesignTokens.brandGreenDark
                            .withValues(alpha: 0.12),
                        child: Text(
                          leading,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: lesson.symbol.isEmpty ? 12 : 14,
                          ),
                        ),
                      ),
                      title: Text(
                        lesson.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('跟读练习'),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () {
                        final String id =
                            BritishIpaCourse.episodeIdForPage(lesson.page);
                        context.push(
                          '/episodes/${Uri.encodeComponent(id)}?autoplay=1',
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
