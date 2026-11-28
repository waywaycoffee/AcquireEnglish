import 'dart:convert';

/// Plain records parsed from Standard Ebooks, Book Dash, and VOA Learning English.
/// Network I/O stays in [ReadingCatalogClient].

class StandardEbooksBrowse {
  const StandardEbooksBrowse({required this.books, required this.lastPage});

  final List<StandardEbookRef> books;
  final int lastPage;
}

class StandardEbookRef {
  const StandardEbookRef({
    required this.path,
    required this.title,
    required this.author,
  });

  /// Site path after `/ebooks/`, e.g. `jane-austen/pride-and-prejudice`.
  final String path;
  final String title;
  final String author;
}

class BookDashRef {
  const BookDashRef({required this.slug, required this.title});

  final String slug;
  final String title;
}

class BookDashText {
  const BookDashText({required this.title, required this.body});

  final String title;
  final String body;
}

class VoaSection {
  const VoaSection({
    required this.id,
    required this.title,
    required this.level,
    required this.feedPath,
  });

  final String id;
  final String title;
  final String level;

  /// Path on learningenglish.voanews.com, starting with `/api/`.
  final String feedPath;
}

class VoaFeedItem {
  const VoaFeedItem({
    required this.id,
    required this.title,
    required this.url,
    required this.summary,
  });

  final String id;
  final String title;
  final String url;
  final String summary;
}

class VoaArticle {
  const VoaArticle({
    required this.title,
    required this.text,
    required this.wireService,
  });

  final String title;
  final String text;

  /// True when the page byline is a news-agency credit, not a VOA script.
  final bool wireService;
}

/// VOA Learning English sections whose scripts are produced by VOA.
const List<VoaSection> kVoaLearningSections = <VoaSection>[
  VoaSection(
    id: 'words',
    title: 'Words and Their Stories',
    level: 'B1',
    feedPath: '/api/zmypyl-vomx-tpeyry_',
  ),
  VoaSection(
    id: 'health',
    title: 'Health & Lifestyle',
    level: 'B1',
    feedPath: '/api/zmmpql-vomx-tpey-_q',
  ),
  VoaSection(
    id: 'science',
    title: 'Science & Technology',
    level: 'B1',
    feedPath: '/api/zmg_pl-vomx-tpeymtm',
  ),
  VoaSection(
    id: 'asitis',
    title: 'As It Is',
    level: 'B1',
    feedPath: '/api/zkm-ql-vomx-tpej-rqi',
  ),
  VoaSection(
    id: 'stories',
    title: 'American Stories',
    level: 'B1',
    feedPath: '/api/zyg__l-vomx-tpetmty',
  ),
  VoaSection(
    id: 'arts',
    title: 'Arts & Culture',
    level: 'B1',
    feedPath: '/api/zpyp_l-vomx-tpe_rym',
  ),
  VoaSection(
    id: 'education',
    title: 'Education',
    level: 'B1',
    feedPath: '/api/ztmp_l-vomx-tpek-__',
  ),
  VoaSection(
    id: 'grammar',
    title: 'Everyday Grammar',
    level: 'B1',
    feedPath: '/api/zoroqql-vomx-tpeptpqq',
  ),
  VoaSection(
    id: 'america',
    title: 'All About America',
    level: 'B1',
    feedPath: '/api/zbmroml-vomx-tpeqboo_',
  ),
  VoaSection(
    id: 'parks',
    title: "America's National Parks",
    level: 'B1',
    feedPath: '/api/zqmiqol-vomx-tpei-mqp',
  ),
  VoaSection(
    id: 'history',
    title: 'U.S. History',
    level: 'B2',
    feedPath: '/api/zj_pvl-vomx-tpebb_v',
  ),
];

const String kBookDashTreeUrl =
    'https://api.github.com/repos/bookdash/bookdash-books/git/trees/gh-pages?recursive=1';

/// Placeholder `index.md` files in the Book Dash repo are 462 bytes and have no story.
const int kBookDashMinTextBytes = 800;

const String kVoaCredit =
    'Source: VOA Learning English (learningenglish.voanews.com).';

String bookDashRawUrl(String slug) =>
    'https://raw.githubusercontent.com/bookdash/bookdash-books/gh-pages/$slug/en/index.md';

String bookDashPageUrl(String slug) => 'https://bookdash.org/books/$slug/';

String standardEbooksBrowseUrl(int page) =>
    'https://standardebooks.org/ebooks?per-page=48&view=list&page=$page';

String decodeHtmlEntities(String input) {
  final String named = input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&rsquo;', '’')
      .replaceAll('&lsquo;', '‘')
      .replaceAll('&rdquo;', '”')
      .replaceAll('&ldquo;', '“')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–')
      .replaceAll('&amp;', '&');
  return named.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);|&#(\d+);'), (
    Match m,
  ) {
    final String hex = m.group(1) ?? '';
    final String dec = m.group(2) ?? '';
    final int? code = hex.isNotEmpty
        ? int.tryParse(hex, radix: 16)
        : int.tryParse(dec);
    if (code == null || code < 0 || code > 0x10FFFF) return m.group(0) ?? '';
    return String.fromCharCode(code);
  });
}

String _stripTags(String html) {
  final String withBreaks = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n');
  return decodeHtmlEntities(withBreaks.replaceAll(RegExp(r'<[^>]+>'), ' '))
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .trim();
}

StandardEbooksBrowse parseStandardEbooksBrowsePage(String html) {
  final RegExp bookRe = RegExp(
    r'<li typeof="schema:Book" about="([^"]+)"[\s\S]*?<span property="schema:name">([^<]+)</span>[\s\S]*?class="author"[\s\S]*?<span property="schema:name">([^<]+)</span>',
  );
  final List<StandardEbookRef> books = <StandardEbookRef>[];
  for (final RegExpMatch m in bookRe.allMatches(html)) {
    var path = decodeHtmlEntities(m.group(1) ?? '').replaceAll(
      RegExp(r'\s+'),
      '',
    );
    if (path.startsWith('/ebooks/')) path = path.substring('/ebooks/'.length);
    path = path.replaceAll(RegExp(r'^/+|/+$'), '');
    final String title = decodeHtmlEntities(m.group(2) ?? '').trim();
    final String author = decodeHtmlEntities(m.group(3) ?? '').trim();
    if (path.isEmpty || title.isEmpty) continue;
    books.add(StandardEbookRef(path: path, title: title, author: author));
  }
  var lastPage = 1;
  for (final RegExpMatch m in RegExp(
    r'(?<![\w-])page=(\d+)',
  ).allMatches(html)) {
    final int n = int.tryParse(m.group(1) ?? '') ?? 1;
    if (n > lastPage) lastPage = n;
  }
  if (lastPage > 200) lastPage = 200;
  return StandardEbooksBrowse(books: books, lastPage: lastPage);
}

List<BookDashRef> parseBookDashTree(String raw) {
  final Object? decoded = jsonDecode(raw);
  if (decoded is! Map) return const <BookDashRef>[];
  final Object? tree = decoded['tree'];
  if (tree is! List) return const <BookDashRef>[];
  final RegExp pathRe = RegExp(r'^([a-z0-9-]+)/en/index\.md$');
  final List<BookDashRef> out = <BookDashRef>[];
  for (final Object? item in tree) {
    if (item is! Map) continue;
    if ('${item['type']}' != 'blob') continue;
    final String path = '${item['path'] ?? ''}';
    final Match? m = pathRe.firstMatch(path);
    if (m == null) continue;
    final int size = (item['size'] as num?)?.toInt() ?? 0;
    if (size < kBookDashMinTextBytes) continue;
    final String slug = m.group(1) ?? '';
    if (slug.isEmpty) continue;
    out.add(BookDashRef(slug: slug, title: bookDashTitleFromSlug(slug)));
  }
  out.sort(
    (BookDashRef a, BookDashRef b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );
  return out;
}

String bookDashTitleFromSlug(String slug) {
  const Set<String> small = <String>{
    'a',
    'an',
    'the',
    'of',
    'and',
    'or',
    'to',
    'in',
    'on',
    'for',
  };
  const Map<String, String> special = <String, String>{
    'mr': 'Mr',
    'mrs': 'Mrs',
    'dr': 'Dr',
  };
  final List<String> parts = slug
      .split('-')
      .where((String p) => p.isNotEmpty)
      .toList();
  return <String>[
    for (int i = 0; i < parts.length; i++)
      special[parts[i]] ??
          (i > 0 && small.contains(parts[i])
              ? parts[i]
              : '${parts[i][0].toUpperCase()}${parts[i].substring(1)}'),
  ].join(' ');
}

BookDashText parseBookDashMarkdown(String raw) {
  String text = raw.replaceAll('\r\n', '\n');
  String title = '';
  final Match? fm = RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n').firstMatch(text);
  if (fm != null) {
    final String yaml = fm.group(1) ?? '';
    title =
        RegExp(
          r'^title:\s*(.+)$',
          multiLine: true,
        ).firstMatch(yaml)?.group(1)?.trim() ??
        '';
    title = title.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
    text = text.substring(fm.end);
  }
  final List<String> lines = <String>[];
  for (final String line in text.split('\n')) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      lines.add('');
      continue;
    }
    if (trimmed.startsWith('![')) continue;
    if (trimmed.startsWith('#')) {
      if (title.isEmpty || title == 'Title') {
        title = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      }
      continue;
    }
    lines.add(trimmed);
  }
  final String body = _collapseBlankLines(lines);
  if (title == 'Title') title = '';
  return BookDashText(title: title, body: body);
}

Map<String, String> parseBookDashCredits(String html) {
  final Map<String, String> out = <String, String>{};
  final RegExp re = RegExp(
    r'<span class="txt-bold">([^<]+)</span>\s*\((Writer|Illustrator|Designer|Editor)\)',
  );
  for (final RegExpMatch m in re.allMatches(html)) {
    final String role = (m.group(2) ?? '').toLowerCase();
    final String name = decodeHtmlEntities(m.group(1) ?? '').trim();
    if (role.isEmpty || name.isEmpty || out.containsKey(role)) continue;
    out[role] = name;
  }
  return out;
}

String bookDashAttribution({
  required String slug,
  required Map<String, String> credits,
}) {
  final List<String> names = <String>[
    if ((credits['writer'] ?? '').isNotEmpty) '${credits['writer']} (Writer)',
    if ((credits['illustrator'] ?? '').isNotEmpty)
      '${credits['illustrator']} (Illustrator)',
    if ((credits['designer'] ?? '').isNotEmpty)
      '${credits['designer']} (Designer)',
    if ((credits['editor'] ?? '').isNotEmpty) '${credits['editor']} (Editor)',
  ];
  final String created = names.isEmpty
      ? 'Book Dash volunteers'
      : names.join(', ');
  return 'Originally published by Book Dash under a Creative Commons CC BY 4.0 license. '
      'This book can be read for free on https://bookdash.org/books/$slug/ '
      'and was created by $created. '
      'Illustrations omitted; this text version is for reading practice in 爱快英语.';
}

List<VoaFeedItem> parseVoaRss(String xml) {
  final Map<String, VoaFeedItem> byTitle = <String, VoaFeedItem>{};
  final RegExp itemRe = RegExp(r'<item>([\s\S]*?)</item>');
  for (final RegExpMatch m in itemRe.allMatches(xml)) {
    final String body = m.group(1) ?? '';
    final String title = _rssTag(body, 'title');
    final String link = _rssTag(body, 'link');
    final String summary = _rssTag(body, 'description');
    if (title.isEmpty || link.isEmpty) continue;
    final Uri? uri = Uri.tryParse(link);
    if (uri == null || uri.host != 'learningenglish.voanews.com') continue;
    if (!RegExp(r'^/a/(?:[a-z0-9-]+/)?\d+\.html$').hasMatch(uri.path)) {
      continue;
    }
    final String id =
        RegExp(r'(\d+)\.html$').firstMatch(uri.path)?.group(1) ?? '';
    if (id.isEmpty) continue;
    final VoaFeedItem next = VoaFeedItem(
      id: id,
      title: title,
      url: uri.replace(query: '').toString(),
      summary: summary,
    );
    final String key = title.toLowerCase();
    final VoaFeedItem? prev = byTitle[key];
    if (prev == null || _preferVoaItem(next, prev)) byTitle[key] = next;
  }
  return byTitle.values.toList(growable: false);
}

bool _preferVoaItem(VoaFeedItem next, VoaFeedItem prev) {
  final bool nextSlug =
      next.url.contains('/a/') && !RegExp(r'/a/\d+\.html$').hasMatch(next.url);
  final bool prevSlug =
      prev.url.contains('/a/') && !RegExp(r'/a/\d+\.html$').hasMatch(prev.url);
  if (nextSlug != prevSlug) return nextSlug;
  return next.summary.length > prev.summary.length;
}

String _rssTag(String body, String name) {
  final Match? m = RegExp('<$name[^>]*>([\\s\\S]*?)</$name>').firstMatch(body);
  if (m == null) return '';
  var value = m.group(1) ?? '';
  value = value.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
  return decodeHtmlEntities(value).replaceAll(RegExp(r'\s+'), ' ').trim();
}

VoaArticle parseVoaArticle(String html) {
  final String title = _stripTags(
    RegExp(
          r'<title>([\s\S]*?)</title>',
          caseSensitive: false,
        ).firstMatch(html)?.group(1) ??
        '',
  ).replaceFirst(RegExp(r'\s*\|\s*VOA.*$', caseSensitive: false), '').trim();
  final bool wire = _voaBylineIsWire(html);
  final int start = html.indexOf('class="wsw"');
  if (start < 0) {
    return VoaArticle(title: title, text: '', wireService: wire);
  }
  var end = html.indexOf('footer-toolbar', start);
  if (end < 0) end = html.indexOf('content-sharing', start);
  if (end < 0) end = html.length;
  final String slice = html.substring(start, end);
  final List<String> parts = <String>[];
  final RegExp blockRe = RegExp(
    r'<h2[^>]*>([\s\S]*?)</h2>|<p[^>]*>([\s\S]*?)</p>',
    caseSensitive: false,
  );
  for (final RegExpMatch m in blockRe.allMatches(slice)) {
    final String raw = m.group(1) ?? m.group(2) ?? '';
    final String text = _stripTags(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length < 2) continue;
    if (_voaNoise(text)) continue;
    parts.add(text);
  }
  return VoaArticle(
    title: title,
    text: parts.join('\n\n').trim(),
    wireService: wire,
  );
}

bool _voaBylineIsWire(String html) {
  final String byline =
      RegExp(r'byline:"([^"]*)"').firstMatch(html)?.group(1)?.toLowerCase() ??
      '';
  const List<String> markers = <String>[
    'associated press',
    'reuters',
    'agence france',
    'afp',
  ];
  return markers.any(byline.contains);
}

bool _voaNoise(String text) {
  final String lower = text.toLowerCase();
  const List<String> noise = <String>[
    'no media source currently available',
    'direct link',
    'pop-out player',
    'download audio',
  ];
  return noise.any(lower.contains) && text.length < 80;
}

String _collapseBlankLines(List<String> lines) {
  final StringBuffer buf = StringBuffer();
  var blank = false;
  for (final String line in lines) {
    if (line.isEmpty) {
      blank = true;
      continue;
    }
    if (buf.isNotEmpty) buf.write(blank ? '\n\n' : ' ');
    blank = false;
    buf.write(line);
  }
  return buf.toString().trim();
}
