import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/cafe_adventure.dart';
import 'adventure_ui.dart';
import 'cafe_progress_provider.dart';
import 'publish_learning_result_screen.dart';
import 'study_desk_screen.dart';

int? explorationLevel(String? path) => cafeLevelFromPath(path);

class ExplorationMapScreen extends ConsumerWidget {
  const ExplorationMapScreen({super.key, this.sharedLevel});

  final int? sharedLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CafeProgress> async = ref.watch(cafeProgressProvider);
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
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => Center(
          child: HubChunkyButton(
            label: '重新读取进度',
            icon: Icons.refresh_rounded,
            onPressed: () =>
                ref.read(cafeProgressProvider.notifier).refresh(),
          ),
        ),
        data: (CafeProgress progress) => _CafeMapBody(
          progress: progress,
          sharedLevel: sharedLevel,
        ),
      ),
    );
  }
}

class _CafeMapBody extends ConsumerWidget {
  const _CafeMapBody({required this.progress, this.sharedLevel});

  final CafeProgress progress;
  final int? sharedLevel;

  void _open(BuildContext context, WidgetRef ref, int index) {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => _CafeLevel(
              index: index,
              onComplete: () =>
                  ref.read(cafeProgressProvider.notifier).markLevelComplete(index),
            ),
          ),
        )
        .then((_) => ref.read(cafeProgressProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Set<int> completed = progress.completed;
    return ListView(
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
              color: AdventurePalette.pathAmber.withValues(alpha: 0.4),
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
                '${progress.progressLabel} · ${progress.weekLabel}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                progress.retestLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              AdventurePathStrip(
                nodeCount: progress.nodeCount,
                clearedCount: progress.clearedCount,
                currentIndex: progress.nextIndex,
              ),
              const SizedBox(height: 14),
              HubChunkyButton(
                label: progress.clearedCount >= progress.nodeCount
                    ? '重温本章'
                    : '继续第 ${progress.nextIndex + 1} 关',
                onPressed: () => _open(context, ref, progress.nextIndex),
              ),
            ],
          ),
        ),
        if (sharedLevel != null) ...<Widget>[
          const SizedBox(height: 12),
          QuestFeedCard(
            title: '练同一关 · ${kCafeLevels[sharedLevel!].title}',
            meta: '来自成果卡 · ${kCafeLevels[sharedLevel!].ability}',
            badge: '跟练',
            accent: AdventurePalette.pathAmber,
            onPlay: () => _open(context, ref, sharedLevel!),
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
        for (int index = 0; index < kCafeLevels.length; index++) ...<Widget>[
          _LevelNodeTile(
            index: index,
            title: kCafeLevels[index].title,
            ability: kCafeLevels[index].ability,
            cleared: completed.contains(index),
            current: index == progress.nextIndex && !completed.contains(index),
            onTap: () => _open(context, ref, index),
          ),
          if (index < kCafeLevels.length - 1)
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
    final CafeLevel level = kCafeLevels[widget.index];
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
    final CafeLevel level = kCafeLevels[widget.index];
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
                MaterialPageRoute<void>(
                  builder: (_) => PublishLearningResultScreen(
                    initialText:
                        '我完成了街角咖啡店的「${level.title}」关卡（${level.ability}）。一起来练吧！',
                    challengePath: cafeChallengePath(widget.index),
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
            for (int index = 0; index < level.answers.length; index++)
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
