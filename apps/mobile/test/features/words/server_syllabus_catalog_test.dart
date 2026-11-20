import 'package:common_learn_english/features/words/domain/server_syllabus_catalog.dart';
import 'package:common_learn_english/features/words/domain/syllabus_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses server catalog and filters by kind', () {
    final ServerSyllabusCatalog catalog = ServerSyllabusCatalog.fromJson(
      <String, dynamic>{
        'version': 1,
        'count': 2,
        'base_url': 'https://example.test',
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'cet4_core',
            'title': 'CET4',
            'kind': 'word',
            'examTag': 'CET4',
            'disclaimer': '',
            'wordCount': 10,
            'url': 'https://example.test/api/syllabus/books/cet4_core',
            'bytes': 100,
          },
          <String, Object?>{
            'id': 'foundation_ipa_48',
            'title': 'IPA',
            'kind': 'foundation',
            'examTag': 'IPA',
            'disclaimer': '',
            'wordCount': 48,
            'url': 'https://example.test/api/syllabus/books/foundation_ipa_48',
            'bytes': 50,
          },
        ],
      },
    );
    expect(catalog.count, 2);
    expect(catalog.ofKind(SyllabusBookKind.word).single.id, 'cet4_core');
    expect(
      catalog.ofKind(SyllabusBookKind.foundation).single.id,
      'foundation_ipa_48',
    );
  });
}
