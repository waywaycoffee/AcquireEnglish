import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/words/data/word_root_catalog.dart';
import 'package:common_learn_english/features/words/domain/word_root_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final File file = File(
      '${Directory.current.path}/assets/data/wordroot/roots_full.json',
    );
    final String raw = await file.readAsString();
    // Ignore unused decode smoke — ensures asset exists and parses.
    expect(jsonDecode(raw), isA<Map>());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final String key = utf8.decode(message!.buffer.asUint8List());
      if (key == kWordRootAssetPath) {
        final Uint8List bytes = utf8.encode(raw);
        return ByteData.view(bytes.buffer);
      }
      return null;
    });
  });

  test('transport parses and recalls same-root words', () async {
    final WordRootCatalog catalog = await WordRootCatalog.load();
    final WordRootDetail? detail = catalog.queryWordDetail('transport');
    expect(detail, isNotNull);
    expect(detail!.parse, isNotEmpty);
    expect(
      detail.parse.any(
        (WordRootParsePart p) =>
            p.rootText.contains('port') || p.matchedForm.contains('port'),
      ),
      isTrue,
    );
    expect(
      detail.sameRootWords.map((WordRootWord w) => w.word),
      containsAll(<String>['export', 'import', 'portable']),
    );
  });

  test('root reverse lookup for port', () async {
    final WordRootCatalog catalog = await WordRootCatalog.load();
    final List<WordRootWord> words = catalog.queryRootWords('port');
    expect(words.map((WordRootWord w) => w.word), contains('transport'));
  });

  test('spell suggest for tranport', () async {
    final WordRootCatalog catalog = await WordRootCatalog.load();
    final List<WordRootSpellCandidate> tips = catalog.spellSuggest('tranport');
    expect(tips.map((WordRootSpellCandidate c) => c.word), contains('transport'));
  });
}
