import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../sync/data/acquire_api_client.dart';

/// Client-side YouTube education discovery (needs a working network / VPN).
class YoutubeEducationDiscovery {
  const YoutubeEducationDiscovery();

  static final RegExp _cjk = RegExp(
    r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]',
  );

  static const List<String> blockTitleKeywords = <String>[
    'breaking news',
    'world news',
    'live news',
    'election',
    'political',
    'politics',
    'trump',
    'biden',
    'war in',
    'military',
    'protest',
    'ukraine',
    'russia ukraine',
    'gaza',
    'israel hamas',
    'cnn',
    'fox news',
    'msnbc',
    'bbc news',
    'cctv',
    '时政',
    '新闻',
    '政治',
    '两会',
    '军事',
    '战争',
  ];

  static const List<String> newsAuthors = <String>[
    'bbc news',
    'cnn',
    'fox news',
    'msnbc',
    'sky news',
    'al jazeera',
    'reuters',
    'associated press',
    'cctv',
    'cgtn',
    'nhk world',
  ];

  static const List<String> allowAuthors = <String>[
    'bbc learning english',
    'voa learning english',
    'english with lucy',
    'speak english with vanessa',
    'mmmenglish',
    "rachel's english",
    'engvid',
    'oxford online english',
    'cambridge english',
    'british council | learnenglish',
    'englishclass101.com',
    'learn english with tv series',
    'english speaking success',
    'shaw english online',
    'espresso english',
    'easy english',
    'ted-ed',
    'english with jennifer',
    'anglo-link',
    'papa teach me',
    'to fluency',
    'interactive english',
    'english like a native',
    "accent's way english with hadar",
    'learn english open doors',
    'business english pod',
    'englishanyone',
    'speak english with tiffani',
    'learn english with jessica',
    'english fluency journey',
  ];

  static const List<String> eduMarkers = <String>[
    'english',
    'esl',
    'efl',
    'grammar',
    'vocabulary',
    'pronunciation',
    'listening',
    'conversation',
    'cefr',
    'a1',
    'a2',
    'b1',
    'b2',
    'c1',
    'c2',
    'learn english',
    'speaking practice',
    'ted-ed',
    'ted ed',
  ];

  static bool hasCjk(String text) => _cjk.hasMatch(text);

  static bool passesFilters({
    required String title,
    required String author,
  }) {
    if (hasCjk(title) || hasCjk(author)) return false;
    final String titleL = title.toLowerCase();
    final String authorL = author.toLowerCase().trim();
    for (final String kw in blockTitleKeywords) {
      if (titleL.contains(kw) || authorL.contains(kw)) return false;
    }
    for (final String n in newsAuthors) {
      if (authorL == n || authorL.startsWith('$n ')) return false;
    }
    final bool allowed = allowAuthors.contains(authorL);
    if (!allowed && !eduMarkers.any(titleL.contains)) {
      return false;
    }
    return true;
  }

  /// Search YouTube via the device network (VPN) and return filtered hits.
  Future<List<AcquireDailyFeedItemDto>> searchEducation({
    required List<String> queries,
    int perQuery = 8,
    int maxTotal = 36,
  }) async {
    final YoutubeExplode yt = YoutubeExplode();
    final List<AcquireDailyFeedItemDto> out = <AcquireDailyFeedItemDto>[];
    final Set<String> seen = <String>{};
    try {
      for (final String q in queries) {
        if (q.trim().isEmpty) continue;
        try {
          final VideoSearchList page = await yt.search.search(q.trim());
          for (final Video video in page.take(perQuery)) {
            final String id = video.id.value;
            if (id.isEmpty || seen.contains(id)) continue;
            final String title = video.title;
            final String author = video.author;
            if (!passesFilters(title: title, author: author)) continue;
            if (video.isLive) continue;
            seen.add(id);
            out.add(
              AcquireDailyFeedItemDto(
                id: 'yt-$id',
                bvid: id,
                title: title,
                author: author,
                authorId: video.channelId.value,
                coverUrl: video.thumbnails.highResUrl,
                durationSec: video.duration?.inSeconds.toDouble(),
                watchUrl: 'https://www.youtube.com/watch?v=$id',
                description: video.description,
                tags: const <String>['youtube_education', 'live'],
                source: 'youtube',
                reason: 'youtube_browse',
              ),
            );
            if (out.length >= maxTotal) {
              return out;
            }
          }
        } catch (_) {
          // Query failed (often no VPN) — try next seed.
        }
      }
    } finally {
      yt.close();
    }
    return out;
  }
}
