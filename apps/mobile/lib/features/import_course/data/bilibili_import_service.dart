import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path_provider/path_provider.dart';

import '../../../constants/env_config.dart';
import '../domain/bilibili_import.dart';
import 'bilibili_media_proxy.dart';

class BilibiliPageMeta {
  const BilibiliPageMeta({
    required this.page,
    required this.cid,
    required this.part,
    required this.durationSec,
  });

  final int page;
  final int cid;
  final String part;
  final int durationSec;
}

/// One member of a Bilibili UGC season / 合集 (usually a distinct BV).
class BilibiliSeasonEpisodeMeta {
  const BilibiliSeasonEpisodeMeta({
    required this.index,
    required this.title,
    required this.bvid,
    required this.aid,
    required this.cid,
    required this.durationSec,
    this.coverImageUrl,
  });

  final int index;
  final String title;
  final String bvid;
  final String aid;
  final int cid;
  final int durationSec;
  final String? coverImageUrl;

  String get watchUrl => BilibiliImport.watchUrl(
        bvid: bvid.isNotEmpty ? bvid : null,
        aid: aid.isNotEmpty ? aid : null,
      );
}

class BilibiliImportResult {
  const BilibiliImportResult({
    required this.idKey,
    required this.title,
    required this.watchUrl,
    required this.durationMinutes,
    this.enSubtitlePath,
    this.cnSubtitlePath,
    this.author,
    this.coverImagePath,
    this.coverImageUrl,
    this.localVideoPath,
    this.subtitleNote,
    this.page = 1,
    this.pages = const <BilibiliPageMeta>[],
    this.aid,
    this.seasonId,
    this.seasonTitle,
    this.seasonCoverUrl,
    this.seasonEpisodes = const <BilibiliSeasonEpisodeMeta>[],
  });

  final String idKey;
  final String title;
  final String watchUrl;
  final int durationMinutes;
  final String? enSubtitlePath;
  final String? cnSubtitlePath;
  final String? author;
  /// Local downloaded cover when available; otherwise prefer [coverImageUrl].
  final String? coverImagePath;
  final String? coverImageUrl;
  /// Local MP4 downloaded during import (preferred playback / ASR source).
  final String? localVideoPath;
  /// Human-readable note when official subs were skipped / unavailable.
  final String? subtitleNote;
  /// 1-based page that [localVideoPath] / subtitle paths belong to.
  final int page;
  final List<BilibiliPageMeta> pages;
  final String? aid;
  final String? seasonId;
  final String? seasonTitle;
  final String? seasonCoverUrl;
  final List<BilibiliSeasonEpisodeMeta> seasonEpisodes;

  bool get isSeasonCollection => seasonEpisodes.length > 1;

  String get bestCoverImage =>
      (coverImagePath != null && coverImagePath!.isNotEmpty)
      ? coverImagePath!
      : (coverImageUrl != null && coverImageUrl!.isNotEmpty)
      ? coverImageUrl!
      : (seasonCoverUrl != null && seasonCoverUrl!.isNotEmpty)
      ? seasonCoverUrl!
      : 'assets/img/app_icon.png';

  /// Prefer the on-disk video; fall back to the watch page URL.
  String get bestVideoAsset =>
      (localVideoPath != null && localVideoPath!.isNotEmpty)
      ? localVideoPath!
      : watchUrl;

  BilibiliImportResult copyWith({
    String? enSubtitlePath,
    String? cnSubtitlePath,
    String? coverImagePath,
    String? coverImageUrl,
    String? localVideoPath,
    String? subtitleNote,
    int? page,
    List<BilibiliPageMeta>? pages,
    String? aid,
    String? seasonId,
    String? seasonTitle,
    String? seasonCoverUrl,
    List<BilibiliSeasonEpisodeMeta>? seasonEpisodes,
  }) {
    return BilibiliImportResult(
      idKey: idKey,
      title: title,
      watchUrl: watchUrl,
      durationMinutes: durationMinutes,
      enSubtitlePath: enSubtitlePath ?? this.enSubtitlePath,
      cnSubtitlePath: cnSubtitlePath ?? this.cnSubtitlePath,
      author: author,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      localVideoPath: localVideoPath ?? this.localVideoPath,
      subtitleNote: subtitleNote ?? this.subtitleNote,
      page: page ?? this.page,
      pages: pages ?? this.pages,
      aid: aid ?? this.aid,
      seasonId: seasonId ?? this.seasonId,
      seasonTitle: seasonTitle ?? this.seasonTitle,
      seasonCoverUrl: seasonCoverUrl ?? this.seasonCoverUrl,
      seasonEpisodes: seasonEpisodes ?? this.seasonEpisodes,
    );
  }
}

class BilibiliImportService {
  BilibiliImportService({
    Dio? dio,
    String? sessdata,
    String? cookie,
  }) : _sessdata = sessdata?.trim() ?? '',
       _cookie = cookie?.trim() ?? '',
       _dio = dio ?? _createDio() {
    if (dio == null) {
      _installDnsBypassAdapter();
    }
  }

  /// Prefer the in-app login Cookie; fall back to compile-time `.env`.
  factory BilibiliImportService.withCookie(String? cookieOrSessdata) {
    final String value = cookieOrSessdata?.trim() ?? '';
    if (value.isEmpty) {
      return BilibiliImportService();
    }
    return BilibiliImportService(sessdata: value);
  }

  final Dio _dio;
  final String _sessdata;
  final String _cookie;
  final Map<String, List<String>> _dnsCache = <String, List<String>>{};

  /// Coalesce concurrent downloads of the same cache key (import + open / 合集).
  static final Map<String, Future<File>> _inflightCacheDownloads =
      <String, Future<File>>{};

  /// Cookie header for player / subtitle APIs (login required for CC list).
  String get cookieHeader {
    if (_cookie.isNotEmpty) {
      return _cookie;
    }
    if (_sessdata.isNotEmpty) {
      if (_sessdata.toLowerCase().contains('sessdata=')) {
        return _sessdata;
      }
      return 'SESSDATA=$_sessdata';
    }
    return EnvConfig.bilibiliCookieHeader;
  }

  bool get hasLoginCookie => cookieHeader.isNotEmpty;

  Map<String, dynamic> get _authHeaders {
    final String cookie = cookieHeader;
    if (cookie.isEmpty) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{'Cookie': cookie};
  }

  /// CDN / playurl requests also need the login Cookie when available.
  Map<String, String> get _playHeadersWithAuth {
    final Map<String, String> headers = Map<String, String>.from(
      playHttpHeaders,
    );
    final String cookie = cookieHeader;
    if (cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
        headers: <String, dynamic>{
          'User-Agent': playHttpHeaders['User-Agent'],
          'Referer': playHttpHeaders['Referer'],
          'Origin': 'https://www.bilibili.com',
          // Keep */* so the same client can hit JSON APIs and MP4 CDNs.
          // Accept: application/json alone makes some bilivideo nodes return 400.
          'Accept': '*/*',
        },
      ),
    );
  }

  void _installDnsBypassAdapter() {
    // Use the platform HttpClient/DNS for API + CDN requests.
    // Forcing sockets onto DoH IPs via connectionFactory broke bilivideo CDN
    // on Android (HTTP 400). Short links still expand via
    // _expandShortLinkWithoutDns (literal IP + SNI), which does not use Dio.
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final HttpClient client = HttpClient();
        client.userAgent = playHttpHeaders['User-Agent'];
        client.autoUncompress = true;
        return client;
      },
    );
  }

  // Flutter/Android getaddrinfo fails for b23 CDN hosts on some devices.
  // Expand short links with SecureSocket to literal IPs only — no DNS.
  static const List<({String host, String ip})> _dohEndpoints =
      <({String host, String ip})>[
        (host: 'dns.alidns.com', ip: '223.5.5.5'),
        (host: 'dns.alidns.com', ip: '223.6.6.6'),
        (host: 'doh.pub', ip: '1.12.12.12'),
      ];

  static const Map<String, List<String>> _shortLinkFallbackIps =
      <String, List<String>>{
        'bili2233.cn': <String>[
          '120.232.99.87',
          '120.241.41.179',
          '120.233.181.41',
        ],
        'b23.tv': <String>[
          '183.232.239.21',
          '183.232.239.20',
          '183.232.239.19',
        ],
        'api.bilibili.com': <String>[
          '183.232.239.21',
          '183.232.239.22',
          '120.240.224.12',
          '120.240.224.20',
        ],
        'www.bilibili.com': <String>[
          '183.232.239.18',
          '183.232.239.20',
          '120.240.224.12',
        ],
      };

  /// Resolves share-paste / b23.tv short links into `bvid` or `aid`.
  Future<Map<String, String>?> resolveIds(String rawInput) async {
    final String cleaned = BilibiliImport.normalizeInput(rawInput);
    final Map<String, String>? direct = BilibiliImport.extractIds(cleaned);
    if (direct != null) {
      return direct;
    }

    final String? candidate = BilibiliImport.firstUrlInText(cleaned);
    if (candidate == null) {
      return null;
    }

    final Map<String, String>? fromCandidate = BilibiliImport.extractIds(
      candidate,
    );
    if (fromCandidate != null) {
      return fromCandidate;
    }

    if (!BilibiliImport.isShortLink(candidate)) {
      return null;
    }

    final String resolved = await _resolveShortLinkCandidates(
      BilibiliImport.shortLinkCandidates(cleaned),
    );
    final Map<String, String>? ids = BilibiliImport.extractIds(resolved);
    if (ids == null) {
      throw StateError('短链已打开，但未能解析出 BV/av：$resolved');
    }
    return ids;
  }

  Future<String> _resolveShortLinkCandidates(List<String> candidates) async {
    final List<Object> errors = <Object>[];
    for (final String start in candidates) {
      try {
        return await _expandShortLinkWithoutDns(start);
      } catch (e) {
        errors.add(e);
      }
    }
    throw StateError(
      '无法解析短链。请改贴完整 BV 链接（如 bilibili.com/video/BVxxxx）。\n'
      '${errors.isEmpty ? '' : errors.first}',
    );
  }

  Future<String> _expandShortLinkWithoutDns(String shortUrl) async {
    Uri uri = Uri.parse(shortUrl);
    for (int hop = 0; hop < 8; hop++) {
      final List<String> ips = await _lookupIpv4WithoutDns(uri.host);
      Object? lastError;
      for (final String ip in ips) {
        try {
          final _RawHttpsResponse res = await _rawHttpsGet(
            host: uri.host,
            ip: ip,
            pathAndQuery: _pathAndQuery(uri),
          );
          final String? location = res.location;
          if (location == null || location.isEmpty) {
            if (BilibiliImport.extractIds(uri.toString()) != null) {
              return uri.toString();
            }
            throw StateError(
              '${uri.host} 未返回跳转 Location（HTTP ${res.status}）',
            );
          }
          final Uri next = uri.resolve(location);
          if (BilibiliImport.extractIds(next.toString()) != null) {
            return next.toString();
          }
          uri = next;
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (lastError != null) {
        throw StateError('$lastError');
      }
    }
    return uri.toString();
  }

  Future<List<String>> _lookupIpv4WithoutDns(String host) async {
    final String key = host.toLowerCase();
    final List<String>? cached = _dnsCache[key];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final List<Object> errors = <Object>[];

    // System DNS first — reliable for bilivideo CDN on most Android devices.
    try {
      final List<InternetAddress> system = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      final List<String> ips = system
          .map((InternetAddress a) => a.address)
          .where((String v) => v.isNotEmpty)
          .toList(growable: false);
      if (ips.isNotEmpty) {
        _dnsCache[key] = ips;
        return ips;
      }
    } catch (e) {
      errors.add(e);
    }

    for (final ({String host, String ip}) endpoint in _dohEndpoints) {
      try {
        final List<String> ips = await _lookupIpv4ViaDohEndpoint(
          host,
          dohHost: endpoint.host,
          dohIp: endpoint.ip,
        );
        if (ips.isNotEmpty) {
          _dnsCache[key] = ips;
          return ips;
        }
      } catch (e) {
        errors.add(e);
      }
    }
    final List<String>? fallback = _shortLinkFallbackIps[key];
    if (fallback != null && fallback.isNotEmpty) {
      _dnsCache[key] = fallback;
      return fallback;
    }
    throw StateError(
      'DNS 失败：$host'
      '${errors.isEmpty ? '' : ' (${errors.first})'}',
    );
  }

  Future<List<String>> _lookupIpv4ViaDohEndpoint(
    String host, {
    required String dohHost,
    required String dohIp,
  }) async {
    final _RawHttpsResponse res = await _rawHttpsGet(
      host: dohHost,
      ip: dohIp,
      pathAndQuery: '/resolve?name=${Uri.encodeQueryComponent(host)}&type=A',
      accept: 'application/dns-json',
    );
    final dynamic root = jsonDecode(res.body);
    final List<dynamic> answers = root is Map<String, dynamic>
        ? (root['Answer'] as List<dynamic>? ?? const <dynamic>[])
        : const <dynamic>[];
    final List<String> ips = <String>[];
    for (final dynamic item in answers) {
      if (item is! Map) {
        continue;
      }
      if (item['type'] != 1) {
        continue;
      }
      final String? data = item['data'] as String?;
      if (data != null && data.isNotEmpty) {
        ips.add(data);
      }
    }
    return ips;
  }

  String _pathAndQuery(Uri uri) {
    final String path = uri.path.isEmpty ? '/' : uri.path;
    if (!uri.hasQuery) {
      return path;
    }
    return '$path?${uri.query}';
  }

  Future<_RawHttpsResponse> _rawHttpsGet({
    required String host,
    required String ip,
    required String pathAndQuery,
    String? accept,
  }) async {
    final Socket raw = await Socket.connect(
      InternetAddress(ip),
      443,
      timeout: const Duration(seconds: 12),
    );
    final SecureSocket socket = await SecureSocket.secure(
      raw,
      host: host,
    );
    try {
      final StringBuffer request = StringBuffer()
        ..write('GET $pathAndQuery HTTP/1.1\r\n')
        ..write('Host: $host\r\n')
        ..write(
          'User-Agent: Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36\r\n',
        )
        ..write('Referer: https://www.bilibili.com\r\n')
        ..write('Accept: ${accept ?? '*/*'}\r\n')
        ..write('Connection: close\r\n')
        ..write('\r\n');
      socket.add(utf8.encode(request.toString()));
      await socket.flush();

      final BytesBuilder bytes = BytesBuilder(copy: false);
      await for (final List<int> chunk in socket.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.add(chunk);
      }
      return _parseRawHttpsResponse(bytes.takeBytes());
    } finally {
      socket.destroy();
    }
  }

  _RawHttpsResponse _parseRawHttpsResponse(List<int> raw) {
    final int headerEnd = _indexOfHeaderEnd(raw);
    if (headerEnd < 0) {
      throw StateError('HTTPS 响应缺少头部结束标记');
    }
    final String headerText = utf8.decode(
      raw.sublist(0, headerEnd),
      allowMalformed: true,
    );
    final List<String> lines = headerText.split('\r\n');
    if (lines.isEmpty) {
      throw StateError('空 HTTPS 响应');
    }
    final List<String> statusParts = lines.first.split(' ');
    final int status = statusParts.length > 1
        ? (int.tryParse(statusParts[1]) ?? 0)
        : 0;
    String? location;
    bool chunked = false;
    int? contentLength;
    for (final String line in lines.skip(1)) {
      final int colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      final String name = line.substring(0, colon).trim().toLowerCase();
      final String value = line.substring(colon + 1).trim();
      if (name == 'location') {
        location = value;
      } else if (name == 'transfer-encoding' &&
          value.toLowerCase().contains('chunked')) {
        chunked = true;
      } else if (name == 'content-length') {
        contentLength = int.tryParse(value);
      }
    }
    List<int> bodyBytes = raw.sublist(headerEnd + 4);
    if (chunked) {
      bodyBytes = _decodeChunked(bodyBytes);
    } else if (contentLength != null && contentLength < bodyBytes.length) {
      bodyBytes = bodyBytes.sublist(0, contentLength);
    }
    return _RawHttpsResponse(
      status: status,
      location: location,
      body: utf8.decode(bodyBytes, allowMalformed: true),
    );
  }

  int _indexOfHeaderEnd(List<int> raw) {
    for (int i = 0; i + 3 < raw.length; i++) {
      if (raw[i] == 13 &&
          raw[i + 1] == 10 &&
          raw[i + 2] == 13 &&
          raw[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  List<int> _decodeChunked(List<int> raw) {
    final BytesBuilder out = BytesBuilder(copy: false);
    int i = 0;
    while (i < raw.length) {
      final int lineEnd = _indexOfCrlf(raw, i);
      if (lineEnd < 0) {
        break;
      }
      final String sizeHex = utf8.decode(raw.sublist(i, lineEnd)).trim();
      final int size = int.tryParse(sizeHex.split(';').first, radix: 16) ?? -1;
      i = lineEnd + 2;
      if (size <= 0) {
        break;
      }
      if (i + size > raw.length) {
        break;
      }
      out.add(raw.sublist(i, i + size));
      i += size + 2;
    }
    return out.takeBytes();
  }

  int _indexOfCrlf(List<int> raw, int start) {
    for (int i = start; i + 1 < raw.length; i++) {
      if (raw[i] == 13 && raw[i + 1] == 10) {
        return i;
      }
    }
    return -1;
  }

  Future<BilibiliImportResult> fetch(String rawInput) async {
    final Map<String, String>? ids = await resolveIds(rawInput);
    if (ids == null) {
      throw ArgumentError('无效的 Bilibili 链接（含短链未能解析）');
    }

    final Response<dynamic> viewRes = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: ids,
    );
    final Map<String, dynamic> viewRoot =
        viewRes.data as Map<String, dynamic>? ?? <String, dynamic>{};
    if ((viewRoot['code'] as int? ?? -1) != 0) {
      throw StateError(
        (viewRoot['message'] as String?) ?? '无法获取 Bilibili 视频信息',
      );
    }
    final Map<String, dynamic> data =
        viewRoot['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String bvid = (data['bvid'] as String?) ?? ids['bvid'] ?? '';
    final int? aid =
        (data['aid'] as num?)?.toInt() ?? int.tryParse(ids['aid'] ?? '');
    final String rawTitle = (data['title'] as String?)?.trim() ?? '';
    final String title = rawTitle.isNotEmpty
        ? rawTitle
        : (bvid.isNotEmpty ? bvid : 'av$aid');
    final String? author =
        (data['owner'] as Map<String, dynamic>?)?['name'] as String?;
    final List<BilibiliPageMeta> pageMetas = _parsePages(data);
    final int requestedPage = BilibiliImport.extractPage(rawInput) ?? 1;
    final BilibiliPageMeta selected = _pageMetaFor(
      pageMetas,
      requestedPage: requestedPage,
      fallbackCid: (data['cid'] as num?)?.toInt() ?? 0,
      fallbackDurationSec: (data['duration'] as num?)?.toInt() ?? 60,
    );
    final int cid = selected.cid;
    final int page = selected.page;
    final int durationSec = selected.durationSec > 0
        ? selected.durationSec
        : ((data['duration'] as num?)?.toInt() ?? 60);

    final String watch = BilibiliImport.watchUrl(
      bvid: bvid.isEmpty ? null : bvid,
      aid: aid?.toString(),
      page: page,
    );
    final String rootKey = bvid.isNotEmpty ? bvid : 'av$aid';
    final String idKey = BilibiliImport.mediaIdKey(
      bvidOrAv: rootKey,
      page: page,
      pageCount: pageMetas.isEmpty ? 1 : pageMetas.length,
    );
    final String? coverUrl = _normalizeCoverUrl(data['pic'] as String?);
    String? coverPath;
    if (coverUrl != null) {
      try {
        coverPath = await _downloadCoverImage(
          coverUrl: coverUrl,
          idKey: rootKey,
        );
      } catch (_) {}
    }

    String? enPath;
    String? cnPath;
    String? subtitleNote;
    if (cid > 0 && (bvid.isNotEmpty || aid != null)) {
      try {
        final Map<String, String?> tracks = await _fetchSubtitles(
          bvid: bvid,
          aid: aid?.toString(),
          cid: cid,
          idKey: idKey,
        );
        enPath = tracks['en'];
        cnPath = tracks['zh'];
        if (enPath == null && cnPath == null) {
          final bool multi = pageMetas.length > 1;
          subtitleNote = multi
              ? 'P$page 暂无中/英官方字幕（合集共 ${pageMetas.length} P，部分分 P 才有英文字幕）'
              : (hasLoginCookie
                    ? '该视频暂无可用中/英官方字幕'
                    : '官方字幕需要登录 Cookie：在设置里登录 B 站或粘贴 SESSDATA');
        } else if (enPath == null && cnPath != null && pageMetas.length > 1) {
          subtitleNote =
              'P$page 已保存中文字幕；该分 P 无英文字幕（可切换到带 English(US) 的分 P）';
        }
      } catch (e) {
        subtitleNote = '官方字幕拉取失败：$e';
      }
    }

    final BilibiliSeasonParseResult season = _parseSeason(data);
    return BilibiliImportResult(
      idKey: idKey,
      title: title,
      watchUrl: watch,
      durationMinutes: (durationSec / 60).ceil().clamp(1, 24 * 60),
      enSubtitlePath: enPath,
      cnSubtitlePath: cnPath,
      author: author,
      coverImagePath: coverPath,
      coverImageUrl: coverUrl,
      subtitleNote: subtitleNote,
      page: page,
      pages: pageMetas,
      aid: aid?.toString(),
      seasonId: season.id,
      seasonTitle: season.title,
      seasonCoverUrl: season.coverUrl,
      seasonEpisodes: season.episodes,
    );
  }

  List<BilibiliPageMeta> _parsePages(Map<String, dynamic> data) {
    final List<dynamic> pages =
        data['pages'] as List<dynamic>? ?? const <dynamic>[];
    final List<BilibiliPageMeta> out = <BilibiliPageMeta>[];
    for (final dynamic raw in pages) {
      if (raw is! Map) {
        continue;
      }
      final Map<String, dynamic> page = raw.cast<String, dynamic>();
      final int pageNo = (page['page'] as num?)?.toInt() ?? (out.length + 1);
      final int cid = (page['cid'] as num?)?.toInt() ?? 0;
      if (cid <= 0) {
        continue;
      }
      out.add(
        BilibiliPageMeta(
          page: pageNo,
          cid: cid,
          part: (page['part'] as String?)?.trim() ?? 'P$pageNo',
          durationSec: (page['duration'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return out;
  }

  BilibiliPageMeta _pageMetaFor(
    List<BilibiliPageMeta> pages, {
    required int requestedPage,
    required int fallbackCid,
    required int fallbackDurationSec,
  }) {
    if (pages.isEmpty) {
      return BilibiliPageMeta(
        page: 1,
        cid: fallbackCid,
        part: 'P1',
        durationSec: fallbackDurationSec,
      );
    }
    for (final BilibiliPageMeta page in pages) {
      if (page.page == requestedPage) {
        return page;
      }
    }
    return pages.first;
  }

  BilibiliSeasonParseResult _parseSeason(Map<String, dynamic> data) {
    return parseBilibiliUgcSeason(
      data,
      normalizeCoverUrl: _normalizeCoverUrl,
    );
  }

  /// Fetch metadata, then download the MP4 locally before import completes.
  ///
  /// Playback and ASR both use the local file so recognition never depends on
  /// a live CDN stream or the localhost media proxy.
  Future<BilibiliImportResult> fetchAndDownloadLocal(
    String rawInput, {
    void Function(double? progress, String message)? onProgress,
  }) async {
    onProgress?.call(null, '正在获取视频信息…');
    final BilibiliImportResult meta = await fetch(rawInput);
    onProgress?.call(null, '正在下载视频到本地…');
    final String localPath = await ensureLocalCacheForAsr(
      meta.watchUrl,
      onProgress: onProgress,
    );
    return meta.copyWith(localVideoPath: localPath);
  }

  /// Resolve and download cover for an already-imported Bilibili course.
  Future<String?> resolveCoverImage(String rawInput) async {
    Map<String, String>? ids = BilibiliImport.extractIds(rawInput);
    ids ??= await resolveIds(rawInput);
    if (ids == null) {
      // Last resort: bare BV / av tokens inside course ids.
      final RegExpMatch? bv = RegExp(
        r'(BV[0-9A-Za-z]+)',
        caseSensitive: false,
      ).firstMatch(rawInput);
      if (bv != null) {
        ids = <String, String>{'bvid': bv.group(1)!};
      } else {
        final RegExpMatch? av = RegExp(r'av(\d+)', caseSensitive: false)
            .firstMatch(rawInput);
        if (av != null) {
          ids = <String, String>{'aid': av.group(1)!};
        }
      }
    }
    if (ids == null) {
      return null;
    }
    final Response<dynamic> viewRes = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: ids,
      options: Options(
        headers: <String, dynamic>{
          'Accept': 'application/json, text/plain, */*',
        },
        validateStatus: (int? code) =>
            code != null && code >= 200 && code < 500,
      ),
    );
    if ((viewRes.statusCode ?? 0) >= 400) {
      return null;
    }
    final Map<String, dynamic> viewRoot = _asJsonMap(viewRes.data);
    if ((viewRoot['code'] as int? ?? -1) != 0) {
      return null;
    }
    final Map<String, dynamic> data = _asJsonMap(viewRoot['data']);
    final String bvid = (data['bvid'] as String?) ?? ids['bvid'] ?? '';
    final String? aid =
        ids['aid'] ?? (data['aid'] as num?)?.toInt().toString();
    final String idKey = bvid.isNotEmpty
        ? bvid
        : (aid == null ? 'unknown' : 'av$aid');
    final String? coverUrl = _normalizeCoverUrl(data['pic'] as String?);
    if (coverUrl == null) {
      return null;
    }
    // Always prefer a local file — NetworkImage can fail on some Android
    // stacks for CDN hosts even when curl succeeds.
    try {
      final String? local = await _downloadCoverImage(
        coverUrl: coverUrl,
        idKey: idKey,
      );
      if (local != null && local.isNotEmpty) {
        return local;
      }
    } catch (_) {}
    return coverUrl;
  }

  String? _normalizeCoverUrl(String? raw) {
    if (raw == null) {
      return null;
    }
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('http://')) {
      return 'https://${trimmed.substring('http://'.length)}';
    }
    if (trimmed.startsWith('https://')) {
      return trimmed;
    }
    return null;
  }

  Future<String?> _downloadCoverImage({
    required String coverUrl,
    required String idKey,
  }) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/bilibili/$idKey');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final Uri uri = Uri.parse(coverUrl);
    final String ext = _coverExtension(uri.path);
    final File out = File('${dir.path}/cover$ext');
    if (out.existsSync() && out.lengthSync() > 1024) {
      return out.path;
    }

    List<int>? bytes;
    try {
      final Response<List<int>> res = await _dio.get<List<int>>(
        coverUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: <String, dynamic>{
            'Referer': 'https://www.bilibili.com',
            'User-Agent': playHttpHeaders['User-Agent'],
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          },
          validateStatus: (int? code) =>
              code != null && code >= 200 && code < 400,
        ),
      );
      bytes = res.data;
    } catch (_) {
      bytes = null;
    }

    // Dio can fail on some CDN/TLS stacks; fall back to HttpClient.
    if (bytes == null || bytes.length < 128) {
      try {
        final HttpClient client = HttpClient();
        client.userAgent = playHttpHeaders['User-Agent'];
        final HttpClientRequest req = await client.getUrl(Uri.parse(coverUrl));
        req.headers.set(HttpHeaders.refererHeader, 'https://www.bilibili.com');
        req.headers.set(
          HttpHeaders.acceptHeader,
          'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        );
        final HttpClientResponse res = await req.close();
        if (res.statusCode >= 200 && res.statusCode < 400) {
          final BytesBuilder builder = BytesBuilder(copy: false);
          await for (final List<int> chunk in res) {
            builder.add(chunk);
          }
          bytes = builder.takeBytes();
        }
        client.close(force: true);
      } catch (_) {
        bytes = null;
      }
    }

    if (bytes == null || bytes.length < 128) {
      return null;
    }
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }

  String _coverExtension(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return '.png';
    }
    if (lower.endsWith('.webp')) {
      return '.webp';
    }
    if (lower.endsWith('.gif')) {
      return '.gif';
    }
    return '.jpg';
  }

  /// Resolve a playable media URL for a Bilibili watch page / share paste.
  /// Prefers html5 MP4 durl; falls back to other playurl modes.
  Future<String?> resolvePlayableMediaUrl(String rawInput) async {
    try {
      final BilibiliPlayableMedia media = await resolvePlayableForPlayback(
        rawInput,
      );
      return media.uri;
    } catch (_) {
      return null;
    }
  }

  /// Resolve a player-ready URI for media_kit.
  ///
  /// Always prefer a local MP4. Download the full file before playback /
  /// recognition so ASR and the player share one on-disk source. Fall back to
  /// [BilibiliMediaProxy] only when every download candidate fails.
  Future<BilibiliPlayableMedia> resolvePlayableForPlayback(
    String rawInput, {
    void Function(double? progress, String message)? onProgress,
  }) async {
    // Already a local file from a previous import.
    final String trimmed = rawInput.trim();
    if (trimmed.isNotEmpty &&
        !trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://') &&
        File(trimmed).existsSync() &&
        File(trimmed).lengthSync() > 64 * 1024) {
      onProgress?.call(1, '使用本地视频');
      return BilibiliPlayableMedia(uri: trimmed, headers: null);
    }

    onProgress?.call(null, '正在获取视频信息…');
    final _BilibiliVideoRef ref = await _resolveVideoRef(rawInput);
    final File? cached = await _existingCacheFile(ref.idKey);
    if (cached != null) {
      onProgress?.call(1, '使用已缓存视频');
      return BilibiliPlayableMedia(uri: cached.path, headers: null);
    }

    onProgress?.call(null, '正在解析播放地址…');
    final List<String> remoteUrls = await _fetchPlayableDurlCandidates(ref);
    if (remoteUrls.isEmpty) {
      throw StateError('B 站取流失败：无可用地址');
    }

    Object? lastDownloadError;
    for (final String remoteUrl in remoteUrls) {
      try {
        onProgress?.call(null, '正在校验视频流…');
        await _assertRemoteIsPlayable(remoteUrl);
        onProgress?.call(0, '正在下载视频到本地…');
        final File local = await _downloadPlayableToCache(
          mediaUrl: remoteUrl,
          idKey: ref.idKey,
          onProgress: (double? p) {
            if (p == null) {
              onProgress?.call(null, '正在下载视频…');
              return;
            }
            onProgress?.call(
              p,
              '正在下载视频 ${(p * 100).clamp(0, 100).round()}%',
            );
          },
        );
        onProgress?.call(1, '下载完成');
        return BilibiliPlayableMedia(uri: local.path, headers: null);
      } catch (e) {
        lastDownloadError = e;
      }
    }

    // Local-first: do not silently fall back to online streaming.
    throw StateError(
      '本地下载失败：${_dioErrorSummary(lastDownloadError)}。'
      '请检查网络后重试；已登录时可获得更稳定的取流。',
    );
  }

  /// Ensure a local MP4 exists for ASR / offline tooling.
  ///
  /// Playback may stream through [BilibiliMediaProxy]; speech recognition needs
  /// a real file path on disk.
  Future<String> ensureLocalCacheForAsr(
    String rawInput, {
    void Function(double? progress, String message)? onProgress,
  }) async {
    onProgress?.call(null, '正在准备本地视频…');
    final _BilibiliVideoRef ref = await _resolveVideoRef(rawInput);
    final File? cached = await _existingCacheFile(ref.idKey);
    if (cached != null) {
      onProgress?.call(1, '使用已缓存视频');
      return cached.path;
    }

    onProgress?.call(null, '正在解析播放地址…');
    final List<String> remoteUrls = await _fetchPlayableDurlCandidates(ref);
    if (remoteUrls.isEmpty) {
      throw StateError('B 站取流失败：无可用地址');
    }

    Object? lastError;
    for (final String remoteUrl in remoteUrls) {
      try {
        onProgress?.call(0, '正在下载视频供语音识别…');
        final File local = await _downloadPlayableToCache(
          mediaUrl: remoteUrl,
          idKey: ref.idKey,
          onProgress: (double? p) {
            if (p == null) {
              onProgress?.call(null, '正在下载视频…');
              return;
            }
            onProgress?.call(
              p,
              '正在下载视频 ${(p * 100).clamp(0, 100).round()}%',
            );
          },
        );
        return local.path;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError(
      '无法下载视频供语音识别：${_dioErrorSummary(lastError)}',
    );
  }

  /// Return an on-disk import/cache MP4 for [rawInput] without downloading.
  ///
  /// Prefers a cheap BV/av filename probe so open-after-import stays offline
  /// when the file is already in `bilibili_media/`.
  Future<String?> findExistingLocalCache(String rawInput) async {
    final String? cheapKey = _cheapMediaIdKey(rawInput);
    if (cheapKey != null && cheapKey.isNotEmpty) {
      final int? page = BilibiliImport.extractPage(rawInput);
      final List<String> probes = <String>[
        if (page != null && page > 1)
          BilibiliImport.mediaIdKey(
            bvidOrAv: cheapKey,
            page: page,
            pageCount: 2,
          ),
        cheapKey,
      ];
      for (final String key in probes) {
        final File? cached = await _existingCacheFile(key);
        if (cached != null) {
          return cached.path;
        }
      }
    }
    try {
      final _BilibiliVideoRef ref = await _resolveVideoRef(rawInput);
      final File? cached = await _existingCacheFile(ref.idKey);
      return cached?.path;
    } catch (_) {
      return null;
    }
  }

  String? _cheapMediaIdKey(String rawInput) {
    final Map<String, String>? ids = BilibiliImport.extractIds(rawInput);
    if (ids != null) {
      final String? bvid = ids['bvid']?.trim();
      if (bvid != null && bvid.isNotEmpty) {
        return bvid;
      }
      final String? aid = ids['aid']?.trim();
      if (aid != null && aid.isNotEmpty) {
        return 'av$aid';
      }
    }
    final RegExpMatch? bv = RegExp(
      r'(BV[0-9A-Za-z]+)',
      caseSensitive: false,
    ).firstMatch(rawInput);
    if (bv != null) {
      return bv.group(1);
    }
    final RegExpMatch? av = RegExp(
      r'(?:^|[/\\_-])(av\d+)(?:[/\\_.-]|$)',
      caseSensitive: false,
    ).firstMatch(rawInput);
    return av?.group(1);
  }

  Future<void> _assertRemoteIsPlayable(String mediaUrl) async {
    Object? lastError;
    // Prefer a tiny Range GET. Fall back to HEAD when the node rejects Range.
    for (final bool useRange in <bool>[true, false]) {
      try {
        if (useRange) {
          final Response<List<int>> res = await _dio.get<List<int>>(
            mediaUrl,
            options: Options(
              headers: <String, dynamic>{
                ..._playHeadersWithAuth,
                'Range': 'bytes=0-1023',
              },
              responseType: ResponseType.bytes,
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (int? code) =>
                  code != null && code >= 200 && code < 400,
            ),
          );
          final List<int> bytes = res.data ?? const <int>[];
          if (bytes.isEmpty) {
            throw StateError('取流探活返回空内容');
          }
          final String contentType =
              (res.headers.value('content-type') ?? '').toLowerCase();
          if (contentType.contains('text/html') ||
              contentType.contains('application/json')) {
            throw StateError('CDN 返回了网页而不是视频（可能被防盗链拦截）');
          }
          final String head = String.fromCharCodes(
            bytes.take(64).where((int b) => b >= 32 && b < 127),
          );
          if (head.contains('<html') || head.contains('<!DOCTYPE')) {
            throw StateError('CDN 返回了 HTML，无法播放');
          }
          return;
        }

        final Response<void> head = await _dio.head<void>(
          mediaUrl,
          options: Options(
            headers: _playHeadersWithAuth,
            receiveTimeout: const Duration(seconds: 15),
            validateStatus: (int? code) =>
                code != null && code >= 200 && code < 400,
          ),
        );
        final String contentType =
            (head.headers.value('content-type') ?? '').toLowerCase();
        if (contentType.contains('text/html') ||
            contentType.contains('application/json')) {
          throw StateError('CDN 返回了网页而不是视频（可能被防盗链拦截）');
        }
        return;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError is StateError) {
      throw lastError;
    }
    throw StateError('无法访问 B 站视频流：${_dioErrorSummary(lastError)}');
  }

  String _dioErrorSummary(Object? error) {
    if (error is DioException) {
      final int? code = error.response?.statusCode;
      final String path = error.requestOptions.uri.host;
      if (code != null) {
        return 'HTTP $code ($path)';
      }
      return '${error.type.name} ($path)';
    }
    final String text = '$error'.replaceFirst('Bad state: ', '');
    if (text.length <= 120) {
      return text;
    }
    return '${text.substring(0, 117)}...';
  }

  Future<_BilibiliVideoRef> _resolveVideoRef(String rawInput) async {
    final Map<String, String>? ids = await resolveIds(rawInput);
    if (ids == null) {
      throw StateError('无法识别 B 站链接（请贴完整 BV 或分享文案）');
    }
    final Response<dynamic> viewRes;
    try {
      viewRes = await _dio.get<dynamic>(
        'https://api.bilibili.com/x/web-interface/view',
        queryParameters: ids,
        options: Options(
          headers: <String, dynamic>{
            'Accept': 'application/json, text/plain, */*',
          },
          validateStatus: (int? code) =>
              code != null && code >= 200 && code < 500,
        ),
      );
    } catch (e) {
      throw StateError('获取视频信息失败：${_dioErrorSummary(e)}');
    }
    if ((viewRes.statusCode ?? 0) >= 400) {
      throw StateError(
        '获取视频信息失败：HTTP ${viewRes.statusCode} '
        '(${ids.entries.map((e) => '${e.key}=${e.value}').join('&')})',
      );
    }
    final Map<String, dynamic> viewRoot = _asJsonMap(viewRes.data);
    final int code = viewRoot['code'] as int? ?? -1;
    if (code != 0) {
      throw StateError(
        (viewRoot['message'] as String?) ?? '无法获取 B 站视频信息（code=$code）',
      );
    }
    final Map<String, dynamic> data = _asJsonMap(viewRoot['data']);
    final String bvid = (data['bvid'] as String?) ?? ids['bvid'] ?? '';
    final String? aid =
        ids['aid'] ?? (data['aid'] as num?)?.toInt().toString();
    final List<BilibiliPageMeta> pageMetas = _parsePages(data);
    final int requestedPage = BilibiliImport.extractPage(rawInput) ?? 1;
    final BilibiliPageMeta selected = _pageMetaFor(
      pageMetas,
      requestedPage: requestedPage,
      fallbackCid: (data['cid'] as num?)?.toInt() ?? 0,
      fallbackDurationSec: (data['duration'] as num?)?.toInt() ?? 60,
    );
    final int cid = selected.cid;
    if (cid <= 0) {
      throw StateError('视频缺少 cid，无法取流');
    }
    final String rootKey = bvid.isNotEmpty
        ? bvid
        : (aid == null ? 'cid$cid' : 'av$aid');
    final String idKey = BilibiliImport.mediaIdKey(
      bvidOrAv: rootKey,
      page: selected.page,
      pageCount: pageMetas.isEmpty ? 1 : pageMetas.length,
    );
    return _BilibiliVideoRef(
      bvid: bvid,
      aid: aid,
      cid: cid,
      idKey: idKey,
      page: selected.page,
    );
  }

  Future<List<String>> _fetchPlayableDurlCandidates(
    _BilibiliVideoRef ref,
  ) async {
    // Prefer smaller MP4 first so first-open is faster on mobile.
    // Prefer bvid-only queries — large avid values can confuse some gateways.
    final List<Map<String, dynamic>> attempts = <Map<String, dynamic>>[
      <String, dynamic>{
        if (ref.bvid.isNotEmpty) 'bvid': ref.bvid,
        if (ref.bvid.isEmpty && ref.aid != null) 'avid': ref.aid,
        'cid': ref.cid,
        'platform': 'html5',
        'qn': 16,
      },
      <String, dynamic>{
        if (ref.bvid.isNotEmpty) 'bvid': ref.bvid,
        if (ref.bvid.isEmpty && ref.aid != null) 'avid': ref.aid,
        'cid': ref.cid,
        'platform': 'html5',
        'high_quality': 1,
        'qn': 64,
      },
      <String, dynamic>{
        if (ref.bvid.isNotEmpty) 'bvid': ref.bvid,
        if (ref.bvid.isEmpty && ref.aid != null) 'avid': ref.aid,
        'cid': ref.cid,
        'qn': 16,
        'fnval': 1,
      },
      <String, dynamic>{
        if (ref.bvid.isNotEmpty) 'bvid': ref.bvid,
        if (ref.bvid.isEmpty && ref.aid != null) 'avid': ref.aid,
        'cid': ref.cid,
        'qn': 64,
        'fnval': 1,
        'fourk': 1,
      },
      <String, dynamic>{
        if (ref.bvid.isNotEmpty) 'bvid': ref.bvid,
        if (ref.bvid.isEmpty && ref.aid != null) 'avid': ref.aid,
        'cid': ref.cid,
        'qn': 64,
        'fnval': 16,
      },
    ];

    final List<String> errors = <String>[];
    for (final Map<String, dynamic> query in attempts) {
      try {
        final Response<dynamic> playRes = await _dio.get<dynamic>(
          'https://api.bilibili.com/x/player/playurl',
          queryParameters: query,
          options: Options(
            headers: <String, dynamic>{
              'Accept': 'application/json, text/plain, */*',
              ..._authHeaders,
            },
            validateStatus: (int? code) =>
                code != null && code >= 200 && code < 500,
          ),
        );
        if ((playRes.statusCode ?? 0) >= 400) {
          errors.add(
            '${query['platform'] ?? query['fnval']}: '
            'HTTP ${playRes.statusCode}',
          );
          continue;
        }
        final Map<String, dynamic> playRoot = _asJsonMap(playRes.data);
        final int code = playRoot['code'] as int? ?? -1;
        if (code != 0) {
          errors.add(
            '${query['platform'] ?? query['fnval']}: '
            '${playRoot['message'] ?? code}',
          );
          continue;
        }
        final List<String> urls =
            _extractPlayableUrls(_asJsonMap(playRoot['data']));
        if (urls.isNotEmpty) {
          return urls;
        }
        errors.add('${query['platform'] ?? query['fnval']}: 无可用流地址');
      } catch (e) {
        errors.add(
          '${query['platform'] ?? query['fnval']}: ${_dioErrorSummary(e)}',
        );
      }
    }
    throw StateError(
      'B 站取流失败${errors.isEmpty ? '' : '：${errors.first}'}',
    );
  }

  List<String> _extractPlayableUrls(Map<String, dynamic> playData) {
    final LinkedHashSet<String> urls = LinkedHashSet<String>();
    final List<dynamic> durl =
        playData['durl'] as List<dynamic>? ?? const <dynamic>[];
    for (final dynamic item in durl) {
      if (item is! Map) {
        continue;
      }
      final Map<String, dynamic> row = item.cast<String, dynamic>();
      final String? url = row['url'] as String?;
      if (url != null && url.isNotEmpty) {
        urls.add(url);
      }
      final List<dynamic> backups =
          row['backup_url'] as List<dynamic>? ??
          row['backupUrl'] as List<dynamic>? ??
          const <dynamic>[];
      for (final dynamic backup in backups) {
        if (backup is String && backup.isNotEmpty) {
          urls.add(backup);
        }
      }
    }
    final Map<String, dynamic> dash = _asJsonMap(playData['dash']);
    final List<dynamic> videos =
        dash['video'] as List<dynamic>? ?? const <dynamic>[];
    for (final dynamic item in videos) {
      if (item is! Map) {
        continue;
      }
      final Map<String, dynamic> video = item.cast<String, dynamic>();
      final String? url =
          (video['baseUrl'] as String?) ?? (video['base_url'] as String?);
      if (url != null && url.isNotEmpty) {
        urls.add(url);
      }
      final List<dynamic> backups =
          video['backupUrl'] as List<dynamic>? ??
          video['backup_url'] as List<dynamic>? ??
          const <dynamic>[];
      for (final dynamic backup in backups) {
        if (backup is String && backup.isNotEmpty) {
          urls.add(backup);
        }
      }
    }
    return urls.toList(growable: false);
  }

  Future<File?> _existingCacheFile(String idKey) async {
    for (final String key in BilibiliImport.mediaIdKeyAliases(idKey)) {
      final File file = await _cacheFileFor(key);
      if (!file.existsSync()) {
        continue;
      }
      final int size = file.lengthSync();
      // Keep imported media for learning; only reject tiny / corrupt stubs.
      if (size < 64 * 1024) {
        continue;
      }
      return file;
    }
    return null;
  }

  Future<File> _cacheFileFor(String idKey) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/bilibili_media');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$idKey.mp4');
  }

  Future<File> _downloadPlayableToCache({
    required String mediaUrl,
    required String idKey,
    void Function(double? progress)? onProgress,
  }) async {
    final File? already = await _existingCacheFile(idKey);
    if (already != null) {
      onProgress?.call(1);
      return already;
    }

    // Share one download across import / player prepare / 合集 background.
    for (final String alias in BilibiliImport.mediaIdKeyAliases(idKey)) {
      final Future<File>? inflight = _inflightCacheDownloads[alias];
      if (inflight != null) {
        final File shared = await inflight;
        onProgress?.call(1);
        return shared;
      }
    }

    final Future<File> download = _downloadPlayableToCacheUnlocked(
      mediaUrl: mediaUrl,
      idKey: idKey,
      onProgress: onProgress,
    );
    for (final String alias in BilibiliImport.mediaIdKeyAliases(idKey)) {
      _inflightCacheDownloads[alias] = download;
    }
    try {
      return await download;
    } finally {
      for (final String alias in BilibiliImport.mediaIdKeyAliases(idKey)) {
        if (identical(_inflightCacheDownloads[alias], download)) {
          _inflightCacheDownloads.remove(alias);
        }
      }
    }
  }

  Future<File> _downloadPlayableToCacheUnlocked({
    required String mediaUrl,
    required String idKey,
    void Function(double? progress)? onProgress,
  }) async {
    final File? already = await _existingCacheFile(idKey);
    if (already != null) {
      onProgress?.call(1);
      return already;
    }
    final File out = await _cacheFileFor(idKey);
    final File temp = File('${out.path}.part');
    if (temp.existsSync()) {
      await temp.delete();
    }
    try {
      await _dio.download(
        mediaUrl,
        temp.path,
        options: Options(
          headers: _playHeadersWithAuth,
          // Anthology P1 alone can be 100MB+; keep the socket alive on slow nets.
          receiveTimeout: const Duration(minutes: 45),
          sendTimeout: const Duration(minutes: 2),
        ),
        onReceiveProgress: (int received, int total) {
          if (total <= 0) {
            onProgress?.call(null);
            return;
          }
          onProgress?.call((received / total).clamp(0.0, 1.0));
        },
      );
      if (!temp.existsSync() || temp.lengthSync() < 64 * 1024) {
        throw StateError('缓存文件过小或不存在');
      }
      final RandomAccessFile raf = await temp.open();
      final List<int> head = await raf.read(64);
      await raf.close();
      final String ascii = String.fromCharCodes(
        head.where((int b) => b >= 32 && b < 127),
      );
      if (ascii.contains('<html') || ascii.contains('<!DOCTYPE')) {
        throw StateError('缓存到的是网页，不是视频');
      }
      if (!ascii.contains('ftyp') && head.length >= 8) {
        // Still allow non-mp4 containers if CDN returned playable bytes.
      }
      if (out.existsSync()) {
        await out.delete();
      }
      await temp.rename(out.path);
      onProgress?.call(1);
      return out;
    } catch (e) {
      if (temp.existsSync()) {
        await temp.delete();
      }
      throw StateError('B 站视频缓存失败：$e');
    }
  }

  Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    if (value is String && value.isNotEmpty) {
      final dynamic decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    }
    return <String, dynamic>{};
  }

  static const Map<String, String> playHttpHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://www.bilibili.com',
    'Origin': 'https://www.bilibili.com',
    'Accept': '*/*',
  };

  /// Re-fetch official CC/AI subtitle files for a BV/av/watch URL.
  ///
  /// Returns English/Chinese SRT paths when available (biliSub-style first hop).
  Future<Map<String, String?>> fetchOfficialSubtitleTracks(
    String rawInput,
  ) async {
    final BilibiliImportResult meta = await fetch(rawInput);
    return <String, String?>{
      'en': meta.enSubtitlePath,
      'zh': meta.cnSubtitlePath,
      if (meta.subtitleNote != null) 'note': meta.subtitleNote,
    };
  }

  /// Delete cached official EN/ZH under `Documents/bilibili/<idKey>/`.
  ///
  /// Used when B站 confirms there is no CC for this cid — keeping a stale
  /// `zh.srt` from an earlier串台 download would poison playback forever.
  Future<void> clearOfficialSubtitleFiles(String? idKey) async {
    final List<String> keys = BilibiliImport.officialSubtitleFolderKeys(
      idKey ?? '',
    );
    if (keys.isEmpty) {
      return;
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory root = Directory('${docs.path}/bilibili');
    if (!root.existsSync()) {
      return;
    }
    await for (final FileSystemEntity entity in root.list()) {
      if (entity is! Directory) {
        continue;
      }
      final String name = entity.uri.pathSegments
          .lastWhere((String segment) => segment.isNotEmpty, orElse: () => '')
          .toUpperCase();
      if (!keys.contains(name)) {
        continue;
      }
      for (final String fileName in <String>['en.srt', 'zh.srt']) {
        final File file = File(
          '${entity.path}${Platform.pathSeparator}$fileName',
        );
        if (file.existsSync()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<Map<String, String?>> _fetchSubtitles({
    required String bvid,
    String? aid,
    required int cid,
    required String idKey,
  }) async {
    final List<Map<String, dynamic>> list = await _listSubtitleTracks(
      bvid: bvid,
      aid: aid,
      cid: cid,
    );
    if (list.isEmpty) {
      // Confirmed empty track list → wipe stale SRTs for this BV/page.
      await clearOfficialSubtitleFiles(idKey);
      return const <String, String?>{};
    }

    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/bilibili/$idKey');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    // Prefer human CC over AI tracks when both exist for the same language.
    list.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int aiA = _isAiSubtitleTrack(a) ? 1 : 0;
      final int aiB = _isAiSubtitleTrack(b) ? 1 : 0;
      return aiA.compareTo(aiB);
    });

    // ignore: avoid_print
    print(
      'bilibili.subs tracks=${list.length} '
      'lans=${list.map((Map<String, dynamic> t) => t['lan']).join(',')}',
    );

    String? enPath;
    String? zhPath;
    for (final Map<String, dynamic> raw in list) {
      final String lan = (raw['lan'] as String? ?? '').toLowerCase();
      final String lanDoc = (raw['lan_doc'] as String? ?? '').toLowerCase();
      final String? url = _subtitleTrackUrl(raw);
      if (url == null) {
        continue;
      }
      final bool isZh = _isZhSubtitleLan(lan, lanDoc);
      final bool isEn = _isEnSubtitleLan(lan, lanDoc);
      if (!isZh && !isEn) {
        continue;
      }
      // Prefer explicit English tags over ambiguous zh/en collisions.
      final bool treatAsEn = isEn && !isZh;
      final String? path = await _downloadJsonSubtitleToSrt(
        url,
        File('${dir.path}/${treatAsEn ? 'en' : 'zh'}.srt'),
      );
      if (path == null) {
        continue;
      }
      if (treatAsEn) {
        // Some B站 tracks are labeled en/ai-en but body is Chinese.
        if (_srtLooksChineseOnly(path)) {
          zhPath ??= path;
        } else {
          enPath ??= path;
        }
      } else {
        zhPath ??= path;
      }
    }
    // If language tags are unusual, still keep the first downloadable track.
    if (enPath == null && zhPath == null) {
      for (final Map<String, dynamic> raw in list) {
        final String? url = _subtitleTrackUrl(raw);
        if (url == null) {
          continue;
        }
        final String lan = (raw['lan'] as String? ?? 'und').toLowerCase();
        final bool treatAsEn = lan.contains('en');
        final String? path = await _downloadJsonSubtitleToSrt(
          url,
          File('${dir.path}/${treatAsEn ? 'en' : 'zh'}.srt'),
        );
        if (path == null) {
          continue;
        }
        if (treatAsEn) {
          enPath = path;
        } else {
          zhPath = path;
        }
        break;
      }
    }
    return <String, String?>{'en': enPath, 'zh': zhPath};
  }

  Future<List<Map<String, dynamic>>> _listSubtitleTracks({
    required String bvid,
    String? aid,
    required int cid,
  }) async {
    // dm/view often lists human CC (en-US) + AI tracks without login.
    // player/v2 may require login and still omit some CC rows.
    final List<({String url, Map<String, dynamic> query})> endpoints =
        <({String url, Map<String, dynamic> query})>[
          if (aid != null && aid.isNotEmpty)
            (
              url: 'https://api.bilibili.com/x/v2/dm/view',
              query: <String, dynamic>{
                'aid': aid,
                'oid': cid,
                'type': 1,
              },
            ),
          (
            url: 'https://api.bilibili.com/x/player/v2',
            query: <String, dynamic>{
              if (bvid.isNotEmpty) 'bvid': bvid,
              'cid': cid,
            },
          ),
          (
            url: 'https://api.bilibili.com/x/player/wbi/v2',
            query: <String, dynamic>{
              if (bvid.isNotEmpty) 'bvid': bvid,
              'cid': cid,
            },
          ),
        ];
    final Map<String, Map<String, dynamic>> merged =
        <String, Map<String, dynamic>>{};
    for (final ({String url, Map<String, dynamic> query}) endpoint
        in endpoints) {
      try {
        final Response<dynamic> playerRes = await _dio.get<dynamic>(
          endpoint.url,
          queryParameters: endpoint.query,
          options: Options(
            headers: <String, dynamic>{
              'Accept': 'application/json, text/plain, */*',
              ..._authHeaders,
            },
            validateStatus: (int? code) =>
                code != null && code >= 200 && code < 500,
          ),
        );
        if ((playerRes.statusCode ?? 0) >= 400) {
          continue;
        }
        final Map<String, dynamic> root = _asJsonMap(playerRes.data);
        if ((root['code'] as int? ?? -1) != 0) {
          continue;
        }
        final Map<String, dynamic> data = _asJsonMap(root['data']);
        final List<Map<String, dynamic>> tracks = <Map<String, dynamic>>[
          ..._subtitleMaps(_asJsonMap(data['subtitle'])['subtitles']),
          ..._subtitleMaps(_asJsonMap(data['subtitle'])['list']),
          ..._subtitleMaps(_asJsonMap(data['ai_subtitle'])['subtitles']),
        ];
        for (final Map<String, dynamic> track in tracks) {
          final String key =
              '${track['lan']}|${_subtitleTrackUrl(track) ?? track['id_str'] ?? track['id']}';
          merged.putIfAbsent(key, () => track);
        }
      } catch (_) {
        // Try the next endpoint.
      }
    }
    return merged.values.toList(growable: false);
  }

  List<Map<String, dynamic>> _subtitleMaps(dynamic rawList) {
    if (rawList is! List) {
      return const <Map<String, dynamic>>[];
    }
    final List<Map<String, dynamic>> tracks = <Map<String, dynamic>>[];
    for (final dynamic item in rawList) {
      if (item is Map<String, dynamic>) {
        tracks.add(item);
      } else if (item is Map) {
        tracks.add(item.cast<String, dynamic>());
      }
    }
    return tracks;
  }

  String? _subtitleTrackUrl(Map<String, dynamic> track) {
    for (final String key in <String>['subtitle_url', 'subtitle_url_v2', 'url']) {
      final String? raw = track[key] as String?;
      if (raw == null || raw.trim().isEmpty) {
        continue;
      }
      final String url = raw.trim();
      if (url.startsWith('//')) {
        return 'https:$url';
      }
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
      }
      return 'https:$url';
    }
    return null;
  }

  bool _isAiSubtitleTrack(Map<String, dynamic> track) {
    final String lan = (track['lan'] as String? ?? '').toLowerCase();
    final String lanDoc = (track['lan_doc'] as String? ?? '').toLowerCase();
    return lan.startsWith('ai-') ||
        lanDoc.contains('ai') ||
        lanDoc.contains('智能');
  }

  bool _isZhSubtitleLan(String lan, String lanDoc) {
    final String normalizedLan = lan.trim().toLowerCase();
    if (normalizedLan == 'ai-zh' ||
        normalizedLan.startsWith('zh') ||
        normalizedLan == 'chs' ||
        normalizedLan == 'cht' ||
        normalizedLan == 'cn') {
      return true;
    }
    final String blob = '$normalizedLan $lanDoc';
    return blob.contains('中') ||
        blob.contains('汉') ||
        RegExp(r'(^|[^a-z])(zh|chs|cht)([^a-z]|$)').hasMatch(blob);
  }

  bool _isEnSubtitleLan(String lan, String lanDoc) {
    final String normalizedLan = lan.trim().toLowerCase();
    if (normalizedLan == 'ai-en' ||
        normalizedLan == 'en' ||
        normalizedLan.startsWith('en-') ||
        normalizedLan.startsWith('en_')) {
      return true;
    }
    final String blob = '$normalizedLan $lanDoc';
    return blob.contains('英') ||
        RegExp(r'(^|[^a-z])en([^a-z]|$)').hasMatch(blob);
  }

  bool _srtLooksChineseOnly(String path) {
    try {
      final String raw = File(path).readAsStringSync();
      final String text = raw
          .replaceAll(RegExp(r'\d+:\d+:\d+[.,]\d+\s*-->\s*\d+:\d+:\d+[.,]\d+'), ' ')
          .replaceAll(RegExp(r'^\d+\s*$', multiLine: true), ' ')
          .replaceAll(RegExp(r'WEBVTT'), ' ');
      final int latin = RegExp(r'[A-Za-z]').allMatches(text).length;
      final int chinese = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
      return chinese > 0 && chinese >= latin;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _downloadJsonSubtitleToSrt(String url, File outFile) async {
    final Response<dynamic> res = await _dio.get<dynamic>(
      url,
      options: Options(
        headers: <String, dynamic>{
          'Accept': 'application/json, text/plain, */*',
          ..._authHeaders,
        },
      ),
    );
    final dynamic body = res.data;
    final Map<String, dynamic> json = body is String
        ? jsonDecode(body) as Map<String, dynamic>
        : body as Map<String, dynamic>;
    final List<dynamic> cues =
        json['body'] as List<dynamic>? ?? const <dynamic>[];
    if (cues.isEmpty) {
      return null;
    }
    final StringBuffer srt = StringBuffer();
    int index = 1;
    for (final dynamic cue in cues) {
      if (cue is! Map<String, dynamic>) {
        continue;
      }
      final double from = (cue['from'] as num?)?.toDouble() ?? 0;
      final double to = (cue['to'] as num?)?.toDouble() ?? from + 1;
      final String content = (cue['content'] as String? ?? '').trim();
      if (content.isEmpty) {
        continue;
      }
      srt
        ..writeln(index)
        ..writeln('${_fmt(from)} --> ${_fmt(to)}')
        ..writeln(content)
        ..writeln();
      index += 1;
    }
    if (index == 1) {
      return null;
    }
    await outFile.writeAsString(srt.toString(), flush: true);
    return outFile.path;
  }

  String _fmt(double seconds) {
    final Duration d = Duration(milliseconds: (seconds * 1000).round());
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int secs = d.inSeconds.remainder(60);
    final int millis = d.inMilliseconds.remainder(1000);
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(hours)}:${two(minutes)}:${two(secs)},${three(millis)}';
  }
}

class BilibiliSeasonParseResult {
  const BilibiliSeasonParseResult({
    this.id,
    this.title,
    this.coverUrl,
    this.episodes = const <BilibiliSeasonEpisodeMeta>[],
  });

  final String? id;
  final String? title;
  final String? coverUrl;
  final List<BilibiliSeasonEpisodeMeta> episodes;
}

/// Parses `data.ugc_season` from `/x/web-interface/view`.
BilibiliSeasonParseResult parseBilibiliUgcSeason(
  Map<String, dynamic> data, {
  String? Function(String? raw)? normalizeCoverUrl,
}) {
  final Object? rawSeason = data['ugc_season'];
  if (rawSeason is! Map) {
    return const BilibiliSeasonParseResult();
  }
  final Map<String, dynamic> season = rawSeason.cast<String, dynamic>();
  final String id = '${season['id'] ?? ''}'.trim();
  final String title = (season['title'] as String?)?.trim() ?? '';
  final String? coverUrl = normalizeCoverUrl == null
      ? (season['cover'] as String?)?.trim()
      : normalizeCoverUrl(season['cover'] as String?);
  final List<dynamic> sections =
      season['sections'] as List<dynamic>? ?? const <dynamic>[];
  final List<BilibiliSeasonEpisodeMeta> episodes =
      <BilibiliSeasonEpisodeMeta>[];
  for (final dynamic rawSection in sections) {
    if (rawSection is! Map) {
      continue;
    }
    final Map<String, dynamic> section = rawSection.cast<String, dynamic>();
    final List<dynamic> rawEpisodes =
        section['episodes'] as List<dynamic>? ?? const <dynamic>[];
    for (final dynamic rawEpisode in rawEpisodes) {
      if (rawEpisode is! Map) {
        continue;
      }
      final Map<String, dynamic> episode = rawEpisode.cast<String, dynamic>();
      final Map<String, dynamic> arc =
          (episode['arc'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final Map<String, dynamic> page =
          (episode['page'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final String bvid =
          ((episode['bvid'] as String?) ?? (arc['bvid'] as String?) ?? '')
              .trim();
      final String aid = '${episode['aid'] ?? arc['aid'] ?? ''}'.trim();
      if (bvid.isEmpty && aid.isEmpty) {
        continue;
      }
      final String rawTitle =
          ((episode['title'] as String?)?.trim().isNotEmpty == true
              ? (episode['title'] as String).trim()
              : (arc['title'] as String?)?.trim().isNotEmpty == true
              ? (arc['title'] as String).trim()
              : (page['part'] as String?)?.trim() ?? '');
      final String epTitle = rawTitle.isNotEmpty
          ? rawTitle
          : (bvid.isNotEmpty ? bvid : 'av$aid');
      final int cid =
          (episode['cid'] as num?)?.toInt() ??
          (page['cid'] as num?)?.toInt() ??
          0;
      final int durationSec =
          (page['duration'] as num?)?.toInt() ??
          (arc['duration'] as num?)?.toInt() ??
          (episode['duration'] as num?)?.toInt() ??
          0;
      final String? rawCover =
          (episode['cover'] as String?)?.trim().isNotEmpty == true
          ? (episode['cover'] as String).trim()
          : (arc['pic'] as String?)?.trim().isNotEmpty == true
          ? (arc['pic'] as String).trim()
          : (arc['first_frame'] as String?)?.trim();
      final String? normalizedCover = normalizeCoverUrl == null
          ? rawCover
          : normalizeCoverUrl(rawCover);
      episodes.add(
        BilibiliSeasonEpisodeMeta(
          index: episodes.length + 1,
          title: epTitle,
          bvid: bvid,
          aid: aid,
          cid: cid,
          durationSec: durationSec,
          coverImageUrl: normalizedCover ?? coverUrl,
        ),
      );
    }
  }
  return BilibiliSeasonParseResult(
    id: id.isEmpty ? null : id,
    title: title.isEmpty ? null : title,
    coverUrl: coverUrl,
    episodes: episodes,
  );
}

class BilibiliPlayableMedia {
  const BilibiliPlayableMedia({
    required this.uri,
    required this.headers,
  });

  final String uri;
  final Map<String, String>? headers;

  /// True when [uri] is an on-disk file (not CDN / localhost proxy).
  bool get isLocalFile {
    final String value = uri.trim();
    if (value.isEmpty) {
      return false;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return false;
    }
    final File file = File(value);
    return file.existsSync() && file.lengthSync() > 64 * 1024;
  }
}

class _BilibiliVideoRef {
  const _BilibiliVideoRef({
    required this.bvid,
    required this.aid,
    required this.cid,
    required this.idKey,
    this.page = 1,
  });

  final String bvid;
  final String? aid;
  final int cid;
  final String idKey;
  final int page;
}

class _RawHttpsResponse {
  const _RawHttpsResponse({
    required this.status,
    required this.location,
    required this.body,
  });

  final int status;
  final String? location;
  final String body;
}
