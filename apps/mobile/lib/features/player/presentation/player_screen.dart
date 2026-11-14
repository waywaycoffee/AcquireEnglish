import 'package:flutter/material.dart';

import 'pad_portrait_player_screen.dart';

/// Study player is always the portrait shell. Landscape UI is only used inside
/// [PlayerFullscreenVideoScreen] after the user taps fullscreen.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({
    required this.episodeId,
    this.initialStartTime,
    this.autoPlay = false,
    this.autoOpenFullscreen = false,
    super.key,
  });

  final String episodeId;
  final String? initialStartTime;
  final bool autoPlay;
  final bool autoOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    return PadPortraitPlayerScreen(
      key: ValueKey<String>(episodeId),
      episodeId: episodeId,
      initialStartTime: initialStartTime,
      autoPlay: autoPlay,
      autoOpenFullscreen: autoOpenFullscreen,
    );
  }
}
