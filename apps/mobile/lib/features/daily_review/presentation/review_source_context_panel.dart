import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../player/presentation/player_mock_state.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/domain/subtitle_letter_case.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/review_clip_frame_cache.dart';
import '../domain/daily_review.dart';
import 'review_clip_player_sheet.dart';

/// BaiCiZhan-style context block: frame/cover + subtitle example + source + clip.
class ReviewSourceContextPanel extends ConsumerStatefulWidget {
  const ReviewSourceContextPanel({
    required this.source,
    required this.word,
    required this.onSpeakSentence,
    this.speaking = false,
    this.compact = false,
    this.hideSentence = false,
    super.key,
  });

  final ReviewSource source;
  final String word;
  final Future<void> Function() onSpeakSentence;
  final bool speaking;
  final bool compact;
  /// When true (e.g. cloze front), keep source/clip but hide the subtitle line.
  final bool hideSentence;

  @override
  ConsumerState<ReviewSourceContextPanel> createState() =>
      _ReviewSourceContextPanelState();
}

class _ReviewSourceContextPanelState
    extends ConsumerState<ReviewSourceContextPanel> {
  final ReviewClipFrameCache _frames = const ReviewClipFrameCache();
  String? _framePath;
  bool _loadingFrame = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFrame());
  }

  @override
  void didUpdateWidget(covariant ReviewSourceContextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.episodeId != widget.source.episodeId ||
        oldWidget.source.startMs != widget.source.startMs ||
        oldWidget.source.time != widget.source.time) {
      _framePath = null;
      unawaited(_loadFrame());
    }
  }

  ({LibraryCourseData course, LibraryEpisodeItem episode})? _resolveEpisode() {
    final String? episodeId = widget.source.episodeId?.trim();
    if (episodeId == null || episodeId.isEmpty) return null;
    for (final LibraryCourseData course in ref.read(libraryCatalogProvider)) {
      for (final LibraryEpisodeItem episode in course.episodes) {
        if (episode.id == episodeId) {
          return (course: course, episode: episode);
        }
      }
    }
    return null;
  }

  int? _startMs() {
    if (widget.source.startMs != null) return widget.source.startMs;
    return PlayerMockState.parseTimestampToMsPublic(widget.source.time);
  }

  int _clipDurationMs() {
    final int? start = _startMs();
    final int? end = widget.source.endMs;
    if (start != null && end != null && end > start) {
      return (end - start).clamp(1200, 3500);
    }
    return 2000;
  }

  Future<void> _loadFrame() async {
    final hit = _resolveEpisode();
    final String? video = hit?.episode.videoAsset;
    final int? start = _startMs();
    if (hit == null ||
        video == null ||
        !isUsableLocalVideoPath(video) ||
        start == null) {
      return;
    }
    setState(() => _loadingFrame = true);
    try {
      final File? file = await _frames.resolve(
        episodeId: hit.episode.id,
        videoPath: video,
        positionMs: start,
      );
      if (!mounted) return;
      setState(() {
        _framePath = file?.path;
        _loadingFrame = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingFrame = false);
    }
  }

  Future<void> _playClip() async {
    final hit = _resolveEpisode();
    final String? video = hit?.episode.videoAsset;
    final int? start = _startMs();
    if (hit == null || video == null || !isUsableLocalVideoPath(video)) {
      _openFullPlayer();
      return;
    }
    if (start == null) {
      _openFullPlayer();
      return;
    }
    await showReviewClipPlayerSheet(
      context,
      title: widget.source.sourceLabel,
      videoPath: video,
      startMs: start,
      durationMs: _clipDurationMs(),
    );
  }

  void _openFullPlayer() {
    final String? episodeId = widget.source.episodeId?.trim();
    if (episodeId == null || episodeId.isEmpty) return;
    final String? time = widget.source.time;
    context.pushNamed(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': episodeId},
      queryParameters: <String, String>{
        if (time != null && time.isNotEmpty) 'startTime': time,
        'autoplay': '1',
        'loop': 'sentence',
      },
    );
  }

  String? _coverFallback(
    ({LibraryCourseData course, LibraryEpisodeItem episode})? hit,
  ) {
    if (hit == null) return null;
    final String episodeCover = hit.episode.coverImage.trim();
    if (episodeCover.isNotEmpty) return episodeCover;
    final String courseCover = hit.course.coverImage.trim();
    if (courseCover.isNotEmpty) return courseCover;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String letterCase = ref.watch(
      learningSettingsProvider.select(
        (LearningSettingsState settings) => settings.subtitleLetterCase,
      ),
    );
    final String sentence = widget.hideSentence
        ? ''
        : formatSubtitleLetterCase(widget.source.english.trim(), letterCase);
    final String chinese =
        widget.hideSentence ? '' : widget.source.chinese.trim();
    final String label = widget.source.sourceLabel.trim();
    final String? time = widget.source.time?.trim();
    final hit = _resolveEpisode();
    final String? cover = _framePath ?? _coverFallback(hit);
    final bool hasVideo = hit != null &&
        isUsableLocalVideoPath(hit.episode.videoAsset);
    final bool hasContext = sentence.isNotEmpty ||
        label.isNotEmpty ||
        cover != null ||
        hasVideo ||
        widget.source.relatedSources.isNotEmpty;
    if (!hasContext) return const SizedBox.shrink();

    final double imageHeight = widget.compact ? 132 : 168;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (cover != null && cover.isNotEmpty) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: imageHeight,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CoverImage(path: cover, fit: BoxFit.cover),
                    if (_loadingFrame)
                      const ColoredBox(
                        color: Color(0x33000000),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    if (hasVideo)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => unawaited(_playClip()),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '约2秒',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ] else if (hasVideo) ...<Widget>[
            OutlinedButton.icon(
              onPressed: () => unawaited(_playClip()),
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('播放原片约 2 秒'),
            ),
            const SizedBox(height: 8),
          ],
          if (sentence.isNotEmpty) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                IconButton(
                  tooltip: '朗读例句',
                  onPressed: widget.speaking
                      ? null
                      : () => unawaited(widget.onSpeakSentence()),
                  icon: const Icon(Icons.volume_up_rounded),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: _HighlightedSentence(
                    sentence: sentence,
                    word: widget.word,
                  ),
                ),
              ],
            ),
            if (chinese.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 48, top: 2),
                child: Text(
                  chinese,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppDesignTokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
          Row(
            children: <Widget>[
              Icon(
                hasVideo ? Icons.ondemand_video_rounded : Icons.menu_book_rounded,
                size: 16,
                color: AppDesignTokens.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  <String>[
                    if (label.isNotEmpty) label,
                    if (time != null && time.isNotEmpty) time,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ),
              if (hasVideo)
                TextButton(
                  onPressed: _openFullPlayer,
                  child: const Text('打开原片'),
                ),
            ],
          ),
          if (widget.source.relatedSources.length > 1) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final ReviewSourceLink link
                    in widget.source.relatedSources.take(4))
                  Chip(
                    label: Text(
                      link.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HighlightedSentence extends StatelessWidget {
  const _HighlightedSentence({required this.sentence, required this.word});

  final String sentence;
  final String word;

  @override
  Widget build(BuildContext context) {
    final String needle = word.trim();
    if (needle.isEmpty) {
      return Text(
        sentence,
        style: const TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final RegExp re = RegExp(
      RegExp.escape(needle),
      caseSensitive: false,
    );
    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;
    for (final Match match in re.allMatches(sentence)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: sentence.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: sentence.substring(match.start, match.end),
          style: const TextStyle(
            color: Color(0xFF1D4ED8),
            fontWeight: FontWeight.w900,
            backgroundColor: Color(0xFFDBEAFE),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(cursor)));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: sentence));
    }
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111827),
        ),
        children: spans,
      ),
    );
  }
}
