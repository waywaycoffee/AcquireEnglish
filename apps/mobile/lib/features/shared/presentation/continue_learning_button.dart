import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../subtitle_completion/subtitle_completion_queue.dart';
import '../../subtitle_completion/subtitle_completion_runtime.dart';
import '../../subtitle_completion/subtitle_completion_status_provider.dart';
import 'pad/app_design_tokens.dart';

/// Global FAB: subtitle-import progress takes priority over「继续学习」.
class ContinueLearningButton extends ConsumerStatefulWidget {
  const ContinueLearningButton({super.key});

  @override
  ConsumerState<ContinueLearningButton> createState() =>
      _ContinueLearningButtonState();
}

class _ContinueLearningButtonState
    extends ConsumerState<ContinueLearningButton> {
  bool _isOpening = false;
  SubtitleRuntimeSnapshot _runtime =
      SubtitleCompletionRuntime.instance.currentSnapshot;
  StreamSubscription<SubtitleRuntimeSnapshot>? _runtimeSub;

  @override
  void initState() {
    super.initState();
    _runtimeSub = SubtitleCompletionRuntime.instance.snapshots.listen((
      SubtitleRuntimeSnapshot snap,
    ) {
      if (!mounted) {
        return;
      }
      setState(() => _runtime = snap);
    });
  }

  @override
  void dispose() {
    unawaited(_runtimeSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SubtitleCompletionStatusState fill = ref.watch(
      subtitleCompletionStatusProvider,
    );
    final _SubtitleFabState? subtitle = _subtitleFabState(fill, _runtime);
    if (subtitle != null) {
      return FloatingActionButton.extended(
        key: const ValueKey<String>('subtitle-fill-fab'),
        heroTag: 'global-subtitle-fill',
        tooltip: subtitle.tooltip,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(subtitle.tooltip),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        backgroundColor: const Color(0xFF3B7CFF),
        foregroundColor: Colors.white,
        elevation: 3,
        shape: const StadiumBorder(),
        icon: SizedBox(
          width: 22,
          height: 22,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CircularProgressIndicator(
                value: subtitle.progress.clamp(0.05, 1.0),
                strokeWidth: 2.4,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const Icon(Icons.subtitles_rounded, size: 12),
            ],
          ),
        ),
        label: Text(
          subtitle.label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }

    final ContinueLearningTarget? target = ref.watch(
      continueLearningTargetProvider,
    );
    if (target == null) {
      return const SizedBox.shrink();
    }
    return FloatingActionButton.extended(
      key: const ValueKey<String>('continue-learning-button'),
      heroTag: 'global-continue-learning',
      tooltip: '继续学习《${target.course.title}》 · 第 ${target.episode.numberStr} 集',
      onPressed: _isOpening
          ? null
          : () async {
              if (_isOpening) {
                return;
              }
              setState(() => _isOpening = true);
              try {
                await context.pushNamed<void>(
                  SGRoute.player.name,
                  pathParameters: <String, String>{
                    'episodeId': target.episode.id,
                  },
                  queryParameters: const <String, String>{'autoplay': '1'},
                );
              } finally {
                if (mounted) {
                  setState(() => _isOpening = false);
                }
              }
            },
      backgroundColor: AppDesignTokens.brandGreen,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: const StadiumBorder(),
      icon: const Icon(Icons.play_circle_fill_rounded),
      label: Text(
        '继续播放第 ${target.episode.numberStr} 集',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SubtitleFabState {
  const _SubtitleFabState({
    required this.label,
    required this.tooltip,
    required this.progress,
  });

  final String label;
  final String tooltip;
  final double progress;
}

_SubtitleFabState? _subtitleFabState(
  SubtitleCompletionStatusState fill,
  SubtitleRuntimeSnapshot runtime,
) {
  final List<SubtitleCompletionEpisodeUi> active = fill.byEpisodeId.values
      .where((SubtitleCompletionEpisodeUi e) => e.isActive)
      .toList(growable: false);
  if (active.isEmpty && !runtime.active) {
    return null;
  }
  SubtitleCompletionEpisodeUi? focus;
  for (final SubtitleCompletionEpisodeUi row in active) {
    if (row.status == SubtitleCompletionStatus.running) {
      focus = row;
      break;
    }
  }
  focus ??= active.isEmpty ? null : active.first;
  final double progress = (focus?.progressFraction ??
          (runtime.active ? runtime.progress : null) ??
          0.12)
      .clamp(0.05, 0.99);
  final int pct = (progress * 100).round();
  final String live = (focus?.label ?? fill.activeLabel ?? runtime.label)
      .trim();
  final String tooltip = live.isNotEmpty
      ? live
      : (active.length > 1 ? '正在补字幕（${active.length} 集）' : '正在补字幕');
  return _SubtitleFabState(
    label: '补字幕 $pct%',
    tooltip: tooltip,
    progress: progress,
  );
}
