import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../data/exam_error_book_store.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_pack.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_registry.dart';
import '../domain/exam_weakness.dart';
import 'exam_pack_provider.dart';
import 'exam_profile_provider.dart';
import 'exam_weakness_provider.dart';

const Color _kExamHeroDark = Color(0xFF1A2332);

class ExamHomeScreen extends ConsumerWidget {
  const ExamHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final ExamFamily? family = profile.family;
    final ExamPack? pack = ref.watch(examPackProvider).asData?.value;
    final ExamWeaknessReport? weakness = ref.watch(examWeaknessProvider);
    final Map<String, int> progress = family == null
        ? const <String, int>{}
        : ref.watch(examProgressProvider).forFamily(family.id);
    final int errorCount = family == null
        ? 0
        : ref
            .watch(examErrorBookProvider)
            .where(
              (ExamErrorItem e) =>
                  e.familyId == family.id || e.familyId.isEmpty,
            )
            .length;
    final int practiced = progress['practiced'] ?? 0;
    final int correct = progress['correct'] ?? 0;
    final double accuracy = practiced <= 0 ? 0 : correct / practiced;

    return PadScaffold(
      currentDestination: AppNavDestination.exam,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '考试备考',
        description: family == null
            ? '先选目标，再给今日备考与薄弱诊断'
            : '${family.label} · CEFR ${profile.resolvedCefr}'
                '${_countdownSuffix(profile.targetDateIso)}',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Text(
            'ACQUIRE · EXAM',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppDesignTokens.primaryBlueDark,
            ),
          ),
          const SizedBox(height: 12),
          if (family == null)
            _EmptyTargetBody(ref: ref)
          else ...<Widget>[
            _HeroTargetCard(
              family: family,
              practiced: practiced,
              errorCount: errorCount,
              accuracy: accuracy,
            ),
            if (pack != null && pack.missing) ...<Widget>[
              const SizedBox(height: 10),
              _HintCard(
                text: '当前题包较薄。可从社区下载听力/脚本，或先做专项与错题复习。',
                actionLabel: '社区真题资料',
                onAction: () => context.push('/discover'),
              ),
            ],
            const SizedBox(height: 20),
            _SectionTitle('今日备考'),
            const SizedBox(height: 10),
            _TodayTaskRow(
              family: family,
              errorCount: errorCount,
              weakness: weakness,
            ),
            const SizedBox(height: 20),
            _SectionTitle('薄弱项'),
            const SizedBox(height: 10),
            _WeaknessBars(weakness: weakness),
            const SizedBox(height: 20),
            _SectionTitle('专项与模考'),
            const SizedBox(height: 10),
            _PracticeGrid(
              pack: pack,
              errorCount: errorCount,
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                '更多',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              children: <Widget>[
                _MoreLink(
                  title: '听力专项',
                  onTap: () => context.push('/exam/listening'),
                ),
                _MoreLink(
                  title: '完形填空',
                  onTap: () => context.push('/exam/cloze'),
                ),
                _MoreLink(
                  title: '语法选择',
                  onTap: () => context.push('/exam/grammar'),
                ),
                _MoreLink(
                  title: '阅读专项',
                  onTap: () => context.push('/exam/reading'),
                ),
                _MoreLink(
                  title: '写作训练',
                  onTap: () => context.push('/writing'),
                ),
                _MoreLink(
                  title: '口语练习',
                  onTap: () => context.push('/digital-human'),
                ),
                _MoreLink(
                  title: '社区真题资料',
                  onTap: () => context.push('/discover'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _countdownSuffix(String? iso) {
    final String label = _countdownLabel(iso);
    return label.isEmpty ? '' : ' · $label';
  }
}

String _countdownLabel(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '';
  final DateTime? day = DateTime.tryParse(iso.trim());
  if (day == null) return '';
  final DateTime today = DateTime.now();
  final DateTime a = DateTime(today.year, today.month, today.day);
  final DateTime b = DateTime(day.year, day.month, day.day);
  final int diff = b.difference(a).inDays;
  if (diff > 0) return '距考 $diff 天';
  if (diff == 0) return '今天考试';
  return '已过考 ${-diff} 天';
}

class _EmptyTargetBody extends StatelessWidget {
  const _EmptyTargetBody({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '先选目标，再给今日备考\n与薄弱诊断。日常习得不变。',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.45,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        _EntrancePickCard(
          kicker: 'K12 · 初中',
          title: '中考英语',
          subtitle: '地区卷备考 · 听读词语法',
          dark: false,
          onTap: () => ref.read(examProfileProvider.notifier).setFamily('zhongkao'),
        ),
        const SizedBox(height: 12),
        _EntrancePickCard(
          kicker: 'K12 · 高中',
          title: '高考英语',
          subtitle: '估分档次 · 限时客观卷',
          dark: true,
          onTap: () => ref.read(examProfileProvider.notifier).setFamily('gaokao'),
        ),
        const SizedBox(height: 20),
        _SectionTitle('更多目标'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double gap = 10;
            final double chipWidth = (constraints.maxWidth - gap * 2) / 3;
            const List<({String label, String route})> items =
                <({String label, String route})>[
              (label: '小学', route: '/exam/select?track=k12'),
              (label: '初中', route: '/exam/select?track=k12'),
              (label: '高中', route: '/exam/select?track=k12'),
              (label: '四六级', route: '/exam/select?track=cet'),
              (
                label: '考研',
                route: '/exam/select?track=postgraduate&family=kaoyan',
              ),
              (label: '托福', route: '/exam/select?track=toefl&family=toefl'),
              (label: '雅思', route: '/exam/select?track=ielts'),
              (
                label: 'KET',
                route: '/exam/select?track=cambridge&family=ket',
              ),
              (
                label: 'PET',
                route: '/exam/select?track=cambridge&family=pet',
              ),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (final ({String label, String route}) item in items)
                  SizedBox(
                    width: chipWidth,
                    child: _MoreTargetChip(
                      label: item.label,
                      onTap: () => context.push(item.route),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignTokens.brandGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => context.push('/exam/select'),
            child: const Text(
              '打开完整选题',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _EntrancePickCard extends StatelessWidget {
  const _EntrancePickCard({
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.dark,
    required this.onTap,
  });

  final String kicker;
  final String title;
  final String subtitle;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: dark ? _kExamHeroDark : AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                kicker,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.brandGreen,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: dark ? Colors.white : AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: dark
                      ? const Color(0xFFB8BECB)
                      : AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreTargetChip extends StatelessWidget {
  const _MoreTargetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroTargetCard extends StatelessWidget {
  const _HeroTargetCard({
    required this.family,
    required this.practiced,
    required this.errorCount,
    required this.accuracy,
  });

  final ExamFamily family;
  final int practiced;
  final int errorCount;
  final double accuracy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        color: _kExamHeroDark,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '当前目标',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9AA0AE),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  family.label,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '练习 $practiced · 错题 $errorCount · '
                  '正确率 ${(accuracy * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB8BECB),
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignTokens.brandGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () => context.push('/exam/select'),
            child: const Text(
              '更换',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayTaskRow extends StatelessWidget {
  const _TodayTaskRow({
    required this.family,
    required this.errorCount,
    required this.weakness,
  });

  final ExamFamily family;
  final int errorCount;
  final ExamWeaknessReport? weakness;

  @override
  Widget build(BuildContext context) {
    final List<_TaskSpec> tasks = <_TaskSpec>[];
    if (errorCount > 0) {
      tasks.add(
        _TaskSpec(
          icon: Icons.replay_rounded,
          iconColor: AppDesignTokens.orange,
          title: '错题复习',
          subtitle: '$errorCount 条 · FSRS',
          route: '/exam/errorbook',
        ),
      );
    }
    final ExamSkillWeakness? weak = weakness?.topWeak;
    if (weak != null && weak.weakScore >= 0.25) {
      tasks.add(
        _TaskSpec(
          icon: Icons.bolt_rounded,
          iconColor: AppDesignTokens.primaryBlueDark,
          title: '薄弱 · ${weak.label}',
          subtitle: '专项摸底',
          route: weak.route,
        ),
      );
    }
    if (tasks.length < 2) {
      tasks.add(
        _TaskSpec(
          icon: Icons.headphones_outlined,
          iconColor: AppDesignTokens.primaryBlueDark,
          title: '听力热身',
          subtitle: examWarmUpSubtitle(family),
          route: '/exam/listening',
        ),
      );
    }
    if (tasks.length == 1) {
      tasks.add(
        _TaskSpec(
          icon: Icons.fitness_center_rounded,
          iconColor: AppDesignTokens.brandGreenDark,
          title: '专项训练',
          subtitle: '听 / 读 / 词',
          route: '/exam/practice',
        ),
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: _TaskCard(spec: tasks[0])),
        const SizedBox(width: 12),
        Expanded(child: _TaskCard(spec: tasks[1])),
      ],
    );
  }
}

class _TaskSpec {
  const _TaskSpec({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String route;
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.spec});

  final _TaskSpec spec;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(spec.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(spec.icon, color: spec.iconColor, size: 22),
              const SizedBox(height: 14),
              Text(
                spec.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                spec.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeaknessBars extends StatelessWidget {
  const _WeaknessBars({required this.weakness});

  final ExamWeaknessReport? weakness;

  @override
  Widget build(BuildContext context) {
    final List<ExamSkillWeakness> items =
        weakness?.actionable.take(3).toList(growable: false) ??
            const <ExamSkillWeakness>[];
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          '暂无明显薄弱项。先做一组听力或词汇专项，错题会出现在这里。',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: AppDesignTokens.textSecondary,
          ),
        ),
      );
    }

    final List<Color> colors = <Color>[
      AppDesignTokens.orange,
      AppDesignTokens.primaryBlueDark,
      AppDesignTokens.textSecondary,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 14),
            InkWell(
              onTap: () => context.push(items[i].route),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 40,
                    child: Text(
                      items[i].label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: colors[i % colors.length],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: items[i].weakScore.clamp(0.08, 1),
                        minHeight: 10,
                        color: colors[i % colors.length],
                        backgroundColor: AppDesignTokens.softGray,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(items[i].weakScore * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors[i % colors.length],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PracticeGrid extends StatelessWidget {
  const _PracticeGrid({required this.pack, required this.errorCount});

  final ExamPack? pack;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    final String mockSub = pack == null
        ? '计时客观题'
        : '${pack!.mockMinutes} 分钟 · ${pack!.mockSections.join(" / ")}';
    final List<_GridItem> items = <_GridItem>[
      _GridItem(
        title: '专项训练',
        subtitle: '听 / 读 / 词 / 语法',
        route: '/exam/practice',
      ),
      _GridItem(
        title: '限时客观卷',
        subtitle: mockSub,
        route: '/exam/mock',
      ),
      _GridItem(
        title: '错题本',
        subtitle: errorCount == 0 ? '筛选 · 再练' : '$errorCount 条 · 筛选再练',
        route: '/exam/errorbook',
      ),
      _GridItem(
        title: '学习报告',
        subtitle: '正确率 · 薄弱',
        route: '/exam/report',
      ),
    ];

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _GridCard(item: items[0])),
            const SizedBox(width: 12),
            Expanded(child: _GridCard(item: items[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: _GridCard(item: items[2])),
            const SizedBox(width: 12),
            Expanded(child: _GridCard(item: items[3])),
          ],
        ),
      ],
    );
  }
}

class _GridItem {
  const _GridItem({
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String route;
}

class _GridCard extends StatelessWidget {
  const _GridCard({required this.item});

  final _GridItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(item.route),
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
    );
  }
}

class _MoreLink extends StatelessWidget {
  const _MoreLink({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE2A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
