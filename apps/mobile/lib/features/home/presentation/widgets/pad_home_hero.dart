import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../import_course/data/bilibili_import_service.dart';
import '../../../import_course/domain/bilibili_import.dart';
import '../../../library/presentation/library_catalog_provider.dart';
import '../../../library/presentation/library_mock_data.dart';
import '../../../library/presentation/widgets/library_course_poster.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/pad/pad_compact.dart';

class PadHomeHero extends StatelessWidget {
  const PadHomeHero({
    required this.onTap,
    required this.course,
    required this.episode,
    super.key,
  });

  final VoidCallback onTap;
  final LibraryCourseData? course;
  final LibraryEpisodeItem? episode;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    final bool narrow = MediaQuery.sizeOf(context).width < 720;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppDesignTokens.appWhite,
          borderRadius: BorderRadius.circular(compact ? 30 : 36),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x1F24385B),
              blurRadius: 36,
              offset: Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _VideoPreview(course: course, episode: episode),
                  _HeroDetails(onTap: onTap, course: course, episode: episode),
                ],
              )
            : SizedBox(
                height: compact ? 330 : 350,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 9,
                      child: _VideoPreview(course: course, episode: episode),
                    ),
                    Expanded(
                      flex: 11,
                      child: _HeroDetails(
                        onTap: onTap,
                        course: course,
                        episode: episode,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

bool _isUsableCoverPath(String path) {
  final String value = path.trim();
  if (value.isEmpty || value.startsWith('assets/')) {
    return false;
  }
  // Remote covers are displayable via NetworkImage (with Referer). Still prefer
  // a local file when refresh can pin one.
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return true;
  }
  return File(value).existsSync();
}

bool _needsLocalCoverPin(String path) {
  final String value = path.trim();
  return value.startsWith('http://') || value.startsWith('https://');
}

String _heroCoverPath(LibraryCourseData? course, LibraryEpisodeItem? episode) {
  final String episodeCover = episode?.coverImage.trim() ?? '';
  final String courseCover = course?.coverImage.trim() ?? '';
  if (_isUsableCoverPath(episodeCover)) {
    return episodeCover;
  }
  if (_isUsableCoverPath(courseCover)) {
    return courseCover;
  }
  return courseCover.isNotEmpty ? courseCover : episodeCover;
}

String? _bilibiliSource(LibraryCourseData? course, LibraryEpisodeItem? episode) {
  final String description = course?.description.trim() ?? '';
  if (description.isNotEmpty &&
      (description.contains('bilibili.com') ||
          description.contains('b23.tv') ||
          description.contains('BV') ||
          BilibiliImport.looksLikeBilibiliInput(description))) {
    return description;
  }
  final String id = course?.id ?? '';
  if (id.startsWith('bilibili-')) {
    return id.substring('bilibili-'.length);
  }
  final String? video = episode?.videoAsset?.trim();
  if (video != null &&
      video.isNotEmpty &&
      (BilibiliImport.isWatchPageUrl(video) ||
          BilibiliImport.looksLikeBilibiliInput(video))) {
    return video;
  }
  return null;
}

bool _isBilibiliCourse(LibraryCourseData? course) {
  if (course == null) {
    return false;
  }
  return course.category == 'bilibili' ||
      course.sourceLabel.toLowerCase().contains('bilibili') ||
      course.id.startsWith('bilibili-');
}

class _VideoPreview extends ConsumerStatefulWidget {
  const _VideoPreview({required this.course, required this.episode});

  final LibraryCourseData? course;
  final LibraryEpisodeItem? episode;

  @override
  ConsumerState<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends ConsumerState<_VideoPreview> {
  String? _fetchedCover;
  String? _fetchKey;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureCover());
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course?.id != widget.course?.id ||
        oldWidget.course?.coverImage != widget.course?.coverImage ||
        oldWidget.episode?.coverImage != widget.episode?.coverImage ||
        oldWidget.episode?.videoAsset != widget.episode?.videoAsset) {
      unawaited(_ensureCover());
    }
  }

  Future<void> _ensureCover() async {
    final String existing = _heroCoverPath(widget.course, widget.episode);
    if (_isUsableCoverPath(existing) && !_needsLocalCoverPin(existing)) {
      if (mounted) {
        setState(() => _fetchedCover = existing);
      }
      return;
    }
    if (_isUsableCoverPath(existing) && mounted) {
      // Show remote URL immediately while we pin a local copy.
      setState(() => _fetchedCover = existing);
    }
    if (!_isBilibiliCourse(widget.course)) {
      return;
    }
    final String? source = _bilibiliSource(widget.course, widget.episode);
    if (source == null || source.isEmpty) {
      return;
    }
    final String key = '${widget.course?.id}|$source';
    if (_fetchKey == key &&
        _fetchedCover != null &&
        !_needsLocalCoverPin(_fetchedCover!)) {
      return;
    }
    _fetchKey = key;
    try {
      final String? cover =
          await BilibiliImportService().resolveCoverImage(source);
      if (!mounted || cover == null || cover.isEmpty) {
        return;
      }
      setState(() => _fetchedCover = cover);
      final String? courseId = widget.course?.id;
      if (!mounted || courseId == null || courseId.isEmpty) {
        return;
      }
      try {
        await ref
            .read(libraryCatalogProvider.notifier)
            .updateCourseCover(courseId: courseId, coverImage: cover);
      } catch (_) {
        // Catalog write is best-effort; hero already shows [_fetchedCover].
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const BorderRadius radius = BorderRadius.zero;
    final String path =
        (_fetchedCover != null && _isUsableCoverPath(_fetchedCover!))
        ? _fetchedCover!
        : _heroCoverPath(widget.course, widget.episode);
    return AspectRatio(
      aspectRatio: 1.15,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          LibraryCoursePoster(
            title: widget.course?.title ?? '导入你的第一套课程',
            path: path,
            borderRadius: radius,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0x240A1425), Color(0xB6000000)],
              ),
            ),
          ),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppDesignTokens.onAccent.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppDesignTokens.onAccent.withValues(alpha: 0.55),
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x66000000), blurRadius: 16),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 40,
                color: AppDesignTokens.onAccent,
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: Text(
              widget.episode?.title ?? '本地视频 · 英文字幕',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppDesignTokens.onAccent,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroDetails extends StatelessWidget {
  const _HeroDetails({
    required this.onTap,
    required this.course,
    required this.episode,
  });

  final VoidCallback onTap;
  final LibraryCourseData? course;
  final LibraryEpisodeItem? episode;

  @override
  Widget build(BuildContext context) {
    final bool compact = context.isPadCompact;
    final bool hasCourse = course != null;
    final String progressTime = episode?.progressTimeStr ?? '从第 1 句开始';

    return Padding(
      padding: EdgeInsets.all(compact ? 18 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _Pill(
            label: hasCourse ? 'WELCOME BACK · 继续学习' : '开始你的学习旅程',
            color: AppDesignTokens.isDark
                ? AppDesignTokens.skyLight
                : const Color(0xFFE8F1FF),
            textColor: AppDesignTokens.isDark
                ? AppDesignTokens.primaryBlue
                : const Color(0xFF315D9D),
          ),
          const SizedBox(height: 10),
          Text(
            hasCourse ? course!.title : '导入你的第一套英语视频课程',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 28 : 32,
              fontWeight: FontWeight.w900,
              height: 1.1,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          if (hasCourse && episode != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              episode!.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (hasCourse) ...<Widget>[
            const SizedBox(height: 8),
            const Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppDesignTokens.primaryBlueDark,
                ),
                SizedBox(width: 6),
                Text(
                  '字幕精听 · 从上次停留的句子继续',
                  style: TextStyle(
                    color: AppDesignTokens.primaryBlueDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            hasCourse ? '上次学习：$progressTime' : '导入本地视频和英文字幕，即刻开始精听。',
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: compact ? 50 : 52,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.play_arrow_rounded, size: 25),
              label: Text(
                hasCourse ? '继续播放' : '去导入课程',
                style: TextStyle(
                  fontSize: compact ? 17 : 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.brandGreen,
                foregroundColor: AppDesignTokens.onAccent,
                elevation: 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          if (hasCourse) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Text(
                  '课程进度',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${course!.progressPercent}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.brandGreenDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: <Widget>[
                  Container(
                    height: 12,
                    color: AppDesignTokens.isDark
                        ? AppDesignTokens.softGray
                        : const Color(0xFFE7ECF0),
                  ),
                  FractionallySizedBox(
                    widthFactor: course!.progressPercent / 100,
                    child: Container(
                      height: 12,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            AppDesignTokens.brandGreen,
                            Color(0xFF8BE03E),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }
}
