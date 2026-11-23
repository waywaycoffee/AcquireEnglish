import 'package:flutter/material.dart';

import '../../../shared/presentation/android_system_inset.dart';
import '../subtitle_display_mode.dart';
import 'player_video_panel.dart';
import 'study_shell_tokens.dart';

class StudyBottomControls extends StatelessWidget {
  const StudyBottomControls({
    required this.subtitleMode,
    required this.speed,
    required this.isPlaying,
    required this.isLooping,
    required this.position,
    required this.duration,
    required this.onSelectSubtitleMode,
    required this.onCycleSpeed,
    required this.onTogglePlaying,
    required this.onOpenLoopSheet,
    required this.onOpenOralCoach,
    this.onSeek,
    this.onSpeedSelected,
    this.onToggleFullscreen,
    this.onLocateCurrent,
    this.onRerecognizeEnglish,
    this.onRerecognizeChinese,
    this.hardsubMosaicEnabled = false,
    this.onToggleHardsubMosaic,
    this.onEpisodeTest,
    this.onAiParse,
    super.key,
  });

  final String subtitleMode;
  final String speed;
  final bool isPlaying;
  final bool isLooping;
  final Duration position;
  final Duration duration;
  final ValueChanged<String> onSelectSubtitleMode;
  final VoidCallback onCycleSpeed;
  final VoidCallback onTogglePlaying;
  final VoidCallback onOpenLoopSheet;
  final VoidCallback onOpenOralCoach;
  final ValueChanged<double>? onSeek;
  final ValueChanged<String>? onSpeedSelected;
  final VoidCallback? onToggleFullscreen;

  /// Replaces the old bottom-left「倍速 / 超清 / 双语」text cluster.
  final VoidCallback? onLocateCurrent;
  final VoidCallback? onRerecognizeEnglish;
  final VoidCallback? onRerecognizeChinese;

  /// Bottom「遮」toggle for burned-in subtitle mosaic (drag-resize stays on video).
  final bool hardsubMosaicEnabled;
  final ValueChanged<bool>? onToggleHardsubMosaic;

  /// Bottom「测」: sample this episode into the dictation queue (output check).
  final VoidCallback? onEpisodeTest;

  /// Bottom「AI解析」: grammar / structure analysis of the active subtitle line.
  final VoidCallback? onAiParse;

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

  IconData get _subtitleIcon {
    switch (SubtitleDisplayMode.normalize(subtitleMode)) {
      case SubtitleDisplayMode.blind:
        return Icons.visibility_off_rounded;
      case SubtitleDisplayMode.english:
        return Icons.translate_rounded;
      case SubtitleDisplayMode.chinese:
        return Icons.language_rounded;
      case SubtitleDisplayMode.bilingual:
      default:
        return Icons.closed_caption_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.of(context);
    // Keep controls above Android system nav / gesture bar (edge-to-edge).
    final double bottomInset = systemBottomInsetOf(context);
    final double progress = duration.inMilliseconds <= 0
        ? 0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final String modeLabel = SubtitleDisplayMode.label(subtitleMode);

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
                  child: GestureDetector(
                    key: const ValueKey<String>('study-chip-subtitle-longpress'),
                    onLongPress: () {
                      onSelectSubtitleMode(
                        SubtitleDisplayMode.nextLearningMode(subtitleMode),
                      );
                    },
                    child: PopupMenuButton<String>(
                      key: const ValueKey<String>('study-chip-subtitle-mode'),
                      tooltip: '字幕类型 · 长按轮换',
                      color: colors.card,
                      onSelected: onSelectSubtitleMode,
                      itemBuilder: (BuildContext context) {
                        return SubtitleDisplayMode.learningModes
                            .map(
                              (String mode) => CheckedPopupMenuItem<String>(
                                value: mode,
                                checked: mode == modeLabel,
                                child: Text(
                                  mode,
                                  style: TextStyle(
                                    fontWeight: mode == modeLabel
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: mode == modeLabel
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
                              _subtitleIcon,
                              size: 22,
                              color: colors.accent,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              modeLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                    key: const ValueKey<String>('study-chip-oral-coach'),
                    icon: Icons.record_voice_over_rounded,
                    label: '英语口语',
                    selected: false,
                    colors: colors,
                    onPressed: onOpenOralCoach,
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
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (onLocateCurrent != null)
                            IconButton(
                              key: const ValueKey<String>(
                                'study-chip-locate-current',
                              ),
                              tooltip: '定位当前',
                              onPressed: onLocateCurrent,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 32,
                              ),
                              icon: Icon(
                                Icons.my_location,
                                size: 20,
                                color: colors.textSecondary,
                              ),
                            ),
                          if (onRerecognizeEnglish != null)
                            _BottomTextAction(
                              key: const ValueKey<String>(
                                'study-chip-rerecognize-en',
                              ),
                              label: 'AI英文',
                              color: colors.textSecondary,
                              onPressed: onRerecognizeEnglish!,
                            ),
                          if (onRerecognizeChinese != null)
                            _BottomTextAction(
                              key: const ValueKey<String>(
                                'study-chip-rerecognize-zh',
                              ),
                              label: 'AI中文',
                              color: colors.textSecondary,
                              onPressed: onRerecognizeChinese!,
                            ),
                          if (onToggleHardsubMosaic != null)
                            _BottomTextAction(
                              key: const ValueKey<String>(
                                'study-chip-hardsub-mosaic',
                              ),
                              label: '遮',
                              color: hardsubMosaicEnabled
                                  ? colors.accent
                                  : colors.textSecondary,
                              onPressed: () => onToggleHardsubMosaic!(
                                !hardsubMosaicEnabled,
                              ),
                            ),
                          if (onEpisodeTest != null)
                            _BottomTextAction(
                              key: const ValueKey<String>(
                                'study-chip-episode-test',
                              ),
                              label: '测',
                              tooltip: '本集测试：抽最多约8句听写',
                              color: colors.textSecondary,
                              onPressed: onEpisodeTest!,
                            ),
                          if (onAiParse != null)
                            _BottomTextAction(
                              key: const ValueKey<String>(
                                'study-chip-ai-parse',
                              ),
                              label: 'AI解析',
                              tooltip: '分析当前句：结构、词性、主谓宾、语法要点',
                              color: colors.textSecondary,
                              onPressed: onAiParse!,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '全屏',
                  onPressed: onToggleFullscreen,
                  icon: Icon(
                    Icons.fullscreen_rounded,
                    color: colors.textSecondary,
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

class _BottomTextAction extends StatelessWidget {
  const _BottomTextAction({
    required this.label,
    required this.color,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
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
      onTap: onPressed,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: colors.accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 54,
            height: 54,
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: colors.accentOn,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
