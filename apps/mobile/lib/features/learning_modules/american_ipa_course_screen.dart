import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../library/presentation/library_catalog_provider.dart';
import '../shared/presentation/pad/app_design_tokens.dart';
import 'american_ipa_course.dart';

/// Home「美式音标」入口：20 集慢速跟读（BV1iy4y1v7WQ）。
class AmericanIpaCourseScreen extends ConsumerStatefulWidget {
  const AmericanIpaCourseScreen({super.key});

  @override
  ConsumerState<AmericanIpaCourseScreen> createState() =>
      _AmericanIpaCourseScreenState();
}

class _AmericanIpaCourseScreenState
    extends ConsumerState<AmericanIpaCourseScreen> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCatalog());
  }

  Future<void> _ensureCatalog() async {
    try {
      await ref
          .read(libraryCatalogProvider.notifier)
          .ensureAmericanIpaCourse();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AmericanIpaCourse.kTitle)),
      body: !_ready && _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: <Widget>[
                Text(
                  '20 集美式音标慢速跟读',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '来源 B站 ${AmericanIpaCourse.kBvid} · 点进单集后用播放器「跟读」即可。'
                  '视频不进 APK。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppDesignTokens.textSecondary,
                        height: 1.4,
                      ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text('目录写入失败：$_error', style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                ...AmericanIpaCourse.lessons.map((AmericanIpaLesson lesson) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppDesignTokens.brandGreenDark.withValues(alpha: 0.12),
                        child: Text(
                          lesson.symbol,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      title: Text(
                        '第 ${lesson.page} 课 · /${lesson.symbol}/',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('慢速跟读练习 + 讲解'),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () {
                        final String id =
                            AmericanIpaCourse.episodeIdForPage(lesson.page);
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
