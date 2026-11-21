import 'package:common_learn_english/features/words/domain/word_morphology.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splitEnglishSyllables breaks common multi-syllable words', () {
    expect(splitEnglishSyllables('banana').length, greaterThanOrEqualTo(2));
    expect(splitEnglishSyllables('wonderful').length, greaterThanOrEqualTo(2));
    expect(splitEnglishSyllables('cat'), <String>['cat']);
  });

  test('buildPhonicsSegments assigns color blocks', () {
    final List<PhonicsSegment> segments = buildPhonicsSegments('telephone');
    expect(segments, isNotEmpty);
    expect(segments.every((PhonicsSegment s) => s.text.isNotEmpty), isTrue);
  });

  test('matchRootsAndAffixes finds prefix root suffix', () {
    final List<AffixHit> hits = matchRootsAndAffixes('transportation');
    expect(hits.any((AffixHit h) => h.part == 'trans'), isTrue);
    expect(hits.any((AffixHit h) => h.part == 'port'), isTrue);
    expect(
      hits.any(
        (AffixHit h) => h.part == 'tion' || h.part == 'ation' || h.part == 'ion',
      ),
      isTrue,
    );
  });

  test('localEtymologyHint uses curated stories when available', () {
    final MorphologyInsight insight = analyzeWordMorphology('telephone');
    expect(insight.etymologyHintCn, contains('tele'));
  });

  test('confusablePairsFor returns curated foils', () {
    final List<ConfusablePair> pairs = confusablePairsFor('affect');
    expect(pairs, isNotEmpty);
    expect(pairs.first.foil, 'effect');
  });

  test('buildPhonicsGuideSteps ends with whole word when multi-syllable', () {
    final List<PhonicsGuideStep> steps = buildPhonicsGuideSteps('banana');
    expect(steps.length, greaterThanOrEqualTo(2));
    expect(steps.last.isWholeWord, isTrue);
    expect(steps.last.text.toLowerCase(), 'banana');
  });

  test('isVowelLetter marks a e i o u and medial y', () {
    expect(isVowelLetter('a'), isTrue);
    expect(isVowelLetter('y', prev: 'b'), isTrue);
    expect(isVowelLetter('y'), isFalse);
    expect(isVowelLetter('b'), isFalse);
  });
}
