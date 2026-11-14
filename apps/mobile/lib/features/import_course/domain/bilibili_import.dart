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
  static final RegExp _bvOnly = RegExp(
    r'^BV[0-9A-Za-z]+$',
    caseSensitive: false,
  );
  static final RegExp _avOnly = RegExp(r'^av?(\d+)$', caseSensitive: false);

  /// Phone share text often looks like: 【标题-哔哩哔哩】 https://b23.tv/xxxxx
  static final RegExp _urlInText = RegExp(
    r'https?://[^\s\]）)】,，。；;\u3000]+',
    caseSensitive: false,
  );

  static final RegExp _shortLink = RegExp(
    r'(?:https?://)?(?:b23\.tv|bili2233\.cn|bili22\.cn|bili33\.cn)/([A-Za-z0-9_-]+)',
    caseSensitive: false,
  );

  /// Alternate short-link hosts (same path code).
  static const List<String> shortLinkHosts = <String>[
    'bili2233.cn',
    'b23.tv',
  ];

  static final RegExp _invisible = RegExp(
    r'[\u200B-\u200D\uFEFF\u00A0\u202A-\u202E]',
  );

  /// Normalize share paste: strip zero-width / NBSP, collapse spaces.
  static String sanitize(String raw) {
    return raw
        .replaceAll(_invisible, ' ')
        .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
        .trim();
  }

  /// Returns a map with either `bvid` or `aid` key when parse succeeds.
  /// Does not resolve short links; use [looksLikeBilibiliInput] + network resolve.
  static Map<String, String>? extractIds(String raw) {
    final String input = sanitize(raw);
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

  /// True for BV/av, full bilibili URLs, share paste text, or b23.tv short links.
  static bool isBilibiliUrl(String raw) => looksLikeBilibiliInput(raw);

  static bool looksLikeBilibiliInput(String raw) {
    final String input = sanitize(raw);
    if (input.isEmpty) {
      return false;
    }
    if (extractIds(input) != null) {
      return true;
    }
    if (_shortLink.hasMatch(input)) {
      return true;
    }
    final String? url = firstUrlInText(input);
    if (url == null) {
      return false;
    }
    return extractIds(url) != null || isShortLink(url);
  }

  static bool isShortLink(String raw) => _shortLink.hasMatch(sanitize(raw));

  /// Returns the path code of a short link, e.g. `fnJy3OH`.
  static String? shortLinkCode(String raw) {
    final RegExpMatch? match = _shortLink.firstMatch(sanitize(raw));
    return match?.group(1);
  }

  /// Candidate absolute short URLs to try when expanding a share paste.
  /// Prefer `bili2233.cn` first — some VPNs fail DNS for `b23.tv` only.
  static List<String> shortLinkCandidates(String raw) {
    final String? code = shortLinkCode(raw);
    if (code == null || code.isEmpty) {
      final String? url = firstUrlInText(raw);
      return url == null ? const <String>[] : <String>[normalizeHttpUrl(url)];
    }
    return <String>[
      for (final String host in shortLinkHosts) 'https://$host/$code',
    ];
  }

  /// Prefer short-link / bilibili URLs embedded in share text.
  static String? firstUrlInText(String raw) {
    final String input = sanitize(raw);
    String? short;
    String? bilibili;
    String? other;
    for (final RegExpMatch match in _urlInText.allMatches(input)) {
      final String candidate = _stripTrailingPunctuation(match.group(0)!);
      if (isShortLink(candidate)) {
        short ??= candidate;
      } else if (candidate.toLowerCase().contains('bilibili.com')) {
        bilibili ??= candidate;
      } else {
        other ??= candidate;
      }
    }
    if (short != null) {
      return short;
    }
    if (bilibili != null) {
      return bilibili;
    }
    // Bare short link without scheme: b23.tv/xxxxx
    final RegExpMatch? bare = _shortLink.firstMatch(input);
    if (bare != null) {
      final String value = bare.group(0)!;
      return value.toLowerCase().startsWith('http') ? value : 'https://$value';
    }
    return other;
  }

  /// Collapse share paste into the best import candidate for display / fetch.
  static String normalizeInput(String raw) {
    final String input = sanitize(raw);
    final Map<String, String>? ids = extractIds(input);
    if (ids != null) {
      return watchUrl(bvid: ids['bvid'], aid: ids['aid']);
    }
    final String? url = firstUrlInText(input);
    if (url != null) {
      return normalizeHttpUrl(url);
    }
    return input;
  }

  static String normalizeHttpUrl(String raw) {
    final String trimmed = sanitize(raw);
    if (trimmed.toLowerCase().startsWith('http://') ||
        trimmed.toLowerCase().startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  static String _stripTrailingPunctuation(String url) {
    return url.replaceFirst(
      RegExp(r'[.,;:!?）)】》」』|｜]+$'),
      '',
    );
  }

  /// 1-based page index from `?p=` / `&p=` when present.
  static int? extractPage(String raw) {
    final RegExpMatch? match = RegExp(
      r'[?&#]p=(\d+)',
      caseSensitive: false,
    ).firstMatch(sanitize(raw));
    if (match == null) {
      return null;
    }
    final int? page = int.tryParse(match.group(1) ?? '');
    if (page == null || page < 1) {
      return null;
    }
    return page;
  }

  static String watchUrl({String? bvid, String? aid, int? page}) {
    final String base = (bvid != null && bvid.isNotEmpty)
        ? 'https://www.bilibili.com/video/$bvid'
        : 'https://www.bilibili.com/video/av$aid';
    if (page != null && page > 1) {
      return '$base?p=$page';
    }
    return base;
  }

  /// Cache / subtitle folder key. Multi-part anthologies must not share one file.
  static String mediaIdKey({
    required String bvidOrAv,
    required int page,
    required int pageCount,
  }) {
    if (pageCount <= 1) {
      return bvidOrAv;
    }
    return '$bvidOrAv-p${page.clamp(1, 999).toString().padLeft(2, '0')}';
  }

  /// Older builds cached multi-P P1 as bare BV/av without the `-p01` suffix.
  static String? legacyMediaIdKey(String idKey) {
    if (idKey.endsWith('-p01') && idKey.length > 4) {
      return idKey.substring(0, idKey.length - 4);
    }
    return null;
  }

  /// Folder names to try for one BV under `Documents/bilibili/`.
  /// Page 1 is stored as `BV…-p01` (matched case-insensitively).
  static List<String> officialSubtitleFolderKeys(String idKey) {
    final String wanted = idKey.trim().toUpperCase();
    if (wanted.isEmpty) {
      return const <String>[];
    }
    final bool hasPage = RegExp(r'-P\d+$').hasMatch(wanted);
    return <String>[
      wanted,
      if (!hasPage) '$wanted-P01',
      if (wanted.endsWith('-P01')) wanted.substring(0, wanted.length - 4),
    ];
  }

  /// Cache lookup aliases so import (bare BV) and open (`BV-p01`) hit the same
  /// file. Never aliases P2+ — those are different videos.
  static List<String> mediaIdKeyAliases(String idKey) {
    final String trimmed = idKey.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }
    final List<String> keys = <String>[trimmed];
    final String? legacy = legacyMediaIdKey(trimmed);
    if (legacy != null && legacy.isNotEmpty && !keys.contains(legacy)) {
      keys.add(legacy);
    }
    final bool hasPageSuffix = RegExp(
      r'-p\d{2,}$',
      caseSensitive: false,
    ).hasMatch(trimmed);
    if (!hasPageSuffix) {
      // Import may have stored multi-P P1 as `BV-p01` while open resolves bare.
      final String p01 = '$trimmed-p01';
      if (!keys.contains(p01)) {
        keys.add(p01);
      }
    }
    return List<String>.unmodifiable(keys);
  }

  /// True for bilibili.com/video/... page URLs (not playable by media_kit directly).
  static bool isWatchPageUrl(String raw) {
    final String input = sanitize(raw).toLowerCase();
    return input.contains('bilibili.com/video/') ||
        isShortLink(input);
  }
}
