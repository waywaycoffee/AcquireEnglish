import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../community/presentation/adventure_ui.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/onboarding_profile.dart';
import 'onboarding_provider.dart';

class FirstOpenOnboardingScreen extends ConsumerStatefulWidget {
  const FirstOpenOnboardingScreen({super.key});

  @override
  ConsumerState<FirstOpenOnboardingScreen> createState() =>
      _FirstOpenOnboardingScreenState();
}

class _FirstOpenOnboardingScreenState
    extends ConsumerState<FirstOpenOnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _go(int index) async {
    setState(() => _index = index);
    await _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(onboardingProvider.notifier).completeAndApply();
      if (!mounted) return;
      setState(() => _index = 3);
      await _pages.animateToPage(
        3,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OnboardingProfile profile = ref.watch(onboardingProvider);
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: <Widget>[
                  Text(
                    _index >= 3 ? '为你准备好了' : '第 ${_index + 1} / 3 步',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (_index < 3)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await ref
                                  .read(onboardingProvider.notifier)
                                  .skipForNow();
                              if (context.mounted) {
                                context.go('/home');
                              }
                            },
                      child: const Text('跳过'),
                    ),
                ],
              ),
            ),
            if (_index < 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / 3,
                    minHeight: 8,
                    color: AppDesignTokens.brandGreen,
                    backgroundColor: AppDesignTokens.softGray,
                  ),
                ),
              ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  _InterestPage(
                    profile: profile,
                    onChanged: (OnboardingProfile next) => ref
                        .read(onboardingProvider.notifier)
                        .update((_) => next),
                    onNext: () {
                      if (profile.interestIds.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请至少选一个兴趣')),
                        );
                        return;
                      }
                      _go(1);
                    },
                  ),
                  _ModePage(
                    profile: profile,
                    onChanged: (OnboardingProfile next) => ref
                        .read(onboardingProvider.notifier)
                        .update((_) => next),
                    onBack: () => _go(0),
                    onNext: () {
                      if (profile.modeIds.isEmpty ||
                          profile.primaryModeId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请选择学习方式，并指定今天先试哪一个')),
                        );
                        return;
                      }
                      _go(2);
                    },
                  ),
                  _AbilityPage(
                    profile: profile,
                    onChanged: (OnboardingProfile next) => ref
                        .read(onboardingProvider.notifier)
                        .update((_) => next),
                    onBack: () => _go(1),
                    onNext: _busy
                        ? null
                        : () {
                            if (profile.abilityId == null ||
                                profile.canSyllableSplit == null ||
                                profile.learnedPhonics == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('请完成自评与两个小问题'),
                                ),
                              );
                              return;
                            }
                            _finish();
                          },
                  ),
                  _ResultPage(
                    profile: profile,
                    onStart: (String route) => context.go(route),
                    onHome: () => context.go('/home'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterestPage extends StatelessWidget {
  const _InterestPage({
    required this.profile,
    required this.onChanged,
    required this.onNext,
  });

  final OnboardingProfile profile;
  final ValueChanged<OnboardingProfile> onChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: <Widget>[
        Text(
          '你喜欢什么？',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '兴趣可多选。年龄段可选，用来筛选更合适的场景和素材。',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            for (final OnboardingInterest item in kOnboardingInterests)
              FilterChip(
                label: Text(item.label),
                selected: profile.interestIds.contains(item.id),
                onSelected: (bool selected) {
                  final List<String> next =
                      List<String>.from(profile.interestIds);
                  if (selected) {
                    next.add(item.id);
                  } else {
                    next.remove(item.id);
                  }
                  onChanged(profile.copyWith(interestIds: next));
                },
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '年龄段（可跳过）',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            for (final ({String id, String label}) band in kOnboardingAgeBands)
              ChoiceChip(
                label: Text(band.label),
                selected: profile.ageBandId == band.id,
                onSelected: (_) => onChanged(
                  profile.copyWith(ageBandId: band.id),
                ),
              ),
            ChoiceChip(
              label: const Text('先跳过'),
              selected: profile.ageBandId == null,
              onSelected: (_) =>
                  onChanged(profile.copyWith(clearAgeBand: true)),
            ),
          ],
        ),
        const SizedBox(height: 28),
        HubChunkyButton(label: '下一步', onPressed: onNext),
      ],
    );
  }
}

class _ModePage extends StatelessWidget {
  const _ModePage({
    required this.profile,
    required this.onChanged,
    required this.onBack,
    required this.onNext,
  });

  final OnboardingProfile profile;
  final ValueChanged<OnboardingProfile> onChanged;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: <Widget>[
        Text(
          '你想怎么学？',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '可多选。再告诉我：今天想先试哪一个？',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        for (final OnboardingMode mode in kOnboardingModes) ...<Widget>[
          _ModeTile(
            mode: mode,
            selected: profile.modeIds.contains(mode.id),
            primary: profile.primaryModeId == mode.id,
            onToggle: (bool selected) {
              final List<String> next = List<String>.from(profile.modeIds);
              if (selected) {
                next.add(mode.id);
              } else {
                next.remove(mode.id);
              }
              String? primary = profile.primaryModeId;
              if (!selected && primary == mode.id) {
                primary = next.isEmpty ? null : next.first;
              }
              if (selected && primary == null) primary = mode.id;
              onChanged(
                profile.copyWith(modeIds: next, primaryModeId: primary),
              );
            },
            onPrimary: () {
              final List<String> next = List<String>.from(profile.modeIds);
              if (!next.contains(mode.id)) next.add(mode.id);
              onChanged(
                profile.copyWith(modeIds: next, primaryModeId: mode.id),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                child: const Text('上一步'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: HubChunkyButton(label: '下一步', onPressed: onNext),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.primary,
    required this.onToggle,
    required this.onPrimary,
  });

  final OnboardingMode mode;
  final bool selected;
  final bool primary;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onToggle(!selected),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: primary
                  ? AdventurePalette.pathAmber
                  : selected
                      ? AppDesignTokens.brandGreen
                      : AppDesignTokens.borderGray,
              width: primary || selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: selected,
                onChanged: (bool? v) => onToggle(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      mode.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    Text(
                      mode.blurb,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onPrimary,
                child: Text(primary ? '今天先试 ✓' : '今天先试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AbilityPage extends StatelessWidget {
  const _AbilityPage({
    required this.profile,
    required this.onChanged,
    required this.onBack,
    required this.onNext,
  });

  final OnboardingProfile profile;
  final ValueChanged<OnboardingProfile> onChanged;
  final VoidCallback onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: <Widget>[
        Text(
          '你现在能做到什么？',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '自评给出初始难度。音节与自然拼读用于提示或可选热身。',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        for (final ({String id, String label, String level}) row
            in kOnboardingAbility)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChoiceChip(
              label: Text(row.label),
              selected: profile.abilityId == row.id,
              onSelected: (_) =>
                  onChanged(profile.copyWith(abilityId: row.id)),
            ),
          ),
        const SizedBox(height: 18),
        _YesNoRow(
          question: '会按音节拆读单词吗？',
          value: profile.canSyllableSplit,
          onChanged: (bool value) =>
              onChanged(profile.copyWith(canSyllableSplit: value)),
        ),
        const SizedBox(height: 12),
        _YesNoRow(
          question: '学过自然拼读吗？',
          value: profile.learnedPhonics,
          onChanged: (bool value) =>
              onChanged(profile.copyWith(learnedPhonics: value)),
        ),
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                child: const Text('上一步'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: HubChunkyButton(
                label: '查看我的起点',
                onPressed: onNext,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _YesNoRow extends StatelessWidget {
  const _YesNoRow({
    required this.question,
    required this.value,
    required this.onChanged,
  });

  final String question;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            question,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              ChoiceChip(
                label: const Text('会 / 学过'),
                selected: value ?? false,
                onSelected: (_) => onChanged(true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('还不会 / 没学过'),
                selected: value == false,
                onSelected: (_) => onChanged(false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultPage extends StatelessWidget {
  const _ResultPage({
    required this.profile,
    required this.onStart,
    required this.onHome,
  });

  final OnboardingProfile profile;
  final ValueChanged<String> onStart;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final OnboardingMode? primary = profile.primaryMode;
    final List<OnboardingMode> others = profile.otherModes;
    final List<String> warmUps = profile.warmUpRoutes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: <Widget>[
        Text(
          '好，按你的节奏开始',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '初始难度 · ${profile.resolvedLevel}'
          '${profile.ageBandId == null ? '' : ' · 已记录年龄段'}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        if (primary != null) ...<Widget>[
          Text(
            '今天先试 · ${primary.label}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            primary.blurb,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          HubChunkyButton(
            label: '开始 ${primary.label}',
            onPressed: () => onStart(primary.route),
          ),
        ],
        if (others.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Text(
            '也保留了这些入口',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final OnboardingMode mode in others)
                ActionChip(
                  label: Text(mode.label),
                  onPressed: () => onStart(mode.route),
                ),
            ],
          ),
        ],
        if (warmUps.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Text(
            '可选热身',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (warmUps.contains('/learn/ipa'))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('国际音标提示'),
              subtitle: const Text('你标记了还不熟悉按音节拆读'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onStart('/learn/ipa'),
            ),
          if (warmUps.contains('/learn/phonics'))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自然拼读热身'),
              subtitle: const Text('你标记了还没学过自然拼读'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onStart('/learn/phonics'),
            ),
        ],
        const SizedBox(height: 16),
        TextButton(onPressed: onHome, child: const Text('先去首页逛逛')),
      ],
    );
  }
}
