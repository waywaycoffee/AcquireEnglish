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
    final CafeProgress? progress = async.asData?.value;
    final int stage = ((sharedLevel ?? progress?.nextIndex ?? 0) + 1).clamp(
      1,
      kCafeLevels.length,
    );
    return Scaffold(
      backgroundColor: AdventurePalette.nightInk,
      appBar: AppBar(
        backgroundColor: AdventurePalette.cafeWarm,
        foregroundColor: Colors.white,
        title: Text('街角咖啡店 · 第$stage站'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const StudyDeskScreen(),
              ),
            ),
            child: const Text(
              '学习桌',
              style: TextStyle(
                color: AdventurePalette.cafeGlow,
                fontWeight: FontWeight.w800,
              ),
            ),
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
    final int focus = sharedLevel ?? progress.nextIndex;
    final CafeLevel focusLevel = kCafeLevels[focus.clamp(0, kCafeLevels.length - 1)];
    return Column(
      children: <Widget>[
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  AdventurePalette.cafeWarm,
                  AdventurePalette.nightInk,
                  Color(0xFF0E1016),
                ],
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: <Widget>[
                Text(
                  '夜色街角 · 点单冒险',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AdventurePalette.cafeGlow.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${progress.progressLabel} · ${progress.weekLabel}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  progress.retestLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 18),
                CafeWindingPath(
                  titles: kCafeLevels.map((CafeLevel e) => e.title).toList(),
                  cleared: completed,
                  currentIndex: progress.nextIndex,
                  onTapLevel: (int index) => _open(context, ref, index),
                ),
                if (sharedLevel != null) ...<Widget>[
                  const SizedBox(height: 20),
                  QuestFeedCard(
                    title: '练同一关 · ${kCafeLevels[sharedLevel!].title}',
                    meta: '来自成果卡 · ${kCafeLevels[sharedLevel!].ability}',
                    badge: '跟练',
                    accent: AdventurePalette.pathAmber,
                    onPlay: () => _open(context, ref, sharedLevel!),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  '单人进度永久保留 · 同桌只加本周分',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ),
        Material(
          color: AppDesignTokens.appWhite,
          elevation: 12,
          shadowColor: Colors.black26,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '第 ${focus + 1} 关 · ${focusLevel.title}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    focusLevel.ability,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  HubChunkyButton(
                    label: completed.contains(focus) ? '再战本关' : '开始这一关',
                    onPressed: () => _open(context, ref, focus),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const StudyDeskScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.groups_2_outlined, size: 18),
                    label: const Text('约同桌练这关'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFFFFF6E8), Color(0xFFFFE8C8)],
              ),
              border: Border.all(
                color: AdventurePalette.pathAmber.withValues(alpha: 0.45),
              ),
              boxShadow: AppDesignTokens.toyCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AdventurePalette.pathAmber,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '能力 · ${level.ability}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF3A2A00),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
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
                border: Border.all(color: AppDesignTokens.brandGreen, width: 2),
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
            HubChunkyButton(
              label: '返回地图',
              icon: Icons.map_rounded,
              color: AdventurePalette.pathAmber,
              onPressed: () => Navigator.pop(context),
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
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x14000000),
                            offset: Offset(0, 3),
                          ),
                        ],
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
