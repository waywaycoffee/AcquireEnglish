/// Bilibili URL helpers (paste-link flow, parallel to YouTube).
class BilibiliImport {
  BilibiliImport._();

  static final RegExp _bvInUrl = RegExp(
    r'bilibili\.com/video/(BV[0-9A-Za-z]+)',
    caseSensitive: false,
  );
  static final RegExp _avInUrl = RegExp(
    r'bilibili\.com/video/(?:av)?(\d+)',
    caseSensitive: false,
  );
  static final RegExp _bvOnly = RegExp(r'^BV[0-9A-Za-z]+$', caseSensitive: false);
  static final RegExp _avOnly = RegExp(r'^av?(\d+)$', caseSensitive: false);

  /// Returns a map with either `bvid` or `aid` key when parse succeeds.
  static Map<String, String>? extractIds(String raw) {
    final String input = raw.trim();
    if (input.isEmpty) {
      return null;
    }
    final RegExpMatch? bvUrl = _bvInUrl.firstMatch(input);
    if (bvUrl != null) {
      return <String, String>{'bvid': bvUrl.group(1)!};
    }
    if (_bvOnly.hasMatch(input)) {
      return <String, String>{'bvid': input};
    }
    final RegExpMatch? avUrl = _avInUrl.firstMatch(input);
    if (avUrl != null) {
      return <String, String>{'aid': avUrl.group(1)!};
    }
    final RegExpMatch? avOnly = _avOnly.firstMatch(input);
    if (avOnly != null) {
      return <String, String>{'aid': avOnly.group(1)!};
    }
    return null;
  }

  static bool isBilibiliUrl(String raw) => extractIds(raw) != null;

  static String watchUrl({String? bvid, String? aid}) {
    if (bvid != null && bvid.isNotEmpty) {
      return 'https://www.bilibili.com/video/$bvid';
    }
    return 'https://www.bilibili.com/video/av$aid';
  }
}
