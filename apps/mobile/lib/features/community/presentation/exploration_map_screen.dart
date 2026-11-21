import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'adventure_ui.dart';
import 'publish_learning_result_screen.dart';
import 'study_desk_screen.dart';

const _chapterPath = '/community/explore/cafe';
const _levels = [
  (
    title: '看懂菜单',
    prompt:
        '菜单：Small coffee £2 · Large coffee £3 · Small tea £2。\n你有 £2，想喝咖啡。选哪一款？',
    answers: ['Large coffee', 'Small coffee', 'Small tea'],
    correct: 1,
    explanation: 'Small coffee 同时满足饮品和预算要求。',
    ability: '读懂价目与预算',
  ),
  (
    title: '开口点单',
    prompt: '店员问 “What can I get for you?” 你想点一杯小杯咖啡外带。',
    answers: [
      'A small coffee to go, please.',
      'A large coffee to go, please.',
      'A small coffee for here, please.',
    ],
    correct: 0,
    explanation: 'To go 表示外带。选好后可以把整句话读一遍。',
    ability: '点单 + 外带',
  ),
  (
    title: '修改订单',
    prompt: '你已经点了咖啡，想把牛奶换成燕麦奶。怎么说？',
    answers: [
      'Could I get another coffee?',
      'Could I have it without milk?',
      'Could I get that with oat milk instead?',
    ],
    correct: 2,
    explanation: 'With oat milk instead 表示改用燕麦奶。',
    ability: '改规格 / 替换配料',
  ),
  (
    title: '售罄挑战',
    prompt: '店员说 “Sorry, we’re out of coffee.” 你想改成小杯茶，并确认外带。',
    answers: [
      'I’ll have a small tea to go, then.',
      'I’ll wait for the coffee.',
      'A small tea for here, please.',
    ],
    correct: 0,
    explanation: 'Then 在这里表示「那就」，to go 确认外带。',
    ability: '应变换单',
  ),
];

int? explorationLevel(String? path) {
  for (int index = 0; index < _levels.length; index++) {
    if (path == '$_chapterPath/${index + 1}') return index;
  }
  return null;
}

class ExplorationMapScreen extends ConsumerWidget {
  const ExplorationMapScreen({super.key, this.sharedLevel});

  final int? sharedLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final profile = session.isLoggedIn ? 'account:${session.email}' : 'guest';
    return _CafeMap(
      key: ValueKey(profile),
      profile: profile,
      sharedLevel: sharedLevel,
    );
  }
}

class _CafeMap extends StatefulWidget {
  const _CafeMap({super.key, required this.profile, this.sharedLevel});

  final String profile;
  final int? sharedLevel;

  @override
  State<_CafeMap> createState() => _CafeMapState();
}

class _CafeMapState extends State<_CafeMap> {
  final _preferences = SharedPreferencesAsync();
  Set<int>? _completed;
  bool _failed = false;

  String _key(int index) =>
      'community.exploration.cafe.v1.${widget.profile}.$index';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final flags = await Future.wait([
        for (int index = 0; index < _levels.length; index++)
          _preferences.getBool(_key(index)),
      ]);
      if (mounted) {
        setState(
          () => _completed = {
            for (int index = 0; index < flags.length; index++)
              if (flags[index] == true) index,
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _open(int index) {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            builder: (_) => _CafeLevel(
              index: index,
              onComplete: () async {
                await _preferences.setBool(_key(index), true);
                if (mounted) setState(() => _completed?.add(index));
              },
            ),
          ),
        )
        .then((_) {
          if (mounted) _load();
        });
  }

  int _nextIndex(Set<int> completed) {
    for (int i = 0; i < _levels.length; i++) {
      if (!completed.contains(i)) return i;
    }
    return _levels.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final completed = _completed;
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        title: const Text('街角咖啡店'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const StudyDeskScreen(),
              ),
            ),
            child: const Text('学习桌'),
          ),
        ],
      ),
      body: _failed
          ? Center(
              child: HubChunkyButton(
                label: '重新读取进度',
                onPressed: _load,
                icon: Icons.refresh_rounded,
              ),
            )
          : completed == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: AppDesignTokens.isDark
                              ? const <Color>[
                                  AdventurePalette.cafeWarm,
                                  Color(0xFF12141A),
                                ]
                              : const <Color>[
                                  Color(0xFFFFF3DE),
                                  Color(0xFFFFE2B8),
                                ],
                        ),
                        border: Border.all(
                          color: AdventurePalette.pathAmber.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '章节路线',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '点单 · 外带 · 改规格',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '个人通关永久保留 · 同桌只是加分',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          AdventurePathStrip(
                            nodeCount: _levels.length,
                            clearedCount: completed.length,
                            currentIndex: _nextIndex(completed),
                          ),
                          const SizedBox(height: 14),
                          HubChunkyButton(
                            label: completed.length >= _levels.length
                                ? '重温本章'
                                : '继续第 ${_nextIndex(completed) + 1} 关',
                            onPressed: () => _open(_nextIndex(completed)),
                          ),
                        ],
                      ),
                    ),
                    if (widget.sharedLevel case final int index) ...<Widget>[
                      const SizedBox(height: 12),
                      QuestFeedCard(
                        title: '练同一关 · ${_levels[index].title}',
                        meta: '来自成果卡 · ${_levels[index].ability}',
                        badge: '跟练',
                        accent: AdventurePalette.pathAmber,
                        onPlay: () => _open(index),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      '关卡节点',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (int index = 0; index < _levels.length; index++) ...<
                        Widget>[
                      _LevelNodeTile(
                        index: index,
                        title: _levels[index].title,
                        ability: _levels[index].ability,
                        cleared: completed.contains(index),
                        current: index == _nextIndex(completed) &&
                            !completed.contains(index),
                        onTap: () => _open(index),
                      ),
                      if (index < _levels.length - 1)
                        Center(
                          child: Container(
                            width: 3,
                            height: 18,
                            color: completed.contains(index)
                                ? AppDesignTokens.brandGreen
                                : AppDesignTokens.borderGray,
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }
}

class _LevelNodeTile extends StatelessWidget {
  const _LevelNodeTile({
    required this.index,
    required this.title,
    required this.ability,
    required this.cleared,
    required this.current,
    required this.onTap,
  });

  final int index;
  final String title;
  final String ability;
  final bool cleared;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = cleared
        ? AppDesignTokens.brandGreen
        : current
            ? AdventurePalette.pathAmber
            : AppDesignTokens.borderGray;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: current ? AdventurePalette.pathAmber : accent,
              width: current ? 2.5 : 1,
            ),
            boxShadow: AppDesignTokens.toyCardShadow,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: current
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x66FFC800),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: cleared
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: current
                              ? const Color(0xFF3A2A00)
                              : Colors.white,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cleared
                          ? '已通关 · 可重练 · $ability'
                          : current
                              ? '当前关 · $ability'
                              : '第 ${index + 1} 站 · $ability',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppDesignTokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CafeLevel extends StatefulWidget {
  const _CafeLevel({required this.index, required this.onComplete});

  final int index;
  final Future<void> Function() onComplete;

  @override
  State<_CafeLevel> createState() => _CafeLevelState();
}

class _CafeLevelState extends State<_CafeLevel> {
  bool _saving = false;
  bool _complete = false;
  String? _feedback;

  Future<void> _answer(int index) async {
    final level = _levels[widget.index];
    if (index != level.correct) {
      setState(() => _feedback = '再看看顾客的要求，试一次。');
      return;
    }
    setState(() {
      _saving = true;
      _feedback = null;
    });
    try {
      await widget.onComplete();
      if (mounted) setState(() => _complete = true);
    } catch (_) {
      if (mounted) setState(() => _feedback = '进度保存失败，请重新提交。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = _levels[widget.index];
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(title: Text('第 ${widget.index + 1} 关 · ${level.title}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppDesignTokens.toyCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '能力目标 · ${level.ability}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AdventurePalette.pathAmberDeep,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  level.prompt,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_complete) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppDesignTokens.brandGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppDesignTokens.brandGreen),
              ),
              child: Text(
                '通关！本关练过：${level.ability}\n${level.explanation}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            HubChunkyButton(
              label: '发布成果卡，邀人练同一关',
              icon: Icons.ios_share_rounded,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => PublishLearningResultScreen(
                    initialText:
                        '我完成了街角咖啡店的「${level.title}」关卡（${level.ability}）。一起来练吧！',
                    challengePath: '$_chapterPath/${widget.index + 1}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回地图'),
            ),
          ] else ...<Widget>[
            for (int index = 0; index < level.answers.length; index++) ...<
                Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: AppDesignTokens.appWhite,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _saving ? null : () => _answer(index),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppDesignTokens.borderGray),
                      ),
                      child: Text(
                        level.answers[index],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (_saving) const LinearProgressIndicator(),
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _feedback!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.orange,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
