import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:common_learn_english/features/words/data/word_root_catalog.dart';
import 'package:common_learn_english/features/words/domain/word_root_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    WordRootCatalog.resetForTest();
    final File file = File(
      '${Directory.current.path}/assets/data/wordroot/roots_app.json',
    );
    final String raw = await file.readAsString();
    expect(jsonDecode(raw), isA<Map>());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final String key = utf8.decode(message!.buffer.asUint8List());
      if (key == WordRootCatalog.assetPath ||
          key == WordRootCatalog.legacyAssetPath) {
        final Uint8List bytes = Uint8List.fromList(utf8.encode(raw));
        return ByteData.view(bytes.buffer);
      }
      return null;
    });
  });

  test('v2 meta loads and transport is fully manual', () async {
    final WordRootCatalog catalog = await WordRootCatalog.load();
    expect(catalog.meta['root_sense_manual'], 2953);
    expect(catalog.words.length, 2738);
    expect(catalog.roots.length, 771);

    final WordRootDetail? detail = catalog.queryWordDetail('transport');
    expect(detail, isNotNull);
    expect(detail!.parse.length, greaterThanOrEqualTo(2));
    expect(detail.allManualSense, isTrue);
    expect(
      detail.parse.map((WordRootParsePart p) => p.matchedForm).toList(),
      containsAll(<String>['trans', 'port']),
    );
    expect(
      detail.parse.firstWhere((WordRootParsePart p) => p.matchedForm == 'port').rootSense,
      '搬运',
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

  test('review path does not attach guess for unknown lemma', () async {
    final WordRootCatalog catalog = await WordRootCatalog.load();
    final WordRootDetail? guessed =
        catalog.resolveWord('brexitishxyz', allowGuess: true);
    final WordRootDetail? review =
        catalog.resolveWord('brexitishxyz', allowGuess: false);
    // Guess may or may not hit affixes; review must stay empty/null parse.
    expect(review == null || review.parse.isEmpty, isTrue);
    if (guessed != null && guessed.parse.isNotEmpty) {
      expect(guessed.isManual, isFalse);
    }
  });
}
