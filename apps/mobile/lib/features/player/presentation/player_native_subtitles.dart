import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Study player never paints softsubs on the video surface — hardsubs stay
/// readable and learners use the list under the player instead.
const SubtitleViewConfiguration kHiddenSubtitleViewConfiguration =
    SubtitleViewConfiguration(
      visible: false,
      style: TextStyle(fontSize: 1, color: Color(0x00000000)),
    );

List<SubtitleTrack> embeddedSubtitleTracks(Iterable<SubtitleTrack> tracks) {
  return tracks
      .where((SubtitleTrack track) => track.id != 'auto' && track.id != 'no')
      .toList(growable: false);
}

String embeddedSubtitleTrackLabel(SubtitleTrack track) {
  final String language = switch (track.language) {
    'eng' || 'en' => '英语',
    'chi' || 'zho' || 'zh' => '中文',
    final String value when value.trim().isNotEmpty => value,
    _ => '未知语言',
  };
  final String? title = track.title?.trim();
  return title == null || title.isEmpty ? language : '$language · $title';
}

/// Disable Flutter + native (libass/mpv) soft-subtitle painting.
///
/// Call after [Player.open] and whenever tracks refresh — mpv may auto-select
/// a default soft track (`subs-fallback`) that would cover burned-in hardsubs.
Future<void> suppressPlayerSoftSubtitles(Player player) async {
  try {
    await player.setSubtitleTrack(SubtitleTrack.no());
  } catch (_) {}
  final PlatformPlayer? platform = player.platform;
  if (platform is! NativePlayer) {
    return;
  }
  const List<(String, String)> props = <(String, String)>[
    ('sid', 'no'),
    ('secondary-sid', 'no'),
    ('sub-visibility', 'no'),
    ('secondary-sub-visibility', 'no'),
    ('sub-ass', 'no'),
    ('subs-fallback', 'no'),
    ('subs-with-matching-audio', 'no'),
  ];
  for (final (String name, String value) in props) {
    try {
      await platform.setProperty(name, value);
    } catch (_) {}
  }
}

/// Shared [Player] factory for study screens — libass off from the start.
///
/// [largeNetworkBuffer] helps Baidu/OpenList MKV progressive streams where
/// audio often starts before the first video keyframe arrives.
Player createStudyVideoPlayer({bool largeNetworkBuffer = false}) {
  return Player(
    configuration: PlayerConfiguration(
      // Cap demuxer cache: 2h+ MKV (e.g. Harry Potter) + 96MB buffer OOM'd
      // mid-film. Netdisk/B站 still get a larger progressive window than local.
      bufferSize: largeNetworkBuffer ? 48 * 1024 * 1024 : 24 * 1024 * 1024,
    ),
  );
}
