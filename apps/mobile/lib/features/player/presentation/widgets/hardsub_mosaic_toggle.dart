import 'package:flutter/material.dart';

import 'study_shell_tokens.dart';

/// Compact switch to cover burned-in (hard) subtitles with a draggable mosaic band.
class HardsubMosaicToggle extends StatelessWidget {
  const HardsubMosaicToggle({
    required this.enabled,
    required this.onChanged,
    this.contentPadding = EdgeInsets.zero,
    super.key,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final StudyShellColors shell = StudyShellColors.of(context);
    return SwitchListTile(
      key: const ValueKey<String>('hardsub-mosaic-toggle'),
      contentPadding: contentPadding,
      title: Text(
        '遮挡硬字幕',
        style: TextStyle(
          color: shell.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '拉出马赛克框盖住视频里的字幕',
        style: TextStyle(color: shell.textSecondary, fontSize: 12),
      ),
      value: enabled,
      activeThumbColor: shell.accent,
      onChanged: onChanged,
    );
  }
}
