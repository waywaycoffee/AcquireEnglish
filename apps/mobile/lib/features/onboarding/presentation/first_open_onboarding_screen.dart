import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../community/presentation/adventure_ui.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/onboarding_profile.dart';
import 'auth_guide_keys.dart';
import 'focus_recommendation.dart';
import 'onboarding_provider.dart';

String _shortRecommendTitle(String raw, {int maxChars = 36}) {
  final String text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars).trimRight()}…';
}

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
                  _FocusPage(
                    profile: profile,
                    onChanged: (OnboardingProfile next) => ref
                        .read(onboardingProvider.notifier)
                        .update((_) => next),
                    onNext: () {
                      if (profile.focusId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请选择一个学习重点')),
                        );
                        return;
                      }
                      _go(1);
                    },
                  ),
                  _FilterPage(
                    profile: profile,
                    onChanged: (OnboardingProfile next) => ref
                        .read(onboardingProvider.notifier)
                        .update((_) => next),
                    onBack: () => _go(0),
                    onNext: () {
                      if (profile.interestIds.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请至少选一个兴趣领域')),
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
                    onStart: (String route) {
                      final String target =
                          ref.read(focusRecommendationProvider)?.route ?? route;
                      // Do not push a module route over auth-guide — that
                      // skipped the post-register source guide in practice.
                      if (!readAuthSourceGuideCompletedSync()) {
                        context.go('/onboarding/auth-guide');
                        return;
                      }
                      context.go('/home');
                      context.push(target);
                    },
                    onHome: () => context.go('/home'),
                    recommendation: ref.watch(focusRecommendationProvider),
                    onMap: () {
                      if (!readAuthSourceGuideCompletedSync()) {
                        context.go('/onboarding/auth-guide');
                        return;
                      }
                      context.go('/discover');
                      context.push('/explore');
                    },
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

class _FocusPage extends StatelessWidget {
  const _FocusPage({
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
          '你现在最想重点练什么？',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '单选一项作为首页优先推荐。其他模块和社区地图照常可用，之后也能在设置里更换。',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        for (final LearningFocus focus in kLearningFocuses) ...<Widget>[
          _FocusTile(
            focus: focus,
            selected: profile.focusId == focus.id,
            onTap: () => onChanged(profile.copyWith(focusId: focus.id)),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        HubChunkyButton(label: '下一步', onPressed: onNext),
      ],
    );
  }
}

class _FocusTile extends StatelessWidget {
  const _FocusTile({
    required this.focus,
    required this.selected,
    required this.onTap,
  });

  final LearningFocus focus;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AdventurePalette.pathAmber
                  : AppDesignTokens.borderGray,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected
                    ? AdventurePalette.pathAmber
                    : AppDesignTokens.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      focus.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      focus.homeBlurb,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPage extends StatelessWidget {
  const _FilterPage({
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
          '兴趣和年龄段',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '用来在你的重点模块里筛选场景和素材，例如「阅读 + 科技」会优先推入门科技短文。',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '兴趣领域（可多选）',
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
          '自评给出初始难度。音节与自然拼读只决定相关练习里是否提供可跳过的提示。',
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
    required this.onMap,
    required this.recommendation,
  });

  final OnboardingProfile profile;
  final ValueChanged<String> onStart;
  final VoidCallback onHome;
  final VoidCallback onMap;
  final FocusRecommendation? recommendation;

  @override
  Widget build(BuildContext context) {
    final LearningFocus? focus = profile.focus;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: <Widget>[
        Text(
          '好，按你的重点开始',
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
        if (focus != null) ...<Widget>[
          Text(
            '首页优先 · ${focus.label}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            focus.homeBlurb,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          if (recommendation != null &&
              recommendation!.title.trim().isNotEmpty &&
              recommendation!.title.trim() != focus.homeBlurb) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '推荐起点 · ${_shortRecommendTitle(recommendation!.title)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
                height: 1.35,
              ),
            ),
            if (recommendation!.subtitle.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _shortRecommendTitle(recommendation!.subtitle, maxChars: 48),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppDesignTokens.textSecondary.withValues(alpha: 0.85),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 14),
          HubChunkyButton(
            label: focus.startLabel,
            onPressed: () => onStart(recommendation?.route ?? focus.route),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          '社区地图对所有人开放，关卡规则一致；随时可去玩，也可在设置里更换重点。',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onMap,
          child: const Text('先去社区地图看看'),
        ),
        if (profile.warmUpRoutes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Text(
            '相关练习会带可跳过提示',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (profile.showSyllableHints)
            const Text('· 音节拆读提示（可跳过）'),
          if (profile.showPhonicsHints)
            const Text('· 自然拼读提示（可跳过）'),
        ],
        const SizedBox(height: 16),
        TextButton(onPressed: onHome, child: const Text('先去首页自由选课')),
      ],
    );
  }
}
