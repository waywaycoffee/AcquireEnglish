import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'library_catalog_provider.dart';
import 'library_mock_data.dart';

/// Auto-split watched episodes into 1–3 minute dubbing clips.
class DubClipHub extends ConsumerWidget {
  const DubClipHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LearningActivityState activity = ref.watch(learningActivityProvider);
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    final List<_DubClip> clips = _buildClips(
      watchedKeys: activity.today.watchedVideoKeys.union(
        activity.records.values
            .expand((LearningDailyRecord r) => r.watchedVideoKeys)
            .toSet(),
      ),
      courses: courses,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        Text(
          '配音练习',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '从你看过的视频里自动切出 1–3 分钟片段；配音使用人声分离伴奏，完成后可分享到朋友圈。',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        if (clips.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppDesignTokens.borderGray),
            ),
            child: Text(
              '先去 B站 / 美剧 / YouTube 看几集视频，这里会自动生成配音片段。',
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          )
        else
          for (final _DubClip clip in clips) ...<Widget>[
            _DubClipCard(clip: clip),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

List<_DubClip> _buildClips({
  required Set<String> watchedKeys,
  required List<LibraryCourseData> courses,
}) {
  final List<_DubClip> out = <_DubClip>[];
  final Map<String, (LibraryCourseData, LibraryEpisodeItem)> byId =
      <String, (LibraryCourseData, LibraryEpisodeItem)>{};
  for (final LibraryCourseData course in courses) {
    for (final LibraryEpisodeItem ep in course.episodes) {
      byId[ep.id] = (course, ep);
    }
  }
  for (final String key in watchedKeys) {
    final (LibraryCourseData, LibraryEpisodeItem)? hit = byId[key];
    if (hit == null) continue;
    final LibraryCourseData course = hit.$1;
    final LibraryEpisodeItem ep = hit.$2;
    final int totalSec = (ep.durationMinutes * 60).clamp(60, 3 * 3600);
    // Prefer ~2 min windows; clamp 60–180s.
    final int window = totalSec >= 180
        ? 150
        : totalSec >= 90
            ? 90
            : totalSec.clamp(60, 180);
    int start = 0;
    int index = 1;
    while (start + 45 < totalSec && out.length < 40) {
      final int end = (start + window).clamp(start + 60, totalSec);
      if (end - start < 55) break;
      out.add(
        _DubClip(
          episodeId: ep.id,
          courseId: course.id,
          title: ep.title.trim().isEmpty ? course.title : ep.title,
          courseTitle: course.title,
          cover: ep.coverImage.isNotEmpty ? ep.coverImage : course.coverImage,
          startMs: start * 1000,
          endMs: end * 1000,
          index: index,
        ),
      );
      start += window;
      index += 1;
      if (index > 4) break; // at most 4 clips per watched episode
    }
  }
  return out;
}

class _DubClip {
  const _DubClip({
    required this.episodeId,
    required this.courseId,
    required this.title,
    required this.courseTitle,
    required this.cover,
    required this.startMs,
    required this.endMs,
    required this.index,
  });

  final String episodeId;
  final String courseId;
  final String title;
  final String courseTitle;
  final String cover;
  final int startMs;
  final int endMs;
  final int index;

  String get rangeLabel {
    String fmt(int ms) {
      final int s = ms ~/ 1000;
      final int m = s ~/ 60;
      final int r = s % 60;
      return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
    }

    return '${fmt(startMs)}–${fmt(endMs)}';
  }

  int get durationSec => ((endMs - startMs) / 1000).round();
}

class _DubClipCard extends StatelessWidget {
  const _DubClipCard({required this.clip});

  final _DubClip clip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 96,
                  height: 64,
                  child: clip.cover.trim().isEmpty
                      ? ColoredBox(
                          color: AppDesignTokens.softGray,
                          child: Icon(
                            Icons.mic_none_rounded,
                            color: AppDesignTokens.textSecondary,
                          ),
                        )
                      : CoverImage(path: clip.cover, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${clip.title} · 片段 ${clip.index}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${clip.rangeLabel} · ${clip.durationSec}s · 人声分离',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => _open(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.primaryBlueDark,
                  foregroundColor: AppDesignTokens.onAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('去配音'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    context.pushNamed(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': clip.episodeId},
      queryParameters: <String, String>{
        'courseId': clip.courseId,
        'activity': 'shadowing',
        'courseStartMs': '${clip.startMs}',
        'courseEndMs': '${clip.endMs}',
        'autoplay': '0',
      },
    );
  }
}
