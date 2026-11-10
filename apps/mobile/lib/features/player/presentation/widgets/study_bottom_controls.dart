import 'package:flutter/material.dart';

import '../../../shared/presentation/android_system_inset.dart';
import 'player_video_panel.dart';
import 'study_shell_tokens.dart';

class StudyBottomControls extends StatelessWidget {
  const StudyBottomControls({
    required this.bilingual,
    required this.blindListening,
    required this.speed,
    required this.isPlaying,
    required this.isLooping,
    required this.position,
    required this.duration,
    required this.onToggleBlindListening,
    required this.onCycleSpeed,
    required this.onTogglePlaying,
    required this.onOpenLoopSheet,
    required this.onOpenWordCards,
    this.onToggleBilingual,
    this.onLongPressBlind,
    this.onSeek,
    this.onSpeedSelected,
    this.onOpenSpeedSheet,
    this.onOpenQualitySheet,
    this.qualityLabel = '超清',
    this.onToggleFullscreen,
    super.key,
  });

  final bool bilingual;
  final bool blindListening;
  final String speed;
  final bool isPlaying;
  final bool isLooping;
  final Duration position;
  final Duration duration;
  final VoidCallback onToggleBlindListening;
  final VoidCallback onCycleSpeed;
  final VoidCallback onTogglePlaying;
  final VoidCallback onOpenLoopSheet;
  final VoidCallback onOpenWordCards;
  final VoidCallback? onToggleBilingual;
  final VoidCallback? onLongPressBlind;
  final ValueChanged<double>? onSeek;
  final ValueChanged<String>? onSpeedSelected;
  final VoidCallback? onOpenSpeedSheet;
  final VoidCallback? onOpenQualitySheet;
  final String qualityLabel;
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
    final StudyShellColors colors = StudyShellColors.of(context);
    // Keep controls above Android system nav / gesture bar (edge-to-edge).
    final double bottomInset = systemBottomInsetOf(context);
    final double progress = duration.inMilliseconds <= 0
        ? 0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Material(
      color: colors.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 6 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _IconAction(
                    key: const ValueKey<String>('study-chip-blind'),
                    icon: blindListening
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    label: '盲听',
                    selected: blindListening,
                    colors: colors,
                    onPressed: onToggleBlindListening,
                    onLongPress: onLongPressBlind ?? onToggleBilingual,
                  ),
                ),
                Expanded(
                  child: PopupMenuButton<String>(
                    key: const ValueKey<String>('study-chip-speed'),
                    tooltip: '倍速',
                    color: colors.card,
                    onSelected: (String value) {
                      if (onSpeedSelected != null) {
                        onSpeedSelected!(value);
                        return;
                      }
                      onCycleSpeed();
                    },
                    itemBuilder: (BuildContext context) {
                      return PlayerVideoPanel.kSpeedOptions
                          .map(
                            (String option) => PopupMenuItem<String>(
                              value: option,
                              child: Text(
                                option.replaceAll('×', 'x'),
                                style: TextStyle(
                                  fontWeight: option == speed
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: option == speed
                                      ? colors.accent
                                      : colors.textPrimary,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.speed_rounded,
                            size: 22,
                            color: speed != '1.0×' && speed != '1×'
                                ? colors.accent
                                : colors.textSecondary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _speedLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: speed != '1.0×' && speed != '1×'
                                  ? colors.accent
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _PlayButton(
                  key: const ValueKey<String>('study-chip-play'),
                  isPlaying: isPlaying,
                  colors: colors,
                  onPressed: onTogglePlaying,
                ),
                Expanded(
                  child: _IconAction(
                    key: const ValueKey<String>('study-chip-loop'),
                    icon: Icons.repeat_rounded,
                    label: '循环',
                    selected: isLooping,
                    colors: colors,
                    onPressed: onOpenLoopSheet,
                  ),
                ),
                Expanded(
                  child: _IconAction(
                    key: const ValueKey<String>('study-chip-word-cards'),
                    icon: Icons.style_rounded,
                    label: '词卡',
                    selected: false,
                    colors: colors,
                    onPressed: onOpenWordCards,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  '${formatClock(position)} / ${formatClock(duration)}',
                  style: TextStyle(
                    color: colors.textMuted,
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
                      activeTrackColor: colors.progressPlayed,
                      inactiveTrackColor: colors.progressTrack,
                      thumbColor: colors.accentOn,
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
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: onOpenSpeedSheet ?? onCycleSpeed,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
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
                  onPressed: onOpenQualitySheet,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    qualityLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (bilingual)
                  TextButton(
                    onPressed: onToggleBilingual,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '双语',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: '全屏',
                  onPressed: onToggleFullscreen,
                  icon: Icon(
                    Icons.fullscreen_rounded,
                    color: colors.textSecondary,
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
    required this.colors,
    required this.onPressed,
    this.onLongPress,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final StudyShellColors colors;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? colors.accent : colors.textSecondary;
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
    required this.colors,
    required this.onPressed,
    super.key,
  });

  final bool isPlaying;
  final StudyShellColors colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.playGlow,
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: colors.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 58,
              height: 58,
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: colors.accentOn,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
