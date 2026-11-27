import 'package:flutter/material.dart';

import '../../../constants/assets.dart';
import '../domain/syllabus_book.dart';
import 'word_book_library_theme.dart';

/// Standing hardcover used on the 词书 library shelves.
class WordBookCover extends StatelessWidget {
  const WordBookCover({
    required this.title,
    this.badge = '',
    this.progressLabel = '',
    this.width = 78,
    this.height = 132,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final String title;
  final String badge;
  final String progressLabel;
  final double width;
  final double height;
  final bool selected;
  final VoidCallback? onTap;

  String? get _coverAsset {
    if (title == kSceneMemoryBookTitle || title.contains('情景记忆')) {
      return Assets.wordBookSceneMemory;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String? coverAsset = _coverAsset;
    if (coverAsset != null) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: width,
          height: height,
          transform: Matrix4.translationValues(0, selected ? -6 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.35 : 0.22),
                blurRadius: selected ? 12 : 8,
                offset: Offset(selected ? 4 : 3, selected ? 6 : 4),
              ),
            ],
            border: selected
                ? Border.all(color: const Color(0xFFF2E6DA), width: 2)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.asset(
                  coverAsset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
                if (progressLabel.isNotEmpty)
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: Text(
                      progressLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        shadows: const <Shadow>[
                          Shadow(blurRadius: 4, color: Colors.black54),
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

    final Color color = WordBookLibraryTheme.coverColor(title);
    final bool lightInk = color.computeLuminance() > 0.55;
    final Color ink = lightInk ? const Color(0xFF3A2212) : Colors.white;
    final Color muted = lightInk
        ? const Color(0xFF3A2212).withValues(alpha: 0.65)
        : Colors.white70;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        height: height,
        transform: Matrix4.translationValues(0, selected ? -6 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.35 : 0.22),
              blurRadius: selected ? 12 : 8,
              offset: Offset(selected ? 4 : 3, selected ? 6 : 4),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[
              Color.lerp(color, Colors.black, 0.18)!,
              color,
              Color.lerp(color, Colors.white, 0.06)!,
            ],
            stops: const <double>[0, 0.1, 1],
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(left: 5),
          padding: const EdgeInsets.fromLTRB(8, 10, 7, 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
              top: selected
                  ? const BorderSide(color: Color(0xFFF2E6DA), width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                badge.isEmpty ? 'WORD' : badge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: muted,
                  fontSize: 9,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontFamily: 'serif',
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (progressLabel.isNotEmpty)
                Text(
                  progressLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 10),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
