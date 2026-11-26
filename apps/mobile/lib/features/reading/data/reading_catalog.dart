import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

import '../../../constants/endpoints.dart';
import '../domain/reading_doc.dart';
import '../domain/reading_title_zh.dart';
import 'reading_cover_cache.dart';
import 'reading_ingest.dart';

enum ReadingCatalogKind {
  onestop,
  cefr,
  magic,
  standardebooks,
  readseasy,
  clickbook,
}

class ReadingCatalogSource {
  const ReadingCatalogSource({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.licenseNote,
    this.externalUrl,
    this.downloadable = true,
  });

  final ReadingCatalogKind kind;
  final String title;
  final String subtitle;
  final String licenseNote;
  final String? externalUrl;
  final bool downloadable;
}

const List<ReadingCatalogSource>
kReadingCatalogSources = <ReadingCatalogSource>[
  ReadingCatalogSource(
    kind: ReadingCatalogKind.onestop,
    title: 'OneStopEnglish',
    subtitle: '新闻分级短文 · 初/中/高三档对齐',
    licenseNote:
        'CC BY-SA 4.0 · github.com/nishkalavallabhi/OneStopEnglishCorpus',
  ),
  ReadingCatalogSource(
    kind: ReadingCatalogKind.cefr,
    title: 'CEFR Levelled Texts',
    subtitle: '约 1500 篇 A1–C2 短文（导入 Kaggle CSV 或加载缓存）',
    licenseNote: '数据集标 CC0；请从 Kaggle 下载 cefr_leveled_texts.csv 后导入。仅供个人学习。',
    externalUrl:
        'https://www.kaggle.com/datasets/amontgomerie/cefr-levelled-english-texts',
  ),
  ReadingCatalogSource(
    kind: ReadingCatalogKind.magic,
    title: 'Magic English Buddy',
    subtitle: '儿童分级故事 L1–L7（按需下载）',
    licenseNote: 'CC BY-NC-SA 4.0 · 非商用；署名分享一致。仅个人学习。',
    externalUrl: 'https://github.com/xckevin/magic-english-buddy',
  ),
  ReadingCatalogSource(
    kind: ReadingCatalogKind.standardebooks,
    title: 'Standard Ebooks',
    subtitle: '公版精排 EPUB · 新书 + 经典精选',
    licenseNote: '文本公版；排版 CC0 · standardebooks.org',
    externalUrl: 'https://standardebooks.org/ebooks',
  ),
  ReadingCatalogSource(
    kind: ReadingCatalogKind.readseasy,
    title: 'Readseasy',
    subtitle: 'A2/B1/B2 简易分级读物站（外链打开）',
    licenseNote: '第三方网站；请在站内按其条款下载 EPUB，再用「导入」加入书架。',
    externalUrl: 'https://readseasy.com/library/english',
    downloadable: false,
  ),
  ReadingCatalogSource(
    kind: ReadingCatalogKind.clickbook,
    title: 'ClickBook',
    subtitle: '按 CEFR 词覆盖度整理的公版书目录（外链）',
    licenseNote: '第三方目录（多为 Standard Ebooks）；外链浏览后可回 App 导入 EPUB。',
    externalUrl: 'https://clickbook-ai.com/library/english.html',
    downloadable: false,
  ),
];

enum ReadingCatalogEntryKind { folder, article, ebook, external }

class ReadingCatalogEntry {
  const ReadingCatalogEntry({
    required this.id,
    required this.title,
    required this.kind,
    this.titleZh = '',
    this.subtitle = '',
    this.level = '',
    this.path = '',
    this.downloadUrl,
    this.externalUrl,
    this.sizeBytes = 0,
  });

  final String id;
  final String title;
  final String titleZh;
  final ReadingCatalogEntryKind kind;
  final String subtitle;
  final String level;
  final String path;
  final String? downloadUrl;
  final String? externalUrl;
  final int sizeBytes;

  String get displayTitle =>
      readingDisplayTitle(title, titleZh: titleZh);

  String get stableDocId {
    final Digest digest = sha1.convert(utf8.encode(id));
    return 'catalog_${digest.toString().substring(0, 16)}';
  }
}

/// Featured Standard Ebooks classics (direct EPUB, no OPDS auth).
const List<({String path, String title, String titleZh, String author})>
kStandardEbooksFeatured =
    <({String path, String title, String titleZh, String author})>[
  (
    path: 'l-frank-baum/the-wonderful-wizard-of-oz',
    title: 'The Wonderful Wizard of Oz',
    titleZh: '绿野仙踪',
    author: 'L. Frank Baum',
  ),
  (
    path: 'jane-austen/pride-and-prejudice',
    title: 'Pride and Prejudice',
    titleZh: '傲慢与偏见',
    author: 'Jane Austen',
  ),
  (
    path: 'mary-shelley/frankenstein',
    title: 'Frankenstein',
    titleZh: '弗兰肯斯坦',
    author: 'Mary Shelley',
  ),
  (
    path: 'bram-stoker/dracula',
    title: 'Dracula',
    titleZh: '德古拉',
    author: 'Bram Stoker',
  ),
  (
    path: 'lewis-carroll/alices-adventures-in-wonderland',
    title: 'Alice’s Adventures in Wonderland',
    titleZh: '爱丽丝漫游奇境',
    author: 'Lewis Carroll',
  ),
  (
    path: 'arthur-conan-doyle/the-adventures-of-sherlock-holmes',
    title: 'The Adventures of Sherlock Holmes',
    titleZh: '福尔摩斯探案集',
    author: 'Arthur Conan Doyle',
  ),
  (
    path: 'charles-dickens/a-christmas-carol',
    title: 'A Christmas Carol',
    titleZh: '圣诞颂歌',
    author: 'Charles Dickens',
  ),
  (
    path: 'robert-louis-stevenson/treasure-island',
    title: 'Treasure Island',
    titleZh: '金银岛',
    author: 'Robert Louis Stevenson',
  ),
  (
    path: 'jonathan-swift/gullivers-travels',
    title: 'Gulliver’s Travels',
    titleZh: '格列佛游记',
    author: 'Jonathan Swift',
  ),
  (
    path: 'mark-twain/the-adventures-of-huckleberry-finn',
    title: 'Adventures of Huckleberry Finn',
    titleZh: '哈克贝利·费恩历险记',
    author: 'Mark Twain',
  ),
  (
    path: 'herman-melville/moby-dick',
    title: 'Moby Dick',
    titleZh: '白鲸',
    author: 'Herman Melville',
  ),
];

const ReadingCatalogEntry kDefaultWizardOfOzEntry = ReadingCatalogEntry(
  id: 'se:l-frank-baum/the-wonderful-wizard-of-oz',
  title: 'The Wonderful Wizard of Oz',
  titleZh: '绿野仙踪',
  kind: ReadingCatalogEntryKind.ebook,
  subtitle: 'L. Frank Baum · 公版奇幻长篇',
  level: 'B1',
  path: 'l-frank-baum/the-wonderful-wizard-of-oz',
  externalUrl:
      'https://standardebooks.org/ebooks/l-frank-baum/the-wonderful-wizard-of-oz',
);

class ReadingCatalogClient {
  ReadingCatalogClient({Dio? dio, String apiBaseUrl = Endpoints.baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 90),
              headers: const <String, String>{
                'User-Agent': 'AcquireEnglish-ReadingCatalog',
                'Accept': '*/*',
              },
            ),
          ) {
    if (dio == null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final source = options.uri;
            if (source.host == 'api.github.com' ||
                source.host == 'raw.githubusercontent.com' ||
                source.host == 'standardebooks.org' ||
                source.host == 'github.com') {
              options.path = Uri.parse(Endpoints.normalizeBaseUrl(apiBaseUrl))
                  .resolve('api/reading/source')
                  .replace(queryParameters: {'url': source.toString()})
                  .toString();
              options.queryParameters = {};
            }
            handler.next(options);
          },
        ),
      );
    }
  }

  static const String _cefrCacheKey = 'reading_cefr_catalog_v1';
  static const String _onestopApi =
      'https://api.github.com/repos/nishkalavallabhi/OneStopEnglishCorpus/contents';
  static const String _magicApi =
      'https://api.github.com/repos/xckevin/magic-english-buddy/contents';
  static const String _seAtom =
      'https://standardebooks.org/feeds/atom/new-releases';

  final Dio _dio;
  final Map<String, List<ReadingCatalogEntry>> _cache =
      <String, List<ReadingCatalogEntry>>{};

  Future<List<ReadingCatalogEntry>> listRoot(ReadingCatalogKind kind) async {
    switch (kind) {
      case ReadingCatalogKind.onestop:
        return _listOnestopLevels();
      case ReadingCatalogKind.cefr:
        return _listCefrLevels();
      case ReadingCatalogKind.magic:
        return _listMagicLevels();
      case ReadingCatalogKind.standardebooks:
        return _listStandardEbooksRoot();
      case ReadingCatalogKind.readseasy:
      case ReadingCatalogKind.clickbook:
        return const <ReadingCatalogEntry>[];
    }
  }

  Future<List<ReadingCatalogEntry>> listPath({
    required ReadingCatalogKind kind,
    required String path,
  }) async {
    final String key = '${kind.name}::$path';
    final List<ReadingCatalogEntry>? hit = _cache[key];
    if (hit != null) return hit;

    late final List<ReadingCatalogEntry> entries;
    switch (kind) {
      case ReadingCatalogKind.onestop:
        entries = await _listGithubTxtDir(
          apiBase: _onestopApi,
          path: path,
          idPrefix: 'onestop',
          levelFromPath: _onestopLevel,
        );
      case ReadingCatalogKind.magic:
        entries = await _listMagicStories(path);
      case ReadingCatalogKind.cefr:
        entries = await _listCefrByLevel(path);
      case ReadingCatalogKind.standardebooks:
        if (path == 'new') {
          entries = await _listStandardEbooksNew();
        } else if (path == 'featured') {
          entries = _listStandardEbooksFeatured();
        } else {
          entries = const <ReadingCatalogEntry>[];
        }
      case ReadingCatalogKind.readseasy:
      case ReadingCatalogKind.clickbook:
        entries = const <ReadingCatalogEntry>[];
    }
    _cache[key] = List<ReadingCatalogEntry>.unmodifiable(entries);
    return _cache[key]!;
  }

  Future<ReadingDoc> downloadEntry({
    required ReadingCatalogKind kind,
    required ReadingCatalogEntry entry,
  }) async {
    switch (kind) {
      case ReadingCatalogKind.onestop:
        return _downloadPlainText(
          entry: entry,
          sourceLabel: 'OneStopEnglish',
          disclaimer: '来自 OneStopEnglishCorpus（CC BY-SA 4.0），仅供个人学习。',
        );
      case ReadingCatalogKind.magic:
        return _downloadMagicStory(entry);
      case ReadingCatalogKind.cefr:
        return _downloadCefrCached(entry);
      case ReadingCatalogKind.standardebooks:
        return _downloadStandardEbook(entry);
      case ReadingCatalogKind.readseasy:
      case ReadingCatalogKind.clickbook:
        throw StateError('请在浏览器打开站点后，用「导入」加入 EPUB/TXT');
    }
  }

  Future<int> importCefrCsv(Uint8List bytes) async {
    if (!Hive.isBoxOpen('prefs')) {
      throw StateError('本地存储未就绪');
    }
    final List<({String text, String label})> rows = _parseCefrRows(
      utf8.decode(bytes, allowMalformed: true),
    );
    if (rows.isEmpty) {
      throw StateError('CSV 中未识别到 text/label 列');
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (int i = 0; i < rows.length; i++)
        <String, Object?>{
          'id': 'cefr_${rows[i].label.toLowerCase()}_${i + 1}',
          'title': _cefrTitle(rows[i].text, rows[i].label, i + 1),
          'level': rows[i].label.toUpperCase(),
          'text': rows[i].text,
        },
    ];
    final Map<String, Object?> payload = <String, Object?>{
      'importedAt': DateTime.now().toIso8601String(),
      'items': items,
    };
    await Hive.box<String>('prefs').put(_cefrCacheKey, jsonEncode(payload));
    _cache.removeWhere((String k, _) => k.startsWith('cefr::'));
    return items.length;
  }

  int cachedCefrCount() {
    if (!Hive.isBoxOpen('prefs')) return 0;
    final String? raw = Hive.box<String>('prefs').get(_cefrCacheKey);
    if (raw == null || raw.isEmpty) return 0;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return 0;
      final Object? items = decoded['items'];
      return items is List ? items.length : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<ReadingCatalogEntry>> _listOnestopLevels() async {
    return const <ReadingCatalogEntry>[
      ReadingCatalogEntry(
        id: 'onestop:Ele-Txt',
        title: 'Elementary（初级）',
        kind: ReadingCatalogEntryKind.folder,
        level: 'Ele',
        path: 'Texts-SeparatedByReadingLevel/Ele-Txt',
        subtitle: '约 189 篇',
      ),
      ReadingCatalogEntry(
        id: 'onestop:Int-Txt',
        title: 'Intermediate（中级）',
        kind: ReadingCatalogEntryKind.folder,
        level: 'Int',
        path: 'Texts-SeparatedByReadingLevel/Int-Txt',
        subtitle: '约 189 篇',
      ),
      ReadingCatalogEntry(
        id: 'onestop:Adv-Txt',
        title: 'Advanced（高级）',
        kind: ReadingCatalogEntryKind.folder,
        level: 'Adv',
        path: 'Texts-SeparatedByReadingLevel/Adv-Txt',
        subtitle: '约 189 篇',
      ),
    ];
  }

  Future<List<ReadingCatalogEntry>> _listMagicLevels() async {
    return <ReadingCatalogEntry>[
      for (int i = 1; i <= 7; i++)
        ReadingCatalogEntry(
          id: 'magic:l$i',
          title: 'L$i',
          kind: ReadingCatalogEntryKind.folder,
          level: 'L$i',
          path: 'src/data/stories/l$i',
          subtitle: 'Magic English Buddy',
        ),
    ];
  }

  Future<List<ReadingCatalogEntry>> _listCefrLevels() async {
    final int n = cachedCefrCount();
    final String note = n == 0 ? '尚未导入 CSV' : '已缓存 $n 篇';
    return <ReadingCatalogEntry>[
      for (final String level in <String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2'])
        ReadingCatalogEntry(
          id: 'cefr:$level',
          title: level,
          kind: ReadingCatalogEntryKind.folder,
          level: level,
          path: level,
          subtitle: note,
        ),
    ];
  }

  Future<List<ReadingCatalogEntry>> _listStandardEbooksRoot() async {
    return const <ReadingCatalogEntry>[
      ReadingCatalogEntry(
        id: 'se:featured',
        title: '经典精选',
        kind: ReadingCatalogEntryKind.folder,
        path: 'featured',
        subtitle: '可直接下载 EPUB',
      ),
      ReadingCatalogEntry(
        id: 'se:new',
        title: '最新上架',
        kind: ReadingCatalogEntryKind.folder,
        path: 'new',
        subtitle: '来自 Atom new-releases',
      ),
    ];
  }

  Future<List<ReadingCatalogEntry>> _listGithubTxtDir({
    required String apiBase,
    required String path,
    required String idPrefix,
    required String Function(String path) levelFromPath,
  }) async {
    final String url =
        '$apiBase/${path.split('/').map(Uri.encodeComponent).join('/')}';
    final Response<dynamic> response = await _dio.get<dynamic>(
      url,
      options: Options(
        headers: const <String, String>{
          'Accept': 'application/vnd.github+json',
        },
      ),
    );
    final Object? data = response.data;
    if (data is! List) return const <ReadingCatalogEntry>[];
    final List<ReadingCatalogEntry> out = <ReadingCatalogEntry>[];
    final String level = levelFromPath(path);
    for (final Object? item in data) {
      if (item is! Map) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(item);
      final String name = '${map['name'] ?? ''}';
      final String itemPath = '${map['path'] ?? ''}';
      final String type = '${map['type'] ?? ''}';
      if (type != 'file' || !name.toLowerCase().endsWith('.txt')) continue;
      final String title = name.replaceAll(
        RegExp(r'\.txt$', caseSensitive: false),
        '',
      );
      out.add(
        ReadingCatalogEntry(
          id: '$idPrefix:$itemPath',
          title: title,
          kind: ReadingCatalogEntryKind.article,
          level: level,
          path: itemPath,
          downloadUrl: '${map['download_url'] ?? ''}'.isEmpty
              ? null
              : '${map['download_url']}',
          sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    out.sort(
      (ReadingCatalogEntry a, ReadingCatalogEntry b) =>
          a.title.compareTo(b.title),
    );
    return out;
  }

  Future<List<ReadingCatalogEntry>> _listMagicStories(String path) async {
    final String url =
        '$_magicApi/${path.split('/').map(Uri.encodeComponent).join('/')}';
    final Response<dynamic> response = await _dio.get<dynamic>(
      url,
      options: Options(
        headers: const <String, String>{
          'Accept': 'application/vnd.github+json',
        },
      ),
    );
    final Object? data = response.data;
    if (data is! List) return const <ReadingCatalogEntry>[];
    final List<ReadingCatalogEntry> out = <ReadingCatalogEntry>[];
    for (final Object? item in data) {
      if (item is! Map) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(item);
      final String name = '${map['name'] ?? ''}';
      final String itemPath = '${map['path'] ?? ''}';
      if ('${map['type']}' != 'file') continue;
      // Text story index only — never pull Magicaudio / video into the app.
      final String lower = name.toLowerCase();
      if (lower.endsWith('.mp3') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.m4a') ||
          lower.endsWith('.wav') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.ogg')) {
        continue;
      }
      if (!name.endsWith('.ts') && !name.endsWith('.json')) continue;
      if (name == 'index.ts') {
        final String dl = '${map['download_url'] ?? ''}'.trim();
        if (dl.isEmpty) continue;
        final String raw = await _getString(dl);
        out.addAll(parseMagicStoriesIndex(raw, path: itemPath));
      }
    }
    return out;
  }

  Future<List<ReadingCatalogEntry>> _listCefrByLevel(String level) async {
    final List<Map<String, String>> items = _loadCefrCache();
    final String want = level.toUpperCase();
    return <ReadingCatalogEntry>[
      for (final Map<String, String> item in items)
        if ((item['level'] ?? '').toUpperCase() == want)
          ReadingCatalogEntry(
            id: item['id'] ?? '',
            title: item['title'] ?? '',
            kind: ReadingCatalogEntryKind.article,
            level: want,
            path: item['id'] ?? '',
            subtitle: _preview(item['text'] ?? ''),
          ),
    ];
  }

  List<ReadingCatalogEntry> _listStandardEbooksFeatured() {
    return <ReadingCatalogEntry>[
      for (final ({String path, String title, String titleZh, String author}) book
          in kStandardEbooksFeatured)
        ReadingCatalogEntry(
          id: 'se:${book.path}',
          title: book.title,
          titleZh: book.titleZh,
          kind: ReadingCatalogEntryKind.ebook,
          subtitle: book.author,
          path: book.path,
          downloadUrl: _standardEbooksEpubUrl(book.path),
          externalUrl: 'https://standardebooks.org/ebooks/${book.path}',
        ),
    ];
  }

  Future<List<ReadingCatalogEntry>> _listStandardEbooksNew() async {
    final String xml = await _getString(_seAtom);
    final List<ReadingCatalogEntry> out = <ReadingCatalogEntry>[];
    final RegExp entryRe = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
    for (final RegExpMatch m in entryRe.allMatches(xml)) {
      final String body = m.group(1) ?? '';
      final String title =
          RegExp(r'<title[^>]*>([^<]+)</title>').firstMatch(body)?.group(1) ??
          '';
      final String? epub = RegExp(
        r'href="(https://standardebooks\.org/ebooks/[^"]+\.epub[^"]*)"',
      ).firstMatch(body)?.group(1);
      if (title.isEmpty || epub == null) continue;
      if (epub.contains('_advanced') || epub.contains('kepub')) continue;
      final String path = _pathFromSeEpub(epub);
      out.add(
        ReadingCatalogEntry(
          id: 'se-new:$path',
          title: title,
          titleZh: readingTitleZhFor(title) ?? '',
          kind: ReadingCatalogEntryKind.ebook,
          path: path,
          downloadUrl: epub.split('?').first,
          externalUrl: path.isEmpty
              ? null
              : 'https://standardebooks.org/ebooks/$path',
          subtitle: 'New release',
        ),
      );
    }
    return out;
  }

  Future<ReadingDoc> _downloadPlainText({
    required ReadingCatalogEntry entry,
    required String sourceLabel,
    required String disclaimer,
  }) async {
    final String url =
        entry.downloadUrl ??
        'https://raw.githubusercontent.com/nishkalavallabhi/OneStopEnglishCorpus/master/${entry.path.split('/').map(Uri.encodeComponent).join('/')}';
    final String text = (await _getString(url)).trim();
    if (text.isEmpty) throw StateError('正文为空');
    final String zh = readingTitleZhFor(entry.title, titleZh: entry.titleZh) ?? '';
    return ReadingDoc(
      id: entry.stableDocId,
      title: readingDisplayTitle(entry.title, titleZh: zh),
      titleZh: zh,
      sourceType: ReadingSourceType.catalog,
      level: entry.level,
      plainText: text,
      sourceLabel: sourceLabel,
      courseTitle: disclaimer,
      createdAt: DateTime.now(),
    );
  }

  Future<ReadingDoc> _downloadMagicStory(ReadingCatalogEntry entry) async {
    String text = entry.subtitle.trim();
    if (text.length < 20) {
      final String rawPath = entry.path.split('#').first;
      final String url =
          'https://raw.githubusercontent.com/xckevin/magic-english-buddy/main/${rawPath.split('/').map(Uri.encodeComponent).join('/')}';
      final List<ReadingCatalogEntry> stories = parseMagicStoriesIndex(
        await _getString(url),
        path: rawPath,
      );
      text = stories
          .firstWhere(
            (ReadingCatalogEntry e) => e.id == entry.id,
            orElse: () => entry,
          )
          .subtitle
          .trim();
    }
    if (text.isEmpty) throw StateError('故事正文为空');
    final String zh = readingTitleZhFor(entry.title, titleZh: entry.titleZh) ?? '';
    return ReadingDoc(
      id: entry.stableDocId,
      title: readingDisplayTitle(entry.title, titleZh: zh),
      titleZh: zh,
      sourceType: ReadingSourceType.catalog,
      level: entry.level,
      plainText: text,
      sourceLabel: 'Magic English Buddy',
      courseTitle: 'CC BY-NC-SA 4.0 · 非商用个人学习',
      createdAt: DateTime.now(),
    );
  }

  Future<ReadingDoc> _downloadCefrCached(ReadingCatalogEntry entry) async {
    final List<Map<String, String>> items = _loadCefrCache();
    final Map<String, String>? hit = items
        .cast<Map<String, String>?>()
        .firstWhere(
          (Map<String, String>? m) => m?['id'] == entry.id,
          orElse: () => null,
        );
    if (hit == null || (hit['text'] ?? '').trim().isEmpty) {
      throw StateError('请先导入 cefr_leveled_texts.csv');
    }
    final String rawTitle = hit['title'] ?? entry.title;
    final String zh = readingTitleZhFor(rawTitle, titleZh: entry.titleZh) ?? '';
    return ReadingDoc(
      id: entry.stableDocId,
      title: readingDisplayTitle(rawTitle, titleZh: zh),
      titleZh: zh,
      sourceType: ReadingSourceType.catalog,
      level: hit['level'] ?? entry.level,
      plainText: hit['text']!.trim(),
      sourceLabel: 'CEFR Levelled Texts',
      courseTitle: '来自 Kaggle CEFR Levelled English Texts · 个人学习',
      createdAt: DateTime.now(),
    );
  }

  Future<ReadingDoc> _downloadEpub({
    required ReadingCatalogEntry entry,
    required String sourceLabel,
    required String disclaimer,
  }) async {
    final String url = entry.downloadUrl ?? '';
    if (url.isEmpty) throw StateError('缺少 EPUB 下载地址');
    final Response<List<int>> response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final List<int>? data = response.data;
    if (data == null || data.isEmpty) throw StateError('EPUB 下载失败');
    final String text = parseEpubImport(Uint8List.fromList(data));
    if (text.trim().isEmpty) throw StateError('未能从 EPUB 提取正文');
    final String zh = readingTitleZhFor(entry.title, titleZh: entry.titleZh) ?? '';
    return ReadingDoc(
      id: entry.stableDocId,
      title: readingDisplayTitle(entry.title, titleZh: zh),
      titleZh: zh,
      sourceType: ReadingSourceType.catalog,
      level: entry.level,
      plainText: text,
      sourceLabel: sourceLabel,
      courseTitle: disclaimer,
      episodeTitle: entry.subtitle,
      createdAt: DateTime.now(),
    );
  }

  /// Standard Ebooks site serves an HTML interstitial instead of the EPUB bytes
  /// to non-browser clients. Pull the public GitHub source zip and extract text.
  Future<ReadingDoc> _downloadStandardEbook(ReadingCatalogEntry entry) async {
    final List<String> slugs = _standardEbooksGithubSlugs(entry.path);
    if (slugs.isEmpty) {
      throw StateError('缺少 Standard Ebooks 路径');
    }
    Object? lastError;
    for (final String slug in slugs) {
      final String url =
          'https://github.com/standardebooks/$slug/archive/refs/heads/master.zip';
      try {
        final Response<List<int>> response = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            validateStatus: (int? code) =>
                code != null && code >= 200 && code < 400,
          ),
        );
        final List<int>? data = response.data;
        if (data == null || data.isEmpty) {
          throw StateError('空响应');
        }
        final String text = parseEpubImport(Uint8List.fromList(data));
        if (text.trim().isEmpty) {
          throw StateError('未能从源码包提取正文');
        }
        final String zh =
            readingTitleZhFor(entry.title, titleZh: entry.titleZh) ?? '';
        final String? cover =
            featuredReadingCoverRelativeForTitle(entry.title) ??
            (entry.id == kDefaultWizardOfOzEntry.id
                ? kWizardOfOzCoverRelative
                : null);
        return ReadingDoc(
          id: entry.stableDocId,
          title: readingDisplayTitle(entry.title, titleZh: zh),
          titleZh: zh,
          sourceType: ReadingSourceType.catalog,
          level: entry.level,
          plainText: text,
          sourceLabel: 'Standard Ebooks',
          courseTitle: '公版文本 · Standard Ebooks 排版（CC0）。仅供个人学习。',
          episodeTitle: entry.subtitle,
          coverUrl: cover ?? '',
          createdAt: DateTime.now(),
        );
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('Standard Ebooks 下载失败：$lastError');
  }

  static List<String> _standardEbooksGithubSlugs(String path) {
    final List<String> parts = path
        .split('/')
        .map((String p) => p.trim())
        .where((String p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return const <String>[];
    final List<String> out = <String>[parts.join('_')];
    // Translator / illustrator segment is often not in the GitHub repo name.
    if (parts.length >= 3) {
      out.add(parts.take(2).join('_'));
    }
    return out.toSet().toList(growable: false);
  }

  List<Map<String, String>> _loadCefrCache() {
    if (!Hive.isBoxOpen('prefs')) return const <Map<String, String>>[];
    final String? raw = Hive.box<String>('prefs').get(_cefrCacheKey);
    if (raw == null || raw.isEmpty) return const <Map<String, String>>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const <Map<String, String>>[];
      final Object? items = decoded['items'];
      if (items is! List) return const <Map<String, String>>[];
      return <Map<String, String>>[
        for (final Object? item in items)
          if (item is Map)
            <String, String>{
              'id': '${item['id'] ?? ''}',
              'title': '${item['title'] ?? ''}',
              'level': '${item['level'] ?? ''}',
              'text': '${item['text'] ?? ''}',
            },
      ];
    } catch (_) {
      return const <Map<String, String>>[];
    }
  }

  Future<String> _getString(String url) async {
    final Response<String> response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  static String _onestopLevel(String path) {
    if (path.contains('Ele')) return 'Ele';
    if (path.contains('Int')) return 'Int';
    if (path.contains('Adv')) return 'Adv';
    return '';
  }

  static String _standardEbooksEpubUrl(String path) {
    final String slug = path.replaceAll('/', '_');
    // Prefer GitHub source zip — standardebooks.org returns HTML to app clients.
    return 'https://github.com/standardebooks/$slug/archive/refs/heads/master.zip';
  }

  static String _pathFromSeEpub(String epubUrl) {
    final Match? m = RegExp(
      r'standardebooks\.org/ebooks/(.+?)/downloads/',
    ).firstMatch(epubUrl);
    return m?.group(1) ?? '';
  }

  static String _preview(String text) {
    final String t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 80) return t;
    return '${t.substring(0, 80)}…';
  }

  static String _cefrTitle(String text, String label, int index) {
    final String preview = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final String head = preview.length <= 42
        ? preview
        : '${preview.substring(0, 42)}…';
    return 'CEFR $label · #$index · $head';
  }
}

List<ReadingCatalogEntry> parseCefrLeveledCsv(String raw) {
  final List<({String text, String label})> rows = _parseCefrRows(raw);
  return <ReadingCatalogEntry>[
    for (int i = 0; i < rows.length; i++)
      ReadingCatalogEntry(
        id: 'cefr_${rows[i].label.toLowerCase()}_${i + 1}',
        title: ReadingCatalogClient._cefrTitle(
          rows[i].text,
          rows[i].label,
          i + 1,
        ),
        kind: ReadingCatalogEntryKind.article,
        level: rows[i].label.toUpperCase(),
        subtitle: ReadingCatalogClient._preview(rows[i].text),
        path: 'cefr_${rows[i].label.toLowerCase()}_${i + 1}',
      ),
  ];
}

List<({String text, String label})> _parseCefrRows(String raw) {
  final List<List<String>> table = _parseCsv(raw);
  if (table.isEmpty) return const <({String text, String label})>[];
  final List<String> header = table.first
      .map((String c) => c.trim().toLowerCase())
      .toList();
  int textCol = header.indexOf('text');
  int labelCol = header.indexOf('label');
  if (labelCol < 0) labelCol = header.indexOf('level');
  if (textCol < 0) textCol = 0;
  if (labelCol < 0) labelCol = header.length > 1 ? 1 : 0;
  final List<({String text, String label})> out =
      <({String text, String label})>[];
  for (int i = 1; i < table.length; i++) {
    final List<String> row = table[i];
    if (row.length <= textCol || row.length <= labelCol) continue;
    final String text = row[textCol].trim();
    final String label = row[labelCol].trim().toUpperCase();
    if (text.isEmpty || label.isEmpty) continue;
    out.add((text: text, label: label));
  }
  return out;
}

List<List<String>> _parseCsv(String raw) {
  final List<List<String>> rows = <List<String>>[];
  final List<String> current = <String>[];
  final StringBuffer cell = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < raw.length; i++) {
    final String ch = raw[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < raw.length && raw[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
      continue;
    }
    if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      current.add(cell.toString());
      cell.clear();
    } else if (ch == '\n') {
      current.add(cell.toString());
      cell.clear();
      if (current.any((String c) => c.trim().isNotEmpty)) {
        rows.add(List<String>.from(current));
      }
      current.clear();
    } else if (ch != '\r') {
      cell.write(ch);
    }
  }
  current.add(cell.toString());
  if (current.any((String c) => c.trim().isNotEmpty)) {
    rows.add(current);
  }
  return rows;
}

/// Extract stories from Magic English Buddy `index.ts` story arrays.
///
/// Real files nest `words: [...]` inside each paragraph; a naive non-greedy
/// `content: [...]` regex stops at the first nested `]`, so we walk brackets.
List<ReadingCatalogEntry> parseMagicStoriesIndex(
  String raw, {
  required String path,
}) {
  final String level =
      RegExp(r'/l(\d+)', caseSensitive: false).firstMatch(path)?.group(1) ?? '';
  final List<ReadingCatalogEntry> out = <ReadingCatalogEntry>[];
  // Stories have `level: N` right after id; quiz items use `type:` instead.
  // Without that anchor, `id: '…_q1' … title:` would skip into the next story.
  final RegExp storyRe = RegExp(
    r"id:\s*'([^']+)'\s*,\s*level:\s*\d+[\s\S]*?title:\s*'((?:\\'|[^'])*)'[\s\S]*?content:\s*\[",
  );
  final RegExp quizIdRe = RegExp(r'_q\d+$');
  for (final RegExpMatch m in storyRe.allMatches(raw)) {
    final String id = m.group(1) ?? '';
    if (id.isEmpty || quizIdRe.hasMatch(id)) continue;
    final String title = (m.group(2) ?? '').replaceAll(r"\'", "'");
    final int openIdx = m.end - 1; // points at '['
    final String contentBlock = _extractBalancedBracketBlock(raw, openIdx);
    if (contentBlock.isEmpty) continue;
    final List<String> paras = <String>[];
    for (final RegExpMatch tm in RegExp(
      r"text:\s*'((?:\\'|[^'])*)'",
    ).allMatches(contentBlock)) {
      paras.add((tm.group(1) ?? '').replaceAll(r"\'", "'"));
    }
    if (title.isEmpty || paras.isEmpty) continue;
    final String text = paras.join(' ');
    out.add(
      ReadingCatalogEntry(
        id: 'magic:$id',
        title: title,
        kind: ReadingCatalogEntryKind.article,
        level: level.isEmpty ? '' : 'L$level',
        path: '$path#$id',
        subtitle: text, // full text for download without second parse
      ),
    );
  }
  return out;
}

/// Returns the interior of a `[...]` block starting at [openIndex].
String _extractBalancedBracketBlock(String source, int openIndex) {
  if (openIndex < 0 ||
      openIndex >= source.length ||
      source.codeUnitAt(openIndex) != 0x5B /* [ */ ) {
    return '';
  }
  int depth = 0;
  for (int i = openIndex; i < source.length; i++) {
    final int cu = source.codeUnitAt(i);
    if (cu == 0x5B) {
      depth += 1;
    } else if (cu == 0x5D) {
      depth -= 1;
      if (depth == 0) {
        return source.substring(openIndex + 1, i);
      }
    }
  }
  return '';
}
