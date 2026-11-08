import 'package:flutter/material.dart';

import 'player_video_panel.dart';
import 'study_shell_tokens.dart';

class StudyBottomControls extends StatelessWidget {
  const StudyBottomControls({
    required this.bilingual,
    required this.speed,
    required this.isPlaying,
    required this.isLooping,
    required this.position,
    required this.duration,
    required this.onToggleBilingual,
    required this.onCycleSpeed,
    required this.onTogglePlaying,
    required this.onToggleLoop,
    required this.onOpenCloseReading,
    this.onLongPressBilingual,
    this.onSeek,
    this.onOpenSpeedSheet,
    this.onToggleFullscreen,
    super.key,
  });

  final bool bilingual;
  final String speed;
  final bool isPlaying;
  final bool isLooping;
  final Duration position;
  final Duration duration;
  final VoidCallback onToggleBilingual;
  final VoidCallback onCycleSpeed;
  final VoidCallback onTogglePlaying;
  final VoidCallback onToggleLoop;
  final VoidCallback onOpenCloseReading;
  final VoidCallback? onLongPressBilingual;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onOpenSpeedSheet;
  final VoidCallback? onToggleFullscreen;

  static String nextSpeed(String current) {
    const List<String> options = PlayerVideoPanel.kSpeedOptions;
    final int index = options.indexOf(current);
    if (index < 0) {
      return options.first;
    }
    return options[(index + 1) % options.length];
  }

  String get _speedLabel {
    if (speed == '1.0×' || speed == '1×') {
      return '1x';
    }
    return speed.replaceAll('×', 'x');
  }

  static String formatClock(Duration value) {
    final int totalSeconds = value.inSeconds.clamp(0, 24 * 3600);
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final double progress = duration.inMilliseconds <= 0
        ? 0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Material(
      color: StudyShellTokens.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, 8 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child:                   _IconAction(
                    key: const ValueKey<String>('study-chip-bilingual'),
                    icon: Icons.translate_rounded,
                    label: '双',
                    selected: bilingual,
                    onPressed: onToggleBilingual,
                    onLongPress: onLongPressBilingual,
                  ),
                ),
                Expanded(
                  child: _IconAction(
                    key: const ValueKey<String>('study-chip-speed'),
                    icon: Icons.speed_rounded,
                    label: _speedLabel,
                    selected: speed != '1.0×' && speed != '1×',
                    onPressed: onCycleSpeed,
                  ),
                ),
                _PlayButton(
                  key: const ValueKey<String>('study-chip-play'),
                  isPlaying: isPlaying,
                  onPressed: onTogglePlaying,
                ),
                Expanded(
                  child: _IconAction(
                    key: const ValueKey<String>('study-chip-loop'),
                    icon: Icons.repeat_one_rounded,
                    label: '循环',
                    selected: isLooping,
                    onPressed: onToggleLoop,
                  ),
                ),
                Expanded(
                  child: _IconAction(
                    key: const ValueKey<String>('study-chip-close-reading'),
                    icon: Icons.menu_book_rounded,
                    label: '精读',
                    selected: false,
                    onPressed: onOpenCloseReading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Text(
                  '${formatClock(position)} / ${formatClock(duration)}',
                  style: const TextStyle(
                    color: StudyShellTokens.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                      activeTrackColor: StudyShellTokens.progressPlayed,
                      inactiveTrackColor: StudyShellTokens.progressTrack,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: onSeek == null
                          ? null
                          : (double value) => onSeek!(value),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: onOpenSpeedSheet ?? onCycleSpeed,
                  style: TextButton.styleFrom(
                    foregroundColor: StudyShellTokens.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '倍速',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    foregroundColor: StudyShellTokens.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '超清',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '全屏',
                  onPressed: onToggleFullscreen,
                  icon: const Icon(
                    Icons.fullscreen_rounded,
                    color: StudyShellTokens.textSecondary,
                    size: 22,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.onLongPress,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final Color color = selected
        ? StudyShellTokens.accent
        : StudyShellTokens.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPressed,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.onPressed,
    super.key,
  });

  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: StudyShellTokens.accent,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: StudyShellTokens.accent.withValues(alpha: 0.45),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 58,
            height: 58,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}
