import 'dart:io';
import 'dart:typed_data';

import 'package:common_learn_english/features/reading/data/reading_ingest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixtures are copied under test/fixtures/reading/ (see tools/reading_samples).
  final Directory fixtures = Directory('test/fixtures/reading');

  test('import sample TXT extracts readable English', () {
    final File file = File('${fixtures.path}/frankenstein_sample.txt');
    expect(file.existsSync(), isTrue, reason: 'run sample copy step first');
    final String text = parseTxtImport(file.readAsBytesSync());
    expect(text.toLowerCase(), contains('genevese'));
    expect(countWords(text), greaterThan(500));
  });

  test('import sample EPUB extracts chapter text', () {
    final File file = File('${fixtures.path}/christmas_carol.epub');
    expect(file.existsSync(), isTrue);
    final String text = parseEpubImport(
      Uint8List.fromList(file.readAsBytesSync()),
    );
    expect(text.toLowerCase(), contains('marley'));
    expect(countWords(text), greaterThan(1000));
    expect(titleFromFilename(file.path), 'christmas_carol');
  });
}
