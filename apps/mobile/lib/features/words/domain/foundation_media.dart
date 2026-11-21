/// Remote real-person audio/video for zero-foundation IPA / phonics items.
class FoundationMediaItem {
  const FoundationMediaItem({
    required this.bookId,
    required this.key,
    this.audioUrl,
    this.videoUrl,
  });

  factory FoundationMediaItem.fromJson(Map<String, dynamic> json) {
    return FoundationMediaItem(
      bookId: '${json['book_id'] ?? ''}'.trim(),
      key: '${json['key'] ?? ''}'.trim(),
      audioUrl: _nullableUrl(json['audio_url']),
      videoUrl: _nullableUrl(json['video_url']),
    );
  }

  final String bookId;
  final String key;
  final String? audioUrl;
  final String? videoUrl;

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;
  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  static String? _nullableUrl(Object? raw) {
    final String value = '$raw'.trim();
    return value.isEmpty || value == 'null' ? null : value;
  }
}

class FoundationMediaManifest {
  const FoundationMediaManifest({
    required this.version,
    required this.count,
    required this.items,
    this.baseUrl,
  });

  factory FoundationMediaManifest.fromJson(Map<String, dynamic> json) {
    final List<FoundationMediaItem> items = <FoundationMediaItem>[];
    final Object? raw = json['items'];
    if (raw is List) {
      for (final Object? row in raw) {
        if (row is Map) {
          items.add(
            FoundationMediaItem.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }
    return FoundationMediaManifest(
      version: (json['version'] as num?)?.toInt() ?? 1,
      count: (json['count'] as num?)?.toInt() ?? items.length,
      baseUrl: '${json['base_url'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['base_url']}'.trim(),
      items: List<FoundationMediaItem>.unmodifiable(items),
    );
  }

  final int version;
  final int count;
  final String? baseUrl;
  final List<FoundationMediaItem> items;

  static const FoundationMediaManifest empty = FoundationMediaManifest(
    version: 1,
    count: 0,
    items: <FoundationMediaItem>[],
  );

  /// Match syllabus entry [word] under [bookId] (tolerant key normalization).
  FoundationMediaItem? lookup(String bookId, String word) {
    final String bid = bookId.trim().toLowerCase();
    final String want = normKey(word);
    for (final FoundationMediaItem item in items) {
      if (item.bookId.toLowerCase() != bid) continue;
      if (normKey(item.key) == want) return item;
    }
    return null;
  }

  /// Public key normalizer shared with reading / content media lookups.
  static String normKey(String raw) => _normKey(raw);

  FoundationMediaManifest withResolvedUrls(String apiBase) {
    final Uri base = Uri.parse(apiBase.endsWith('/') ? apiBase : '$apiBase/');
    String? abs(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      final Uri uri = Uri.parse(raw);
      if (uri.hasScheme) return raw;
      return base.resolve(raw.startsWith('/') ? raw.substring(1) : raw).toString();
    }

    return FoundationMediaManifest(
      version: version,
      count: count,
      baseUrl: baseUrl ?? apiBase,
      items: items
          .map(
            (FoundationMediaItem item) => FoundationMediaItem(
              bookId: item.bookId,
              key: item.key,
              audioUrl: abs(item.audioUrl),
              videoUrl: abs(item.videoUrl),
            ),
          )
          .toList(growable: false),
    );
  }

  static String _normKey(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}
