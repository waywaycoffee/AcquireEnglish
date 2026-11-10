import 'package:dio/dio.dart';

/// Bilibili passport QR-login (no password / captcha).
///
/// Flow: generate qrcode_key → user scans in 哔哩哔哩 App → poll until cookies
/// arrive in the success URL / Set-Cookie headers. Then follow the jump URL to
/// collect the full web Cookie set (SESSDATA / bili_jct / DedeUserID).
class BilibiliAuthService {
  BilibiliAuthService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                followRedirects: false,
                headers: <String, dynamic>{
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  'Referer': 'https://www.bilibili.com',
                  'Origin': 'https://www.bilibili.com',
                  'Accept': 'application/json, text/plain, */*',
                },
                validateStatus: (int? code) =>
                    code != null && code >= 200 && code < 500,
              ),
            );

  final Dio _dio;

  static const String _generateUrl =
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate';
  static const String _pollUrl =
      'https://passport.bilibili.com/x/passport-login/web/qrcode/poll';

  Future<BilibiliQrSession> createQrSession() async {
    final Response<dynamic> res = await _dio.get<dynamic>(_generateUrl);
    final Map<String, dynamic> root = _asMap(res.data);
    if ((root['code'] as int? ?? -1) != 0) {
      throw StateError(
        (root['message'] as String?) ?? '无法生成 B 站登录二维码',
      );
    }
    final Map<String, dynamic> data = _asMap(root['data']);
    final String key = (data['qrcode_key'] as String? ?? '').trim();
    final String url = (data['url'] as String? ?? '').trim();
    if (key.isEmpty || url.isEmpty) {
      throw StateError('B 站登录二维码返回为空');
    }
    return BilibiliQrSession(qrcodeKey: key, qrContent: url);
  }

  Future<BilibiliQrPollResult> pollQrSession(String qrcodeKey) async {
    final Response<dynamic> res = await _dio.get<dynamic>(
      _pollUrl,
      queryParameters: <String, dynamic>{'qrcode_key': qrcodeKey},
    );
    final Map<String, dynamic> root = _asMap(res.data);
    if ((root['code'] as int? ?? -1) != 0) {
      return BilibiliQrPollResult(
        status: BilibiliQrPollStatus.failed,
        message: (root['message'] as String?) ?? '轮询失败',
      );
    }
    final Map<String, dynamic> data = _asMap(root['data']);
    final int statusCode = data['code'] as int? ?? -1;
    final String message = (data['message'] as String? ?? '').trim();
    switch (statusCode) {
      case 0:
        final String jumpUrl = (data['url'] as String? ?? '').trim();
        final String refreshToken =
            (data['refresh_token'] as String? ?? '').trim();
        final BilibiliLoginSession? session = await _sessionFromPoll(
          jumpUrl: jumpUrl,
          refreshToken: refreshToken,
          responseHeaders: res.headers,
        );
        if (session == null || session.cookieHeader.isEmpty) {
          return const BilibiliQrPollResult(
            status: BilibiliQrPollStatus.failed,
            message: '扫码成功但未拿到 Cookie，请重试',
          );
        }
        return BilibiliQrPollResult(
          status: BilibiliQrPollStatus.confirmed,
          message: '登录成功',
          session: session,
        );
      case 86101:
        return const BilibiliQrPollResult(
          status: BilibiliQrPollStatus.pending,
          message: '请使用哔哩哔哩 App 扫码',
        );
      case 86090:
        return const BilibiliQrPollResult(
          status: BilibiliQrPollStatus.scanned,
          message: '已扫码，请在手机上确认登录',
        );
      case 86038:
        return const BilibiliQrPollResult(
          status: BilibiliQrPollStatus.pending,
          message: '等待扫码…',
        );
      case 86039:
        return const BilibiliQrPollResult(
          status: BilibiliQrPollStatus.expired,
          message: '二维码已过期，请刷新',
        );
      default:
        return BilibiliQrPollResult(
          status: BilibiliQrPollStatus.failed,
          message: message.isEmpty ? '登录状态 $statusCode' : message,
        );
    }
  }

  Future<BilibiliLoginSession?> _sessionFromPoll({
    required String jumpUrl,
    required String refreshToken,
    required Headers responseHeaders,
  }) async {
    final Map<String, String> cookies = <String, String>{};
    _mergeCookies(cookies, _cookiesFromSetCookie(responseHeaders));
    _mergeCookies(cookies, _cookiesFromJumpUrl(jumpUrl));

    // Follow cross-domain URL so browser-style Set-Cookie is also collected.
    if (jumpUrl.isNotEmpty) {
      try {
        final Response<dynamic> jumpRes = await _dio.get<dynamic>(
          jumpUrl,
          options: Options(
            headers: <String, dynamic>{
              if (cookies.isNotEmpty)
                'Cookie': cookies.entries
                    .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
                    .join('; '),
            },
            followRedirects: false,
            validateStatus: (int? code) =>
                code != null && code >= 200 && code < 400,
          ),
        );
        _mergeCookies(cookies, _cookiesFromSetCookie(jumpRes.headers));
        final String? location = jumpRes.headers.value('location');
        if (location != null && location.isNotEmpty) {
          _mergeCookies(cookies, _cookiesFromJumpUrl(location));
        }
      } catch (_) {
        // Jump follow is best-effort; URL/query cookies may already be enough.
      }
    }

    final String? sess = _cookieValue(cookies, 'SESSDATA');
    if (sess == null || sess.isEmpty) {
      return null;
    }
    final String cookieHeader = _preferredCookieOrder(cookies)
        .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
        .join('; ');
    return BilibiliLoginSession(
      cookieHeader: cookieHeader,
      sessdata: sess,
      dedeUserId: _cookieValue(cookies, 'DedeUserID') ?? '',
      biliJct: _cookieValue(cookies, 'bili_jct') ?? '',
      refreshToken: refreshToken,
    );
  }

  Map<String, String> _cookiesFromJumpUrl(String jumpUrl) {
    final Map<String, String> out = <String, String>{};
    if (jumpUrl.isEmpty) {
      return out;
    }
    try {
      final Uri uri = Uri.parse(jumpUrl);
      uri.queryParameters.forEach((String key, String value) {
        if (value.isEmpty) {
          return;
        }
        final String lower = key.toLowerCase();
        if (lower == 'sessdata' ||
            lower == 'bili_jct' ||
            lower == 'dedeuserid' ||
            lower == 'dedeuserid__ckmd5' ||
            lower == 'sid' ||
            lower == 'buvid3' ||
            lower == 'buvid4') {
          // Keep canonical casing expected by Bilibili APIs.
          out[_canonicalCookieName(key)] = value;
        }
      });
    } catch (_) {}
    return out;
  }

  String _canonicalCookieName(String name) {
    switch (name.toLowerCase()) {
      case 'sessdata':
        return 'SESSDATA';
      case 'bili_jct':
        return 'bili_jct';
      case 'dedeuserid':
        return 'DedeUserID';
      case 'dedeuserid__ckmd5':
        return 'DedeUserID__ckMd5';
      case 'sid':
        return 'sid';
      case 'buvid3':
        return 'buvid3';
      case 'buvid4':
        return 'buvid4';
      default:
        return name;
    }
  }

  List<MapEntry<String, String>> _preferredCookieOrder(
    Map<String, String> cookies,
  ) {
    const List<String> order = <String>[
      'SESSDATA',
      'bili_jct',
      'DedeUserID',
      'DedeUserID__ckMd5',
      'sid',
      'buvid3',
      'buvid4',
    ];
    final List<MapEntry<String, String>> ordered = <MapEntry<String, String>>[];
    final Set<String> seen = <String>{};
    for (final String name in order) {
      final String? value = _cookieValue(cookies, name);
      if (value == null || value.isEmpty) {
        continue;
      }
      ordered.add(MapEntry<String, String>(name, value));
      seen.add(name.toLowerCase());
    }
    for (final MapEntry<String, String> entry in cookies.entries) {
      if (seen.contains(entry.key.toLowerCase())) {
        continue;
      }
      ordered.add(entry);
    }
    return ordered;
  }

  Map<String, String> _cookiesFromSetCookie(Headers headers) {
    final Map<String, String> out = <String, String>{};
    final List<String>? values = headers.map['set-cookie'];
    if (values == null) {
      return out;
    }
    for (final String raw in values) {
      final String first = raw.split(';').first.trim();
      final int eq = first.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      final String name = first.substring(0, eq).trim();
      final String value = first.substring(eq + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        out[_canonicalCookieName(name)] = value;
      }
    }
    return out;
  }

  void _mergeCookies(Map<String, String> target, Map<String, String> extra) {
    extra.forEach((String key, String value) {
      if (value.isEmpty) {
        return;
      }
      target[_canonicalCookieName(key)] = value;
    });
  }

  String? _cookieValue(Map<String, String> cookies, String name) {
    for (final MapEntry<String, String> entry in cookies.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }
}

class BilibiliQrSession {
  const BilibiliQrSession({
    required this.qrcodeKey,
    required this.qrContent,
  });

  final String qrcodeKey;
  /// Content encoded into the QR (passport scan URL).
  final String qrContent;
}

enum BilibiliQrPollStatus {
  pending,
  scanned,
  confirmed,
  expired,
  failed,
}

class BilibiliQrPollResult {
  const BilibiliQrPollResult({
    required this.status,
    required this.message,
    this.session,
  });

  final BilibiliQrPollStatus status;
  final String message;
  final BilibiliLoginSession? session;
}

class BilibiliLoginSession {
  const BilibiliLoginSession({
    required this.cookieHeader,
    required this.sessdata,
    required this.dedeUserId,
    required this.biliJct,
    this.refreshToken = '',
  });

  final String cookieHeader;
  final String sessdata;
  final String dedeUserId;
  final String biliJct;
  final String refreshToken;
}
