import 'package:flutter/material.dart';

/// Stable title-based cover for built-in and imported books.
class ReadingBookCover extends StatelessWidget {
  const ReadingBookCover({required this.title, this.level = '', super.key});
  final String title;
  final String level;

  @override
  Widget build(BuildContext context) {
    const List<Color> palette = <Color>[
      Color(0xFF315B50), Color(0xFF66455F), Color(0xFFAD6842),
      Color(0xFF384F74), Color(0xFF77623C),
    ];
    final int seed = title.runes.fold<int>(0, (int value, int rune) => value + rune);
    final Color color = palette[seed % palette.length];
    return AspectRatio(
      aspectRatio: 0.68,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x30000000), blurRadius: 8, offset: Offset(3, 4)),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(7, 0, 0, 0),
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0x44FFFFFF))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(level.isEmpty ? 'ENGLISH' : level,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
              const Spacer(),
              Text(title, maxLines: 4, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontFamily: 'Georgia',
                  fontSize: 17, height: 1.2, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Divider(color: Colors.white54),
              const Text('ACQUIRE READING', style: TextStyle(color: Colors.white70, fontSize: 8)),
            ],
          ),
        ),
      ),
    );
  }
}
