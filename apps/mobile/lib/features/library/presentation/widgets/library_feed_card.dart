import 'package:flutter/material.dart';

import '../../../player/presentation/widgets/study_shell_tokens.dart';
import '../library_mock_data.dart';
import 'library_course_poster.dart';

/// Shadow Talk–style dark weekly feed card.
class LibraryFeedCard extends StatelessWidget {
  const LibraryFeedCard({
    required this.course,
    required this.index,
    required this.onTap,
    this.onContextMenu,
    super.key,
  });

  final LibraryCourseData course;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;

  String get _weekLabel {
    if (course.category.toLowerCase().contains('bilibili') ||
        course.sourceLabel.toLowerCase().contains('bilibili')) {
      return '第 ${index + 1} 集';
    }
    return '第 ${index + 1} 周';
  }

  String get _durationLabel {
    final int minutes = course.episodes.isEmpty
        ? 0
        : course.episodes.first.durationMinutes;
    if (minutes <= 0) {
      return '';
    }
    final int m = minutes;
    final int s = (minutes * 60) % 60;
    if (m >= 60) {
      return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:00';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get _sourceBadge {
    final String raw = course.sourceLabel.trim();
    if (raw.isEmpty) {
      return '@${course.category}';
    }
    return raw.startsWith('@') ? raw : '@$raw';
  }

  List<String> get _tags {
    final List<String> tags = <String>[
      if (course.level.trim().isNotEmpty) course.level,
      if (course.category.trim().isNotEmpty) course.category,
    ];
    return tags.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final StudyShellColors colors = StudyShellColors.dark;
    final int filledStars = course.rating.round().clamp(0, 5);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onSecondaryTapDown: onContextMenu == null
            ? null
            : (TapDownDetails details) =>
                  onContextMenu!(details.globalPosition),
        onLongPressStart: onContextMenu == null
            ? null
            : (LongPressStartDetails details) =>
                  onContextMenu!(details.globalPosition),
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      LibraryCoursePoster(
                        title: course.title,
                        path: course.coverImage,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color(0x00000000),
                              Color(0x99000000),
                            ],
                          ),
                        ),
                      ),
                      if (_durationLabel.isNotEmpty)
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _durationLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _sourceBadge,
                            style: TextStyle(
                              color: colors.accentOn,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _weekLabel,
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                course.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              if (course.description.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  course.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              if (_tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _tags.join('  '),
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  ...List<Widget>.generate(5, (int i) {
                    return Icon(
                      i < filledStars
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 16,
                      color: i < filledStars
                          ? const Color(0xFFF5C542)
                          : colors.textMuted,
                    );
                  }),
                  const SizedBox(width: 6),
                  Text(
                    course.rating.toStringAsFixed(1),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    course.lastStudiedStr,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
