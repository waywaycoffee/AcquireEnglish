import 'package:flutter/material.dart';

import 'pad_portrait_player_screen.dart';

/// Study player is always the portrait shell. Landscape UI is only used inside
/// [PlayerFullscreenVideoScreen] after the user taps fullscreen.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({
    required this.episodeId,
    this.initialStartTime,
    this.courseId,
    this.unitId,
    this.courseStartMs,
    this.courseEndMs,
    this.autoPlay = true,
    this.autoOpenFullscreen = false,
    this.initialLoopSentence = false,
    this.dramaPlan = false,
    super.key,
  });

  final String episodeId;
  final String? initialStartTime;
  final String? courseId;
  final String? unitId;
  final int? courseStartMs;
  final int? courseEndMs;
  final bool autoPlay;
  final bool autoOpenFullscreen;
  final bool initialLoopSentence;
  final bool dramaPlan;

  @override
  Widget build(BuildContext context) {
    return PadPortraitPlayerScreen(
      key: ValueKey<String>(episodeId),
      episodeId: episodeId,
      initialStartTime: initialStartTime,
      courseId: courseId,
      unitId: unitId,
      courseStartMs: courseStartMs,
      courseEndMs: courseEndMs,
      autoPlay: autoPlay,
      autoOpenFullscreen: autoOpenFullscreen,
      initialLoopSentence: initialLoopSentence,
      dramaPlan: dramaPlan,
    );
  }
}
