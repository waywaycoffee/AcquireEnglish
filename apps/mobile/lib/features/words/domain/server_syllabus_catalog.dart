import 'syllabus_book.dart';

class ServerSyllabusCatalogItem {
  const ServerSyllabusCatalogItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.examTag,
    required this.disclaimer,
    required this.wordCount,
    required this.url,
    this.bytes = 0,
  });

  factory ServerSyllabusCatalogItem.fromJson(Map<String, dynamic> json) {
    return ServerSyllabusCatalogItem(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      kind: SyllabusBookKind.fromName('${json['kind'] ?? ''}'),
      examTag: '${json['examTag'] ?? ''}'.trim(),
      disclaimer: '${json['disclaimer'] ?? ''}'.trim(),
      wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
      url: '${json['url'] ?? ''}'.trim(),
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;
  final SyllabusBookKind kind;
  final String examTag;
  final String disclaimer;
  final int wordCount;
  final String url;
  final int bytes;

  String get unitLabel => switch (kind) {
    SyllabusBookKind.pattern => '句型',
    SyllabusBookKind.foundation => '条目',
    SyllabusBookKind.word => '词',
  };
}

class ServerSyllabusCatalog {
  const ServerSyllabusCatalog({
    this.version = 1,
    this.count = 0,
    this.baseUrl = '',
    this.items = const <ServerSyllabusCatalogItem>[],
  });

  factory ServerSyllabusCatalog.fromJson(Map<String, dynamic> json) {
    final List<ServerSyllabusCatalogItem> items =
        <ServerSyllabusCatalogItem>[];
    final Object? raw = json['items'];
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is! Map) continue;
        final ServerSyllabusCatalogItem parsed =
            ServerSyllabusCatalogItem.fromJson(
              Map<String, dynamic>.from(item),
            );
        if (parsed.id.isNotEmpty) items.add(parsed);
      }
    }
    return ServerSyllabusCatalog(
      version: (json['version'] as num?)?.toInt() ?? 1,
      count: (json['count'] as num?)?.toInt() ?? items.length,
      baseUrl: '${json['base_url'] ?? ''}'.trim(),
      items: List<ServerSyllabusCatalogItem>.unmodifiable(items),
    );
  }

  static const ServerSyllabusCatalog empty = ServerSyllabusCatalog();

  final int version;
  final int count;
  final String baseUrl;
  final List<ServerSyllabusCatalogItem> items;

  List<ServerSyllabusCatalogItem> ofKind(SyllabusBookKind kind) => items
      .where((ServerSyllabusCatalogItem item) => item.kind == kind)
      .toList(growable: false);
}
