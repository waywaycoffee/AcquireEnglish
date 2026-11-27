import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../navigation/presentation/navigation_destination.dart';
import '../../reading/domain/k12_textbook_catalog.dart';
import '../../reading/presentation/k12_textbook_shelf_screen.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../data/exam_error_book_store.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_pack.dart';
import '../domain/exam_profile.dart';
import '../domain/exam_registry.dart';
import '../domain/exam_weakness.dart';
import 'exam_module_panel.dart';
import 'exam_pack_provider.dart';
import 'exam_profile_provider.dart';
import 'exam_weakness_provider.dart';

const Color _kExamHeroDark = Color(0xFF1A2332);

class ExamHomeScreen extends ConsumerStatefulWidget {
  const ExamHomeScreen({super.key});

  @override
  ConsumerState<ExamHomeScreen> createState() => _ExamHomeScreenState();
}

class _ExamHomeScreenState extends ConsumerState<ExamHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static const List<String> _tabLabels = <String>[
    '教材',
    '听力',
    '阅读',
    '完形',
    '语法',
    '写作',
    '整卷',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            ? '先选目标，再进入教材与专项页签'
            : '${family.label} · CEFR ${profile.resolvedCefr}'
                '${_countdownSuffix(profile.targetDateIso)}',
      ),
      body: family == null
          ? ListView(
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
                _EmptyTargetBody(ref: ref),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _HeroTargetCard(
                    family: family,
                    practiced: practiced,
                    errorCount: errorCount,
                    accuracy: accuracy,
                  ),
                ),
                if (pack != null && pack.missing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _HintCard(
                      text: '官方题包较薄时，可在各页签「生成」或「导入」扩充习题。',
                      actionLabel: '社区真题资料',
                      onAction: () => context.push('/discover'),
                    ),
                  ),
                const SizedBox(height: 8),
                Material(
                  color: AppDesignTokens.softWhite,
                  child: TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: AppDesignTokens.brandGreen,
                    unselectedLabelColor: AppDesignTokens.textSecondary,
                    indicatorColor: AppDesignTokens.brandGreen,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                    tabs: <Widget>[
                      for (final String label in _tabLabels) Tab(text: label),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: <Widget>[
                      K12TextbookShelfScreen(
                        embedded: true,
                        initialGradeId: _isK12GradeFamily(family.id)
                            ? family.id
                            : null,
                        initialStage: _stageForFamily(family.id),
                      ),
                      ExamModulePanel(
                        skill: 'listening',
                        title: '听力模块',
                        blurb:
                            '官方听力脚本 + 选择题；可生成考纲短听力稿，或从社区导入音频资料。',
                        practiceRoute: '/exam/session?skill=listening',
                        importRoute: '/discover',
                        importLabel: '社区听力资料',
                        generateCount: 6,
                      ),
                      ExamModulePanel(
                        skill: 'reading',
                        title: '阅读模块',
                        blurb: '阅读理解专项。可导入真题卷，或按考纲批量生成篇章与题目。',
                        practiceRoute: '/exam/reading',
                        importRoute: '/exam/reading/import',
                        importLabel: '导入阅读卷',
                        generateCount: 4,
                        extraActions: <Widget>[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () =>
                                context.push('/exam/session?skill=reading'),
                            child: const Text('快速刷题（题包）'),
                          ),
                        ],
                      ),
                      ExamModulePanel(
                        skill: 'cloze',
                        title: '完形填空模块',
                        blurb: '完形篇章练习。支持粘贴导入，也可生成符合年级难度的挖空篇。',
                        practiceRoute: '/exam/cloze',
                        importRoute: '/exam/cloze/import',
                        importLabel: '导入完形文本',
                        generateCount: 3,
                      ),
                      ExamModulePanel(
                        skill: 'grammar',
                        title: '语法模块',
                        blurb: '语法选择与考点归类。可按考纲生成大批量选择题入库练习。',
                        practiceRoute: '/exam/grammar',
                        generateCount: 12,
                        extraActions: <Widget>[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () =>
                                context.push('/exam/session?skill=grammar'),
                            child: const Text('开始语法刷题'),
                          ),
                        ],
                      ),
                      ExamModulePanel(
                        skill: 'writing',
                        title: '写作模块',
                        blurb: '写作题干与评分要点。生成后进入写作练习；云端批改走 ECS。',
                        practiceRoute: '/writing',
                        generateCount: 5,
                      ),
                      _MockTabBody(
                        pack: pack,
                        weakness: weakness,
                        family: family,
                        errorCount: errorCount,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _countdownSuffix(String? iso) {
    final String label = _countdownLabel(iso);
    return label.isEmpty ? '' : ' · $label';
  }
}

K12TextbookStage? _stageForFamily(String familyId) {
  if (familyId.startsWith('k12_g')) return K12TextbookStage.primary;
  if (familyId.startsWith('k12_j') || familyId == 'zhongkao') {
    return K12TextbookStage.junior;
  }
  if (familyId.startsWith('k12_s') || familyId == 'gaokao') {
    return K12TextbookStage.senior;
  }
  return null;
}

class _MockTabBody extends StatelessWidget {
  const _MockTabBody({
    required this.pack,
    required this.weakness,
    required this.family,
    required this.errorCount,
  });

  final ExamPack? pack;
  final ExamWeaknessReport? weakness;
  final ExamFamily family;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        Text(
          '整卷考试',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '限时客观卷（词汇 / 听力 / 阅读等）。写作请用「写作」页签；可先生成一批客观题再开考。',
          style: TextStyle(
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        _TodayTaskRow(
          family: family,
          errorCount: errorCount,
          weakness: weakness,
        ),
        const SizedBox(height: 14),
        _WeaknessBars(weakness: weakness),
        const SizedBox(height: 16),
        ExamModulePanel(
          skill: 'mock',
          title: '组卷与生成',
          blurb: pack == null
              ? '题包加载后可开限时卷；也可生成客观题扩充题量。'
              : '${pack!.title} · 约 ${pack!.mockMinutes} 分钟',
          practiceRoute: '/exam/mock',
          generateCount: 15,
          embeddedInScroll: true,
        ),
      ],
    );
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

bool _isK12GradeFamily(String familyId) {
  return familyId.startsWith('k12_g') ||
      familyId.startsWith('k12_j') ||
      familyId.startsWith('k12_s');
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
              (label: '小学', route: '/reading/textbooks?stage=primary'),
              (label: '初中', route: '/reading/textbooks?stage=junior'),
              (label: '高中', route: '/reading/textbooks?stage=senior'),
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
