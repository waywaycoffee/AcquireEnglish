import 'package:flutter/material.dart';

import 'pad_landscape_player_screen.dart';
import 'pad_portrait_player_screen.dart';

/// Portrait shell by default. [tvMode] opens the landscape TV study chrome
/// (see `design/tv_study_landscape.pen`).
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
    this.videoPlanActivity,
    this.todayTaskId,
    this.dramaPlan = false,
    this.onlinePreview = false,
    this.tvMode = false,
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
  final String? videoPlanActivity;
  final String? todayTaskId;
  final bool dramaPlan;
  final bool onlinePreview;
  final bool tvMode;

  @override
  Widget build(BuildContext context) {
    if (tvMode) {
      return PadLandscapePlayerScreen(
        key: ValueKey<String>('tv-$episodeId'),
        episodeId: episodeId,
        initialStartTime: initialStartTime,
        autoPlay: autoPlay,
        autoOpenFullscreen: false,
        tvMode: true,
      );
    }
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
      onlinePreview: onlinePreview,
      videoPlanActivity: videoPlanActivity,
      todayTaskId: todayTaskId,
    );
  }
}
