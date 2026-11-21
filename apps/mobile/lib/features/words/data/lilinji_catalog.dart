import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../constants/endpoints.dart';
import '../domain/syllabus_book.dart';
import 'lilinji_xlsx_parser.dart';

/// Top-level categories from https://github.com/lilinji/English
const List<LilinjiCategory> kLilinjiCategories = <LilinjiCategory>[
  LilinjiCategory(path: '1.全国各大教材版本中小学同步', title: '中小学教材同步', tag: 'K12'),
  LilinjiCategory(path: '2.中考', title: '中考', tag: 'ZK'),
  LilinjiCategory(path: '2.高考', title: '高考', tag: 'GK'),
  LilinjiCategory(path: '3.大学英语', title: '大学英语', tag: 'COLLEGE'),
  LilinjiCategory(path: '3.四级', title: '四级 CET-4', tag: 'CET4'),
  LilinjiCategory(path: '3.专四', title: '专四 TEM-4', tag: 'TEM4'),
  LilinjiCategory(path: '4.六级', title: '六级 CET-6', tag: 'CET6'),
  LilinjiCategory(path: '4.专八', title: '专八 TEM-8', tag: 'TEM8'),
  LilinjiCategory(path: '5.考研', title: '考研', tag: 'KY'),
  LilinjiCategory(path: '6.研究生', title: '研究生', tag: 'GRAD'),
  LilinjiCategory(path: '6.考博', title: '考博', tag: 'PHD'),
  LilinjiCategory(path: '7.雅思', title: '雅思 IELTS', tag: 'IELTS'),
  LilinjiCategory(path: '7.托福', title: '托福 TOEFL', tag: 'TOEFL'),
  LilinjiCategory(path: '8.商务英语', title: '商务英语', tag: 'BEC'),
  LilinjiCategory(path: '8.国际英语', title: '国际英语教材', tag: 'INTL'),
  LilinjiCategory(path: '8.新世纪英专', title: '新世纪英专', tag: 'MAJOR'),
  LilinjiCategory(path: '8.新概念英语', title: '新概念英语', tag: 'NCE'),
  LilinjiCategory(path: '9.扇贝英语（IT）', title: 'IT / 开发英语', tag: 'IT'),
  LilinjiCategory(path: '9.其他（更多）', title: '其他（GRE/SAT/GMAT 等）', tag: 'OTHER'),
];

class LilinjiCategory {
  const LilinjiCategory({
    required this.path,
    required this.title,
    required this.tag,
  });

  final String path;
  final String title;
  final String tag;
}

enum LilinjiEntryKind { folder, book }

class LilinjiCatalogEntry {
  const LilinjiCatalogEntry({
    required this.name,
    required this.path,
    required this.kind,
    this.sizeBytes = 0,
    this.downloadUrl,
  });

  final String name;
  final String path;
  final LilinjiEntryKind kind;
  final int sizeBytes;
  final String? downloadUrl;

  String get displayTitle {
    final String base = name.replaceAll(
      RegExp(r'\.(xlsx|xls|txt|csv|tsv)$', caseSensitive: false),
      '',
    );
    return base.isEmpty ? name : base;
  }

  String get stableBookId {
    final Digest digest = sha1.convert(utf8.encode(path));
    return 'lilinji_${digest.toString().substring(0, 16)}';
  }
}

class LilinjiCatalogClient {
  LilinjiCatalogClient({Dio? dio, String apiBaseUrl = Endpoints.baseUrl})
    : _apiBaseUrl = Endpoints.normalizeBaseUrl(apiBaseUrl),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 90),
              responseType: ResponseType.json,
              headers: const <String, String>{
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'AcquireEnglish-SyllabusCatalog',
              },
            ),
          ) {
    if (dio == null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            final Uri source = options.uri;
            if (_shouldProxy(source)) {
              options.path = Uri.parse(_apiBaseUrl)
                  .resolve('api/reading/source')
                  .replace(queryParameters: <String, String>{
                    'url': source.toString(),
                  })
                  .toString();
              options.queryParameters = <String, dynamic>{};
            }
            handler.next(options);
          },
        ),
      );
    }
  }

  static const String repoApi =
      'https://api.github.com/repos/lilinji/English/contents';
  static const String rawBase =
      'https://raw.githubusercontent.com/lilinji/English/main';
  static const String ghproxyRawBase =
      'https://ghproxy.net/https://raw.githubusercontent.com/lilinji/English/main';

  final Dio _dio;
  final String _apiBaseUrl;
  final Map<String, List<LilinjiCatalogEntry>> _listCache =
      <String, List<LilinjiCatalogEntry>>{};

  static bool _shouldProxy(Uri source) {
    return source.host == 'api.github.com' ||
        source.host == 'raw.githubusercontent.com';
  }

  Future<List<LilinjiCatalogEntry>> listPath(String path) async {
    final String key = path.trim();
    final List<LilinjiCatalogEntry>? cached = _listCache[key];
    if (cached != null) return cached;

    final String url = key.isEmpty
        ? repoApi
        : '$repoApi/${key.split('/').map(Uri.encodeComponent).join('/')}';
    final Response<dynamic> response = await _dio.get<dynamic>(url);
    final Object? data = response.data;
    final List<dynamic> items = _asJsonList(data);
    final List<LilinjiCatalogEntry> entries = <LilinjiCatalogEntry>[];
    for (final Object? item in items) {
      if (item is! Map) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(item);
      final String name = '${map['name'] ?? ''}';
      final String itemPath = '${map['path'] ?? ''}';
      final String type = '${map['type'] ?? ''}';
      if (name.isEmpty || itemPath.isEmpty) continue;
      if (type == 'dir') {
        entries.add(
          LilinjiCatalogEntry(
            name: name,
            path: itemPath,
            kind: LilinjiEntryKind.folder,
          ),
        );
        continue;
      }
      if (!_isVocabFile(name)) continue;
      entries.add(
        LilinjiCatalogEntry(
          name: name,
          path: itemPath,
          kind: LilinjiEntryKind.book,
          sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
          downloadUrl: '${map['download_url'] ?? ''}'.isEmpty
              ? null
              : '${map['download_url']}',
        ),
      );
    }
    entries.sort((LilinjiCatalogEntry a, LilinjiCatalogEntry b) {
      if (a.kind != b.kind) {
        return a.kind == LilinjiEntryKind.folder ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    _listCache[key] = List<LilinjiCatalogEntry>.unmodifiable(entries);
    return _listCache[key]!;
  }

  Future<({SyllabusBook book, List<SyllabusWord> words})> downloadBook({
    required LilinjiCatalogEntry entry,
    required String examTag,
  }) async {
    if (entry.kind != LilinjiEntryKind.book) {
      throw StateError('不是可下载词书');
    }
    final Uint8List bytes = await _downloadBytes(entry);
    final String lower = entry.name.toLowerCase();
    late final List<SyllabusWord> words;
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      words = parseLilinjiXlsx(bytes);
    } else {
      words = parseLilinjiText(utf8.decode(bytes, allowMalformed: true));
    }
    if (words.isEmpty) {
      throw StateError('未能从该文件解析出单词');
    }
    final SyllabusBook book = SyllabusBook(
      id: entry.stableBookId,
      title: entry.displayTitle,
      examTag: examTag,
      disclaimer: '',
      words: words,
      builtin: false,
    );
    return (book: book, words: words);
  }

  Future<Uint8List> _downloadBytes(LilinjiCatalogEntry entry) async {
    final String encodedPath =
        entry.path.split('/').map(Uri.encodeComponent).join('/');
    final List<String> candidates = <String>[
      if (entry.downloadUrl != null && entry.downloadUrl!.isNotEmpty)
        entry.downloadUrl!,
      '$rawBase/$encodedPath',
      '$ghproxyRawBase/$encodedPath',
    ];
    Object? lastError;
    for (final String url in candidates) {
      try {
        final Response<List<int>> response = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: const <String, String>{
              'Accept': '*/*',
              'User-Agent': 'AcquireEnglish-SyllabusCatalog',
            },
          ),
        );
        final List<int>? data = response.data;
        if (data != null && data.isNotEmpty) {
          return Uint8List.fromList(data);
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('下载失败：${lastError ?? 'empty response'}');
  }

  List<dynamic> _asJsonList(Object? data) {
    if (data is List) return data;
    if (data is String) {
      final Object? decoded = jsonDecode(data);
      if (decoded is List) return decoded;
    }
    if (data is List<int>) {
      final Object? decoded = jsonDecode(utf8.decode(data));
      if (decoded is List) return decoded;
    }
    throw StateError('词库目录格式异常');
  }

  bool _isVocabFile(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith('.md') ||
        lower.endsWith('.pdf') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.pptx') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return false;
    }
    return lower.endsWith('.xlsx') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.tsv');
  }
}
