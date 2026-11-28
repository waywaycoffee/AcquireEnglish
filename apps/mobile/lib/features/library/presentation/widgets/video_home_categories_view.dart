import 'package:flutter/material.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../../../shared/presentation/shell_top_chrome.dart';
import '../library_mock_data.dart';
import 'library_course_poster.dart';

/// Pencil video-home: fixed vertical category rows + bilingual badges.
class VideoHomeCategory {
  const VideoHomeCategory({
    required this.id,
    required this.title,
    required this.match,
  });

  final String id;
  final String title;
  final bool Function(LibraryCourseData course) match;
}

const List<VideoHomeCategory> kVideoHomeCategories = <VideoHomeCategory>[
  VideoHomeCategory(
    id: 'daily',
    title: '每日精选',
    match: _matchDaily,
  ),
  VideoHomeCategory(
    id: 'oral',
    title: '口语实战',
    match: _matchOral,
  ),
  VideoHomeCategory(
    id: 'ted',
    title: 'TED / 演讲',
    match: _matchTed,
  ),
  VideoHomeCategory(
    id: 'news',
    title: '新闻听力',
    match: _matchNews,
  ),
  VideoHomeCategory(
    id: 'pron',
    title: '发音课',
    match: _matchPron,
  ),
  VideoHomeCategory(
    id: 'series',
    title: '课程连载',
    match: _matchSeries,
  ),
  VideoHomeCategory(
    id: 'clips',
    title: '影视片段',
    match: _matchClips,
  ),
];

String _hay(LibraryCourseData c) =>
    '${c.title} ${c.description} ${c.category} ${c.sourceLabel}'.toLowerCase();

bool _matchTed(LibraryCourseData c) {
  final String h = _hay(c);
  return h.contains('ted') || h.contains('演讲') || h.contains('talk');
}

bool _matchOral(LibraryCourseData c) {
  final String h = _hay(c);
  return h.contains('口语') ||
      h.contains('对话') ||
      h.contains('conversation') ||
      h.contains('dialogue') ||
      h.contains('vlog') ||
      h.contains('情景');
}

bool _matchNews(LibraryCourseData c) {
  final String h = _hay(c);
  return h.contains('新闻') ||
      h.contains('news') ||
      h.contains('voa') ||
      h.contains('bbc');
}

bool _matchPron(LibraryCourseData c) {
  final String h = _hay(c);
  return h.contains('发音') ||
      h.contains('pronounc') ||
      h.contains('音标') ||
      h.contains('phonics');
}

bool _matchSeries(LibraryCourseData c) => c.totalEpisodes >= 3;

bool _matchClips(LibraryCourseData c) {
  final String h = _hay(c);
  return h.contains('影视') ||
      h.contains('片段') ||
      h.contains('剧') ||
      h.contains('movie') ||
      h.contains('film') ||
      h.contains('clip');
}

bool _matchDaily(LibraryCourseData c) => true;

List<LibraryCourseData> coursesForVideoCategory({
  required VideoHomeCategory category,
  required List<LibraryCourseData> all,
  required Set<String> claimed,
  int limit = 4,
}) {
  final List<LibraryCourseData> hit = <LibraryCourseData>[];
  for (final LibraryCourseData course in all) {
    if (claimed.contains(course.id)) continue;
    if (!category.match(course)) continue;
    hit.add(course);
    if (hit.length >= limit) break;
  }
  // Daily picks: fill from remaining if keyword buckets ate everything.
  if (hit.isEmpty && category.id == 'daily') {
    for (final LibraryCourseData course in all) {
      if (claimed.contains(course.id)) continue;
      hit.add(course);
      if (hit.length >= limit) break;
    }
  }
  return hit;
}

bool courseLooksBilingual(LibraryCourseData course) {
  if (course.episodes.isEmpty) {
    return course.spokenLanguage == 'auto' || course.spokenLanguage.isEmpty;
  }
  return course.episodes.any(
    (LibraryEpisodeItem e) => e.hasChineseSubtitles && e.hasEnglishSubtitles,
  );
}

class VideoHomeCategoriesView extends StatelessWidget {
  const VideoHomeCategoriesView({
    required this.courses,
    required this.onOpenCourse,
    required this.onMore,
    this.onSearchTap,
    this.onFilesTap,
    super.key,
  });

  final List<LibraryCourseData> courses;
  final ValueChanged<LibraryCourseData> onOpenCourse;
  final ValueChanged<VideoHomeCategory> onMore;
  final VoidCallback? onSearchTap;
  final VoidCallback? onFilesTap;

  @override
  Widget build(BuildContext context) {
    final Set<String> claimed = <String>{};
    final List<(VideoHomeCategory, List<LibraryCourseData>)> rows =
        <(VideoHomeCategory, List<LibraryCourseData>)>[];
    for (final VideoHomeCategory cat in kVideoHomeCategories) {
      final List<LibraryCourseData> slice = coursesForVideoCategory(
        category: cat,
        all: courses,
        claimed: claimed,
      );
      if (cat.id != 'daily') {
        for (final LibraryCourseData c in slice) {
          claimed.add(c.id);
        }
      }
      if (slice.isNotEmpty) {
        rows.add((cat, slice));
      }
    }

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ShellTopChrome(
                  searchHint: '搜索视频',
                  onSearchTap: onSearchTap,
                  onFilesTap: onFilesTap,
                  showNotifications: false,
                  filesLabeled: true,
                ),
                Text(
                  '视频',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '精选 · B站 / YouTube',
                  style: TextStyle(
                    color: AppDesignTokens.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
        if (rows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 96),
              child: Text(
                '还没有视频。点右上角「本地文件」导入，或从 B站 / YouTube 添加。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppDesignTokens.textSecondary),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 22),
              itemBuilder: (BuildContext context, int index) {
                final (VideoHomeCategory cat, List<LibraryCourseData> slice) =
                    rows[index];
                return _CategoryBlock(
                  title: cat.title,
                  courses: slice,
                  onMore: () => onMore(cat),
                  onOpenCourse: onOpenCourse,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.title,
    required this.courses,
    required this.onMore,
    required this.onOpenCourse,
  });

  final String title;
  final List<LibraryCourseData> courses;
  final VoidCallback onMore;
  final ValueChanged<LibraryCourseData> onOpenCourse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppDesignTokens.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(
                foregroundColor: AppDesignTokens.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '更多',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double gap = 12;
            final double cardW = (constraints.maxWidth - gap) / 2;
            final double cardH = cardW * 9 / 16;
            final List<LibraryCourseData> shown = courses.take(4).toList();
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (final LibraryCourseData course in shown)
                  SizedBox(
                    width: cardW,
                    height: cardH,
                    child: _VideoHomeCard(
                      course: course,
                      bilingual: courseLooksBilingual(course),
                      onTap: () => onOpenCourse(course),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _VideoHomeCard extends StatelessWidget {
  const _VideoHomeCard({
    required this.course,
    required this.bilingual,
    required this.onTap,
  });

  final LibraryCourseData course;
  final bool bilingual;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              LibraryCoursePoster(
                title: libraryCourseDisplayTitle(course),
                path: course.coverImage,
                borderRadius: BorderRadius.circular(14),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x00000000),
                      Color(0xCC000000),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: bilingual
                        ? const Color(0xFF22C55E)
                        : Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    bilingual ? '双语' : '仅英',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(
                  libraryCourseDisplayTitle(course),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
