import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../domain/course_plan.dart';
import '../domain/oral_core_series.dart';
import 'course_plan_provider.dart';
import 'oral_core_series_provider.dart';
// activateOralCoreSeries / setDailyLessons live on CoursePlanNotifier.

class OralCoreCourseScreen extends ConsumerStatefulWidget {
  const OralCoreCourseScreen({super.key});

  @override
  ConsumerState<OralCoreCourseScreen> createState() =>
      _OralCoreCourseScreenState();
}

class _OralCoreCourseScreenState extends ConsumerState<OralCoreCourseScreen> {
  int _dailyLessons = 1;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<OralCoreSeries> seriesAsync =
        ref.watch(oralCoreSeriesProvider);
    final CoursePlan? active = ref.watch(coursePlanProvider).active;
    final bool isActive = active?.courseId == OralCoreSeries.kSeriesId;

    return Scaffold(
      appBar: AppBar(title: const Text('核心口语 9000 句')),
      body: seriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => Center(child: Text('加载失败：$e')),
        data: (OralCoreSeries series) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: <Widget>[
              Text(
                series.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '官方课 · ${series.lessons.length} 课 · 一集一课\n'
                '来源 B站 ${series.bvid} · 视频不进 APK',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Text('今日学几节', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <int>[1, 2, 3, 5]
                    .map(
                      (int n) => ChoiceChip(
                        label: Text('$n 节'),
                        selected: _dailyLessons == n,
                        onSelected: (_) => setState(() => _dailyLessons = n),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _activate(context, series),
                child: Text(isActive ? '更新今日节数并继续' : '设为今日课程'),
              ),
              if (isActive) ...<Widget>[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('回首页今日路径'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                '课表预览（前 20 课）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...series.lessons.take(20).map(
                (OralCoreLesson l) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    l.lessonNo.toString().padLeft(2, '0'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  title: Text(l.title),
                  subtitle: Text(
                    l.pack.quiz.isNotEmpty ? '含样例题包' : '题包待生产管线补齐',
                  ),
                  onTap: () {
                    final String epId =
                        '${OralCoreSeries.kSeriesId}-${l.page.toString().padLeft(2, '0')}';
                    context.push(
                      '/episodes/${Uri.encodeComponent(epId)}?autoplay=0',
                    );
                  },
                ),
              ),
              if (series.lessons.length > 20)
                Text('… 共 ${series.lessons.length} 课'),
            ],
          );
        },
      ),
    );
  }

  Future<void> _activate(BuildContext context, OralCoreSeries series) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(libraryCatalogProvider.notifier)
          .ensureOralCoreCourse(series);
      await ref.read(coursePlanProvider.notifier).activateOralCoreSeries(
            series,
            dailyLessons: _dailyLessons,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已设为今日课程 · 每日 $_dailyLessons 节',
          ),
        ),
      );
      context.go('/home');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('激活失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
