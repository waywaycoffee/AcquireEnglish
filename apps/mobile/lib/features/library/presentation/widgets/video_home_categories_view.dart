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

bool _matchDaily(LibraryCourseData c) => true;

List<LibraryCourseData> coursesForVideoCategory({
  required VideoHomeCategory category,
  required List<LibraryCourseData> all,
  required Set<String> claimed,
  int limit = 8,
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
    super.key,
  });

  final List<LibraryCourseData> courses;
  final ValueChanged<LibraryCourseData> onOpenCourse;
  final ValueChanged<VideoHomeCategory> onMore;

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: <Widget>[
        const ShellTopChrome(searchHint: '搜索视频'),
        Text(
          '视频',
          style: TextStyle(
            color: AppDesignTokens.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w900,
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
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text(
              '还没有视频。点右上角文件夹导入，或从 B站 / YouTube 添加。',
              style: TextStyle(color: AppDesignTokens.textSecondary),
            ),
          )
        else
          for (final (VideoHomeCategory cat, List<LibraryCourseData> slice)
              in rows) ...<Widget>[
            _SectionHeader(
              title: cat.title,
              onMore: () => onMore(cat),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 148,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: slice.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int index) {
                  final LibraryCourseData course = slice[index];
                  return _VideoHomeCard(
                    course: course,
                    bilingual: courseLooksBilingual(course),
                    onTap: () => onOpenCourse(course),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
          ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onMore});

  final String title;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
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
          child: Text(
            '更多',
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
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
    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
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
                      if (bilingual)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '双语',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        )
                      else
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '仅英',
                              style: TextStyle(
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
            ],
          ),
        ),
      ),
    );
  }
}
